<#
.SYNOPSIS
  Local Gemini helper for Drone Catchers (see AUTOMATION.md).

.DESCRIPTION
  Uses YOUR Gemini subscription (Gemini CLI logged in with your Google account), not an API key.
  Every -IntervalMinutes it looks at the GitHub Issues assigned to you with the label agent:gemini.
  If the lead has work for you (new Issue, an answer, a review) it runs Gemini CLI headless on it.
  If there is nothing to do it does nothing, so your quota is not used.

  Run it in a separate clone that you use only for this helper. Keep the window open.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\gemini-helper.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\gemini-helper.ps1 -Once
#>
param(
    [int]$IntervalMinutes = 60,
    [int]$TimeoutMinutes = 50,
    [string]$Model = '',
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$env:GEMINI_CLI_TRUST_WORKSPACE = 'true'
$Helpers = @('Kosmint', 'Cagan2112')
$MaxContinueRuns = 3   # stop re-running an unfinished Issue after this many runs with no new comments

$LogDir = Join-Path $env:LOCALAPPDATA 'drone-catchers-gemini'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$script:LogFile = Join-Path $LogDir 'helper.log'
$script:ContinueRuns = @{}

function Write-Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
}

function Invoke-Gh([string[]]$GhArgs) {
    # Runs gh and returns parsed JSON, or $null when gh printed nothing.
    $out = & gh @GhArgs
    if ($LASTEXITCODE -ne 0) { throw ('gh {0} failed (exit {1})' -f ($GhArgs -join ' '), $LASTEXITCODE) }
    $text = ($out | Out-String).Trim()
    if (-not $text) { return $null }
    return ($text | ConvertFrom-Json)
}

function New-Event($By, $At, $Body) {
    return [pscustomobject]@{ By = [string]$By; At = [datetime]$At; Body = [string]$Body }
}

function Get-Activity([int]$Issue, $Pr) {
    # All comments and reviews on the Issue and its PR, oldest first. '#nobot' comments are ignored.
    $events = New-Object System.Collections.Generic.List[object]
    $iv = Invoke-Gh @('issue', 'view', "$Issue", '--json', 'comments')
    foreach ($c in @($iv.comments)) { if ($c) { $events.Add((New-Event $c.author.login $c.createdAt $c.body)) } }
    if ($Pr) {
        $pv = Invoke-Gh @('pr', 'view', "$($Pr.number)", '--json', 'comments,reviews')
        foreach ($c in @($pv.comments)) { if ($c) { $events.Add((New-Event $c.author.login $c.createdAt $c.body)) } }
        foreach ($r in @($pv.reviews)) {
            if ($r -and $r.state -ne 'APPROVED') { $events.Add((New-Event $r.author.login $r.submittedAt $r.body)) }
        }
        $inline = Invoke-Gh @('api', "repos/{owner}/{repo}/pulls/$($Pr.number)/comments")
        foreach ($c in @($inline)) { if ($c) { $events.Add((New-Event $c.user.login $c.created_at $c.body)) } }
    }
    return @($events | Where-Object { $_.Body -notmatch '#nobot' } | Sort-Object At)
}

function Find-Work {
    $issues = @(Invoke-Gh @('issue', 'list', '--assignee', '@me', '--label', 'agent:gemini', '--state', 'open', '--json', 'number,title,labels')) | Where-Object { $_ }
    if (-not $issues) { return $null }
    $prs = @(Invoke-Gh @('pr', 'list', '--state', 'open', '--json', 'number,headRefName,isDraft')) | Where-Object { $_ }

    foreach ($i in ($issues | Sort-Object number)) {
        $labels = @($i.labels | ForEach-Object { $_.name })
        if ($labels -contains 'otomasyon-durdur' -or $labels -contains 'studio') { continue }
        $pr = $prs | Where-Object { $_.headRefName -like "gemini/$($i.number)-*" } | Select-Object -First 1
        $events = Get-Activity $i.number $pr
        $mine = @($events | Where-Object { $_.By -eq $script:Me })
        $last = $events | Select-Object -Last 1

        $trigger = $null
        if ($mine.Count -eq 0) {
            $trigger = 'assigned'
        } elseif ($last -and $last.By -ne $script:Me) {
            if ($pr) { $trigger = 'pr-comment' } else { $trigger = 'issue-comment' }
        } elseif ($labels -contains 'soru') {
            $trigger = $null   # waiting for the lead's answer
        } elseif ((-not $pr) -or $pr.isDraft) {
            $trigger = 'continue'   # unfinished work from an earlier run
        }

        if ($trigger -eq 'continue') {
            $n = 0
            if ($script:ContinueRuns.ContainsKey($i.number)) { $n = $script:ContinueRuns[$i.number] }
            if ($n -ge $MaxContinueRuns) {
                Write-Log ("Issue #{0}: unfinished after {1} runs with no new comments; skipping until someone comments." -f $i.number, $n)
                continue
            }
            $script:ContinueRuns[$i.number] = $n + 1
        } elseif ($trigger) {
            $script:ContinueRuns[$i.number] = 0
        }

        if ($trigger) {
            return [pscustomobject]@{ Issue = $i.number; Title = $i.title; Pr = $pr; Trigger = $trigger }
        }
    }
    return $null
}

function Get-GeminiCommand {
    $cmd = Get-Command 'gemini.cmd' -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command 'gemini.exe' -ErrorAction SilentlyContinue }
    if (-not $cmd) { throw 'Gemini CLI not found. Install it with: npm install -g @google/gemini-cli' }
    return $cmd.Source
}

function Invoke-GeminiRun($Work) {
    git fetch --prune origin
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }
    if (git status --porcelain) {
        Write-Log 'This folder has uncommitted changes, skipping this round. Use this clone only for the Gemini helper.'
        return
    }

    $branch = ''
    if ($Work.Pr) {
        $branch = $Work.Pr.headRefName
    } else {
        $refs = @(Invoke-Gh @('api', "repos/{owner}/{repo}/git/matching-refs/heads/gemini/$($Work.Issue)-")) | Where-Object { $_ }
        if ($refs) { $branch = ($refs | Select-Object -First 1).ref -replace '^refs/heads/', '' }
    }
    if ($branch) { git checkout -q -B $branch "origin/$branch" } else { git checkout -q --detach origin/main }
    if ($LASTEXITCODE -ne 0) { throw 'git checkout failed' }

    $trigger = $Work.Trigger
    if ($trigger -eq 'continue') { $trigger = 'assigned' }   # helper.md: continue on the existing branch
    $prText = 'none yet'; if ($Work.Pr) { $prText = "#$($Work.Pr.number)" }
    $branchText = 'none yet'; if ($branch) { $branchText = $branch }

    $header = @(
        '## This run',
        '- Agent: gemini',
        "- Where: local (your human's PC, gh logged in as $script:Me)",
        "- Working for: $script:Me",
        "- Issue: #$($Work.Issue)",
        "- Pull request: $prText",
        "- Branch: $branchText",
        "- Trigger: $trigger",
        ''
    ) -join "`n"
    # Always the instructions from main, so a branch can't rewrite its own prompt.
    $instructions = (git show 'origin/main:.github/agents/helper.md') -join "`n"
    $promptFile = Join-Path $LogDir 'prompt.md'
    [System.IO.File]::WriteAllText($promptFile, $header + "`n" + $instructions + "`n", $Utf8)

    $runLog = Join-Path $LogDir ('issue{0}-{1}.log' -f $Work.Issue, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $modelArg = ''
    if ($Model) { $modelArg = "-m `"$Model`" " }
    $cmdLine = '"{0}" {1}--approval-mode auto_edit -p "Follow the instructions above." < "{2}" > "{3}" 2>&1' -f $script:Gemini, $modelArg, $promptFile, $runLog

    Write-Log ("Issue #{0} ({1}): starting Gemini, trigger {2}. Log: {3}" -f $Work.Issue, $Work.Title, $Work.Trigger, $runLog)
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/s', '/c', "`"$cmdLine`"") -NoNewWindow -PassThru
    if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        & taskkill /T /F /PID $proc.Id | Out-Null
        Write-Log ("Issue #{0}: Gemini timed out after {1} minutes and was stopped." -f $Work.Issue, $TimeoutMinutes)
    } else {
        Write-Log ("Issue #{0}: Gemini finished (exit {1})." -f $Work.Issue, $proc.ExitCode)
    }
    if (git status --porcelain) {
        Write-Log 'Warning: Gemini left uncommitted changes. Look at them, then commit or discard before the next round.'
    } else {
        git checkout -q --detach origin/main
    }
}

# ---- start ----
$root = (git rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) { throw 'Run this script inside your drone-catchers clone.' }
Set-Location $root.Trim()

foreach ($tool in @('git', 'gh')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not installed." }
}
$script:Gemini = Get-GeminiCommand
$script:Me = (& gh api user --jq .login | Out-String).Trim()
if ($Helpers -notcontains $script:Me) {
    throw "This runner is for the Gemini helpers ($($Helpers -join ', ')). gh is logged in as '$script:Me'."
}

# Install the headless-only tool policy (git and gh only), preferring the copy on main.
$policyDir = Join-Path $env:USERPROFILE '.gemini\policies'
New-Item -ItemType Directory -Force -Path $policyDir | Out-Null
git fetch --prune origin
$policy = (git show 'origin/main:scripts/gemini-policy.toml') -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $policy) { $policy = Get-Content (Join-Path $root.Trim() 'scripts\gemini-policy.toml') -Raw }
[System.IO.File]::WriteAllText((Join-Path $policyDir 'drone-catchers-helper.toml'), $policy, $Utf8)

Write-Log ("Gemini helper started for {0}. Checking every {1} minutes. Stop with Ctrl+C." -f $script:Me, $IntervalMinutes)
while ($true) {
    try {
        $work = Find-Work
        if ($work) { Invoke-GeminiRun $work } else { Write-Log 'Nothing to do.' }
    } catch {
        Write-Log ("Error: {0}" -f $_.Exception.Message)
    }
    if ($Once) { break }
    Start-Sleep -Seconds ($IntervalMinutes * 60)
}

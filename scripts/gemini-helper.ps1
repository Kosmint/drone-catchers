<#
.SYNOPSIS
  Local Gemini helper for Drone Catchers (see AUTOMATION.md).

.DESCRIPTION
  Runs the Antigravity CLI (agy) with YOUR Antigravity / Google AI Pro subscription. No API key.
  Every -IntervalMinutes it looks at the GitHub Issues assigned to you with the label agent:gemini.
  If the lead has work for you (new Issue, an answer, a review) it runs agy headless on it.
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
    [string]$Model = '',          # normal tier: agy's default model unless you set one here
    [string]$StrongModel = '',    # model:guclu tier: --effort high, plus this model when set
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$Helpers = @('Kosmint', 'Cagan2112')
# Only these people's comments and reviews wake a helper and count as instructions.
# Everyone else's text is untrusted data (helper.md says the same to the agent).
$Team = @('muhammet842', 'Kosmint', 'Cagan2112')
$StrongLabel = 'model:guclu'
$MaxContinueRuns = 3          # stop re-running an unfinished Issue after this many runs with no new comments
$PromptName = '.agy-helper-prompt.md'   # written in the clone, hidden from git via .git/info/exclude
$CmdFileName = '.agy-cmd.txt'           # the agent writes its git/gh command here, also hidden from git

# Tool permissions for agy (merged into ~/.gemini/antigravity-cli/settings.json).
# agy headless matches command(...) allow-rules against the WHOLE command line, exactly: command(git),
# command(git *) and friends never match, and only a lone command(*) is a wildcard. So agy gets ONE
# exact grant, for the gate script scripts/agy-git.ps1, which runs only git/gh and refuses the rest.
# The Deny rules below are an extra layer (they apply even when you use Antigravity yourself).
$DenyRules = @(
    'command(git push --force)', 'command(git push -f)', 'command(git config --global)',
    'command(gh pr merge)', 'command(gh repo delete)', 'command(gh secret)',
    'command(gh variable)', 'command(gh auth)', 'command(gh workflow)', 'command(gh label)'
)

$LogDir = Join-Path $env:LOCALAPPDATA 'drone-catchers-gemini'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$script:LogFile = Join-Path $LogDir 'helper.log'
$script:GateCmd = ''   # the exact command line agy is allowed to run (set in Install-Gate)
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

function Test-TeamMember([string]$Login) {
    # GitHub logins are case-insensitive; -contains compares case-insensitively.
    return [bool]($Login -and ($Team -contains $Login))
}

function Get-Activity([int]$Issue, $Pr) {
    # Team members' comments and reviews on the Issue and its PR, oldest first.
    # '#nobot' comments and anything written by people outside the team (or bots) are ignored.
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
    return @($events | Where-Object { (Test-TeamMember $_.By) -and $_.Body -notmatch '#nobot' } | Sort-Object At)
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
            $tier = 'normal'
            if ($labels -contains $StrongLabel) { $tier = 'guclu' }
            return [pscustomobject]@{ Issue = $i.number; Title = $i.title; Pr = $pr; Trigger = $trigger; Tier = $tier }
        }
    }
    return $null
}

function Get-AgyCommand {
    $cmd = Get-Command 'agy' -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $guess = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
        if (Test-Path $guess) { return $guess }
        throw 'Antigravity CLI (agy) not found. Install it in PowerShell with: irm https://antigravity.google/cli/install.ps1 | iex   then open a new terminal.'
    }
    return $cmd.Source
}

function Add-Unique($List, [string[]]$Items) {
    $all = @()
    foreach ($x in @($List)) { if ($x) { $all += [string]$x } }
    foreach ($x in $Items) { if ($all -notcontains $x) { $all += $x } }
    return , $all
}

function Install-Gate {
    # Copy the gate outside the clone (the agent can't edit it there) and build its exact command line.
    $src = Join-Path $PSScriptRoot 'agy-git.ps1'
    if (-not (Test-Path $src)) { throw "Missing $src" }
    $dst = Join-Path $LogDir 'agy-git.ps1'
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $pathText = $dst
    if ($pathText -match '\s') { $pathText = '"' + $pathText + '"' }
    $script:GateCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File ' + $pathText
}

function Set-AgySettings([string]$Workspace) {
    # Merge our permission rules and trust this clone in ~/.gemini/antigravity-cli/settings.json.
    $dir = Join-Path $env:USERPROFILE '.gemini\antigravity-cli'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir 'settings.json'
    $obj = $null
    if (Test-Path $file) {
        $raw = [System.IO.File]::ReadAllText($file)
        if ($raw.Trim()) {
            try { $obj = $raw | ConvertFrom-Json }
            catch {
                throw ("Can't read $file (comments or invalid JSON?). Add these rules yourself with /permissions in agy: allow command(" +
                       $script:GateCmd + '); deny ' + ($DenyRules -join ', '))
            }
        }
        $backup = "$file.before-drone-catchers"
        if (-not (Test-Path $backup)) { Copy-Item $file $backup }
    }
    if (-not $obj) { $obj = New-Object psobject }
    if (-not $obj.PSObject.Properties['permissions']) {
        $obj | Add-Member -NotePropertyName 'permissions' -NotePropertyValue (New-Object psobject)
    }
    $perm = $obj.permissions
    foreach ($kind in @('allow', 'deny')) {
        if (-not $perm.PSObject.Properties[$kind]) { $perm | Add-Member -NotePropertyName $kind -NotePropertyValue @() }
    }
    $perm.allow = Add-Unique $perm.allow @("command($script:GateCmd)")
    $perm.deny = Add-Unique $perm.deny $DenyRules
    if (-not $obj.PSObject.Properties['trustedWorkspaces']) {
        $obj | Add-Member -NotePropertyName 'trustedWorkspaces' -NotePropertyValue @()
    }
    $obj.trustedWorkspaces = Add-Unique $obj.trustedWorkspaces @($Workspace)
    [System.IO.File]::WriteAllText($file, ($obj | ConvertTo-Json -Depth 20), $Utf8)
}

function Get-TierArgs([string]$Tier) {
    # Extra agy arguments for a model tier (AUTOMATION.md "Model tiers").
    #   normal: agy's default model, or -Model when set.
    #   guclu:  --effort high, plus -StrongModel when set (else -Model when set).
    $parts = @()
    if ($Tier -eq 'guclu') {
        $parts += '--effort high'
        if ($StrongModel) { $parts += ('--model "{0}"' -f $StrongModel) }
        elseif ($Model) { $parts += ('--model "{0}"' -f $Model) }
    } elseif ($Model) {
        $parts += ('--model "{0}"' -f $Model)
    }
    if ($parts.Count -eq 0) { return '' }
    return (($parts -join ' ') + ' ')
}

function Invoke-Agy([string]$PromptText, [string]$LogPath, [int]$Minutes, [string]$Tier = 'normal') {
    # Runs agy headless in the clone with the prompt from $PromptName. Returns the exit code (or $null on time-out).
    [System.IO.File]::WriteAllText((Join-Path $script:Root $PromptName), $PromptText, $Utf8)
    $modelArg = Get-TierArgs $Tier
    $cmdLine = '"{0}" {1}--mode accept-edits --print-timeout {2}m -p "Read the file {3} in this folder and follow its instructions exactly." > "{4}" 2>&1' -f `
        $script:Agy, $modelArg, $Minutes, $PromptName, $LogPath
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/s', '/c', "`"$cmdLine`"") -NoNewWindow -PassThru
    $null = $proc.Handle   # keep the handle so ExitCode is available afterwards
    if (-not $proc.WaitForExit(($Minutes + 5) * 60 * 1000)) {
        & taskkill /T /F /PID $proc.Id | Out-Null
        return $null
    }
    return $proc.ExitCode
}

function Get-GateNote {
    # Told to agy in every run: how to run git/gh in headless mode.
    return @(
        '## How to run git and gh in this environment (read this first)',
        'Headless mode only allows ONE shell command line. You cannot run `git ...` or `gh ...` directly: that is auto-denied.',
        'Instead, for EVERY git or gh command, do these two steps:',
        "1. Write the file ``$CmdFileName`` (in the repository root, overwrite it each time) with your file-writing tool. Line 1 is ``git`` or ``gh``. Every following line is exactly ONE argument, taken literally (no quoting, no escaping, no shell syntax such as pipes, redirects or &&). Example for ``git commit -m ""add beam""``: the lines are ``git``, ``commit``, ``-m``, ``add beam``.",
        '2. Run exactly this command line, character for character, and nothing else:',
        '',
        $script:GateCmd,
        '',
        'Its output is the output of your git/gh command, followed by `[exit N]`. `REFUSED: ...` means the gate blocks that command; do not try to get around it.',
        "Put long text in a file and pass it by path: ``git commit -F <file>``, ``gh pr create --body-file <file>``, ``gh issue comment <n> --body-file <file>``, ``gh pr comment <n> --body-file <file>``.",
        "``gh`` only works on Kosmint/drone-catchers. ``gh api`` is GET only and only for paths written out in full, e.g. ``repos/Kosmint/drone-catchers/pulls/<n>/comments`` (not ``{owner}/{repo}``). ``gh pr review`` and ``gh pr merge`` are refused. git allows only: status, add, commit, push, fetch, pull, checkout, switch, branch, log, diff, show, rev-parse, restore, rm, mv, merge, rebase --continue/--abort, ls-files. Use plain ASCII for titles and short messages. Do not commit ``$CmdFileName`` or ``$PromptName`` (they are hidden from git). Do not create other scripts.",
        ''
    ) -join "`n"
}

function Test-Blocked([string]$LogPath) {
    return [bool](Select-String -Path $LogPath -Pattern 'headless mode cannot prompt|auto-denied' -Quiet -ErrorAction SilentlyContinue)
}

function Invoke-HelperRun($Work) {
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
        '- Agent: gemini (Antigravity CLI)',
        "- Where: local (your human's PC, gh logged in as $script:Me)",
        "- Working for: $script:Me",
        "- Issue: #$($Work.Issue)",
        "- Pull request: $prText",
        "- Branch: $branchText",
        "- Trigger: $trigger",
        "- Model tier: $($Work.Tier)",
        ''
    ) -join "`n"
    # Always the instructions from main, so a branch can't rewrite its own prompt.
    $instructions = (git show 'origin/main:.github/agents/helper.md') -join "`n"

    $runLog = Join-Path $LogDir ('issue{0}-{1}.log' -f $Work.Issue, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Log ("Issue #{0} ({1}): starting agy, trigger {2}, tier {3}. Log: {4}" -f $Work.Issue, $Work.Title, $Work.Trigger, $Work.Tier, $runLog)
    $code = Invoke-Agy ($header + "`n" + (Get-GateNote) + "`n" + $instructions + "`n") $runLog $TimeoutMinutes $Work.Tier
    if ($null -eq $code) {
        Write-Log ("Issue #{0}: agy timed out after {1} minutes and was stopped." -f $Work.Issue, $TimeoutMinutes)
    } elseif ($code -ne 0) {
        Write-Log ("Issue #{0}: agy failed (exit {1}). Last lines of the log:" -f $Work.Issue, $code)
        Get-Content $runLog -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "    $_" }
    } elseif (Test-Blocked $runLog) {
        Write-Log ("Issue #{0}: agy finished but was blocked by a permission rule (exit {1}). Last lines of the log:" -f $Work.Issue, $code)
        Get-Content $runLog -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "    $_" }
    } else {
        Write-Log ("Issue #{0}: agy finished." -f $Work.Issue)
    }

    if (git status --porcelain) {
        Write-Log 'Warning: agy left uncommitted changes. Look at them, then commit or discard before the next round.'
    } else {
        git checkout -q --detach origin/main
    }
}

# ---- start ----
$rootOut = (git rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) { throw 'Run this script inside your drone-catchers clone.' }
$script:Root = ($rootOut | Out-String).Trim().Replace('/', '\')
Set-Location $script:Root

foreach ($tool in @('git', 'gh')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not installed." }
}
$script:Agy = Get-AgyCommand
$script:Me = (& gh api user --jq .login | Out-String).Trim()
if ($Helpers -notcontains $script:Me) {
    throw "This runner is for the Gemini helpers ($($Helpers -join ', ')). gh is logged in as '$script:Me'."
}

# Keep the prompt file out of git, so it never counts as an uncommitted change.
$exclude = Join-Path $script:Root '.git\info\exclude'
foreach ($hidden in @($PromptName, $CmdFileName)) {
    if (-not (Select-String -Path $exclude -SimpleMatch $hidden -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $exclude -Value $hidden -Encoding UTF8
    }
}

# git needs an author to commit. If this PC has none, give agy one through environment variables
# (this process only; your git config is not touched). The gate refuses git config / git -c.
$gitName = (git config user.name | Out-String).Trim()
$gitEmail = (git config user.email | Out-String).Trim()
if (-not $gitName) { $env:GIT_AUTHOR_NAME = $script:Me; $env:GIT_COMMITTER_NAME = $script:Me }
if (-not $gitEmail) {
    $userId = (& gh api user --jq .id | Out-String).Trim()
    $noreply = '{0}@users.noreply.github.com' -f $script:Me
    if ($userId -match '^\d+$') { $noreply = '{0}+{1}' -f $userId, $noreply }
    $env:GIT_AUTHOR_EMAIL = $noreply
    $env:GIT_COMMITTER_EMAIL = $noreply
}

Install-Gate
Set-AgySettings $script:Root

# Check that agy is signed in before waiting for work.
$checkLog = Join-Path $LogDir 'login-check.log'
Write-Log 'Checking the Antigravity CLI sign-in...'
# The check also proves that agy can run the gate: it must print true for git rev-parse --is-inside-work-tree through it.
[System.IO.File]::WriteAllText((Join-Path $script:Root $CmdFileName), "git`nrev-parse`n--is-inside-work-tree`n", $Utf8)
$checkPrompt = (Get-GateNote) + "`nTest: run git rev-parse --is-inside-work-tree through the gate now (the file $CmdFileName already contains it). Then reply with the gate output and the word OK."
$code = Invoke-Agy $checkPrompt $checkLog 3
$checkText = ''
if (Test-Path $checkLog) { $checkText = [System.IO.File]::ReadAllText($checkLog) }
if ($code -eq 0 -and $checkText -notmatch '(?m)^\s*true\s*$') {
    Write-Log 'agy ran, but it could not run git through the gate script. Last lines of its output:'
    Get-Content $checkLog -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "    $_" }
    throw 'The permission setup does not work (see AUTOMATION.md, If agy is blocked). Fix it, then start this script again.'
}
if ($code -ne 0) {
    Write-Log 'agy could not run. Last lines of its output:'
    Get-Content $checkLog -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "    $_" }
    throw 'Sign in first: run  agy  in this folder, choose Google OAuth with your Google AI Pro account, trust the folder, then exit with /quit. Then start this script again.'
}

Write-Log ("Gemini helper started for {0}. Checking every {1} minutes. Stop with Ctrl+C." -f $script:Me, $IntervalMinutes)
while ($true) {
    try {
        $work = Find-Work
        if ($work) { Invoke-HelperRun $work } else { Write-Log 'Nothing to do.' }
    } catch {
        Write-Log ("Error: {0}" -f $_.Exception.Message)
    }
    if ($Once) { break }
    Start-Sleep -Seconds ($IntervalMinutes * 60)
}

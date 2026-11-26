<#
.SYNOPSIS
  Command gate for the local Gemini helper (see AUTOMATION.md).

.DESCRIPTION
  agy (Antigravity CLI) in headless mode can only run shell commands that match an allow-rule
  EXACTLY (no prefix or wildcard matching). So the helper is granted ONE fixed command line:
  this script. The agent writes the real command into .agy-cmd.txt in the current folder
  (first line = git or gh, every following line = one argument, taken literally) and then runs this
  script. The script is an ALLOW-LIST: it runs only the git/gh forms below, directly (no shell, so no
  pipes, redirects or injection), and refuses everything else.

  gemini-helper.ps1 copies this file outside the clone before every run, so the agent cannot edit it.
  git runs with hooks, fsmonitor, pager and editor switched off, and the gate refuses to run when
  .git/config contains keys that can run programs.
#>
$ErrorActionPreference = 'Continue'
$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8
$Here = (Get-Location).Path
$CmdFile = Join-Path $Here '.agy-cmd.txt'

function Stop-Gate([string]$Message) {
    Write-Output ('REFUSED: ' + $Message)
    exit 2
}

if (-not (Test-Path -LiteralPath $CmdFile)) { Stop-Gate 'no .agy-cmd.txt in the current folder. Write it first (line 1: git or gh, then one argument per line).' }
if (-not (Test-Path -LiteralPath (Join-Path $Here '.git') -PathType Container)) { Stop-Gate 'run this from the root of the clone.' }

$lines = New-Object System.Collections.Generic.List[string]
foreach ($l in [System.IO.File]::ReadAllLines($CmdFile, $Utf8)) { $lines.Add($l.TrimEnd("`r")) }
while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
if ($lines.Count -eq 0) { Stop-Gate '.agy-cmd.txt is empty.' }

$tool = $lines[0].Trim().ToLowerInvariant()
$cmdArgs = @()
for ($i = 1; $i -lt $lines.Count; $i++) { $cmdArgs += $lines[$i] }
if ($tool -ne 'git' -and $tool -ne 'gh') { Stop-Gate 'only git and gh are allowed (line 1 of .agy-cmd.txt).' }
if ($cmdArgs.Count -eq 0) { Stop-Gate 'no subcommand.' }

# Lower-case view with "--flag=value" split in two, so option checks cannot be dodged with "=".
$norm = New-Object System.Collections.Generic.List[string]
foreach ($a in $cmdArgs) {
    $t = $a.ToLowerInvariant()
    if ($t -match '^--[a-z0-9-]+=') {
        $eq = $t.IndexOf('=')
        $norm.Add($t.Substring(0, $eq)); $norm.Add($t.Substring($eq + 1))
    } else { $norm.Add($t) }
}
$low = @($norm)
$sub = $low[0]
$rest = @()
if ($low.Count -gt 1) { $rest = @($low[1..($low.Count - 1)]) }

function Test-Token([string]$Name) { return ($low -contains $Name) }
function Test-Match([string]$Pattern) {
    foreach ($t in $low) { if ($t -match $Pattern) { return $true } }
    return $false
}

# Never allowed with either tool: options that run programs, open editors/browsers or write files.
if (Test-Match '^--(exec|exec-path|upload-pack|receive-pack|config-env|config|output|ext-diff|textconv|editor|web|git-dir|work-tree|hostname)$') { Stop-Gate 'that option is not allowed.' }
if (Test-Match '^-(c|e|w|o)$') { Stop-Gate 'that option is not allowed.' }
if ($sub.StartsWith('-')) { Stop-Gate 'put the subcommand first; global options are not allowed.' }

$runArgs = $cmdArgs
$gitPrefix = @()

if ($tool -eq 'git') {
    $okGit = @('status', 'diff', 'log', 'show', 'add', 'rm', 'mv', 'restore', 'checkout', 'switch', 'branch', 'commit', 'fetch', 'push', 'rev-parse', 'ls-files', 'ls-remote', 'stash', 'reset', 'blame', 'grep', 'describe', 'merge-base', 'cat-file', 'remote')
    if ($okGit -notcontains $sub) { Stop-Gate "git $sub is not allowed." }
    if ($sub -eq 'remote' -and -not ($rest.Count -le 1 -and ($rest.Count -eq 0 -or $rest[0] -eq '-v'))) { Stop-Gate 'only git remote and git remote -v are allowed.' }
    if ($sub -eq 'push') {
        # Only: git push [-u|--set-upstream] origin <gemini|claude>/<branch>   (explicit branch, never main).
        $r = @($cmdArgs | Select-Object -Skip 1)
        if ($r.Count -ge 1 -and ($r[0] -ceq '-u' -or $r[0] -ceq '--set-upstream')) { $r = @($r | Select-Object -Skip 1) }
        if ($r.Count -ne 2 -or $r[0] -cne 'origin') { Stop-Gate 'allowed push form: git push [-u] origin <gemini|claude>/<branch>' }
        if ($r[1] -cnotmatch '^(gemini|claude)/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$') { Stop-Gate 'push only branches named gemini/... or claude/..., one explicit branch.' }
    }
    if ($sub -eq 'branch' -and (Test-Match '^--(set-upstream-to|unset-upstream|edit-description)')) { Stop-Gate 'that git branch option is not allowed.' }
    # Refuse a clone whose config can run programs (the agent can edit .git/config with its file tools).
    $cfgPath = Join-Path $Here '.git\config'
    if (Test-Path -LiteralPath $cfgPath) {
        $cfg = [System.IO.File]::ReadAllText($cfgPath).ToLowerInvariant()
        if ($cfg -match '(?m)^\s*(\[alias|\[include|\[filter|\[credential|\[core\]|\[url |\[diff |\[merge |\[gpg|\[sequence|\[uploadpack|\[receive|\[protocol|\[pager|\[http)') {
            $bad = ($cfg -split "`n" | Where-Object { $_ -match '^\s*(fsmonitor|sshcommand|hookspath|pager|editor|askpass|program|command|textconv|clean|smudge|process|insteadof|helper|external|gitproxy|path|proxy|extraheader|cainfo|gpgsign|signingkey)\s*=' -or $_ -match '^\s*\[(alias|include|includeif|filter|credential|url |diff |merge |gpg|pager|http|protocol|uploadpack|receive)' } | Select-Object -First 1)
            if ($bad) { Stop-Gate ('.git/config contains a setting that can run programs or redirect git (' + $bad.Trim() + '). Ask a human to clean it.') }
        }
    }
    $noHooks = Join-Path $PSScriptRoot 'nohooks'
    if (-not (Test-Path -LiteralPath $noHooks)) { New-Item -ItemType Directory -Force -Path $noHooks | Out-Null }
    $gitPrefix = @('-c', ('core.hooksPath=' + $noHooks), '-c', 'core.fsmonitor=false', '-c', 'core.pager=cat', '-c', 'core.editor=true', '-c', 'protocol.ext.allow=never', '-c', 'core.askPass=')
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_EDITOR = 'true'
    $env:GIT_PAGER = 'cat'
    $env:GIT_TERMINAL_PROMPT = '0'
    Remove-Item Env:GIT_EXTERNAL_DIFF -ErrorAction SilentlyContinue
    Remove-Item Env:GIT_SSH_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:GIT_ASKPASS -ErrorAction SilentlyContinue
}

if ($tool -eq 'gh') {
    # Allow-list of "<group> <verb>". Everything else (merge, review, secret, auth, workflow, label,
    # repo changes, alias, extension, release ...) is refused.
    $okGh = @('issue view', 'issue list', 'issue comment', 'issue edit', 'pr view', 'pr list', 'pr create', 'pr ready', 'pr comment', 'pr edit', 'pr diff', 'pr checks', 'pr status', 'repo view')
    if ($sub -eq 'api') {
        if ($rest.Count -lt 1) { Stop-Gate 'gh api needs an endpoint.' }
        # Read-only: no method flag, no body fields, no input file, no GraphQL.
        if (Test-Match '^(-x|--method|-f|--field|--raw-field|--input)') { Stop-Gate 'gh api is read-only: method flags and body fields are not allowed.' }
        if (Test-Match 'graphql') { Stop-Gate 'gh api graphql is not allowed.' }
        foreach ($a in $cmdArgs) { if ($a -cmatch '^-[A-Za-z]*[fFXx]') { Stop-Gate 'gh api: short flags that set a method or body are not allowed.' } }
    } else {
        $pair = if ($low.Count -ge 2) { $low[0] + ' ' + $low[1] } else { $low[0] }
        if ($okGh -notcontains $pair) { Stop-Gate "gh $pair is not allowed." }
        # People and labels are not yours to change. Only the label "soru" may be added or removed.
        if (Test-Match '^--(add|remove)?-?(assignee|reviewer|project|milestone)$') { Stop-Gate 'never change assignees, reviewers, projects or milestones.' }
        foreach ($a in $cmdArgs) { if ($a -cmatch '^-[ar]') { Stop-Gate 'short flags -a / -r (assignee, reviewer) are not allowed.' } }
        for ($i = 0; $i -lt $low.Count; $i++) {
            if ($low[$i] -match '^--(add|remove)-label$') {
                if ($i + 1 -ge $low.Count) { Stop-Gate 'missing label.' }
                foreach ($part in ($low[$i + 1] -split ',')) { if ($part.Trim() -ne 'soru') { Stop-Gate 'the only label you may add or remove is soru.' } }
            }
        }
        $isList = ($pair -eq 'issue list' -or $pair -eq 'pr list')
        if ((Test-Match '^(--label$|-l)') -and -not $isList) { Stop-Gate 'labels may only be used for filtering (gh ... list --label).' }
    }
}

# Run directly, no shell. stdin is closed so nothing waits for input.
$null | & $tool @gitPrefix @runArgs 2>&1 | ForEach-Object { [string]$_ }
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }
Write-Output ('[exit {0}]' -f $code)
exit $code

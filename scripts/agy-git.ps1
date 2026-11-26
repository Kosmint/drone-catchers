<#
.SYNOPSIS
  Command gate for the local Gemini helper (see AUTOMATION.md).

.DESCRIPTION
  agy (Antigravity CLI) in headless mode can only run shell commands that match an allow-rule
  EXACTLY (no prefix or wildcard matching). So the helper is granted ONE fixed command line:
  this script. The agent writes the real command into .agy-cmd.txt in the current folder
  (first line = git or gh, every following line = one argument, taken literally) and then runs this
  script. The script runs only git or gh, directly (no shell, so no pipes, redirects or injection),
  and refuses operations the helper must never do.

  gemini-helper.ps1 copies this file outside the clone before every run, so the agent cannot edit it.
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
if (-not (Test-Path -LiteralPath (Join-Path $Here '.git'))) { Stop-Gate 'run this from the root of the clone.' }

$lines = New-Object System.Collections.Generic.List[string]
foreach ($l in [System.IO.File]::ReadAllLines($CmdFile, $Utf8)) { $lines.Add($l.TrimEnd("`r")) }
while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
if ($lines.Count -eq 0) { Stop-Gate '.agy-cmd.txt is empty.' }

$tool = $lines[0].Trim().ToLowerInvariant()
$cmdArgs = @()
for ($i = 1; $i -lt $lines.Count; $i++) { $cmdArgs += $lines[$i] }
if ($tool -ne 'git' -and $tool -ne 'gh') { Stop-Gate 'only git and gh are allowed (line 1 of .agy-cmd.txt).' }
$low = @($cmdArgs | ForEach-Object { $_.ToLowerInvariant() })

function Test-Token([string]$Name) { return ($low -contains $Name) }
function Test-Pair([string]$A, [string]$B) {
    for ($i = 0; $i -lt ($low.Count - 1); $i++) { if ($low[$i] -eq $A -and $low[$i + 1] -eq $B) { return $true } }
    return $false
}
function Test-Match([string]$Pattern) {
    foreach ($t in $low) { if ($t -match $Pattern) { return $true } }
    return $false
}

if ($tool -eq 'git') {
    if ((Test-Token '-c') -or (Test-Match '^--(exec-path|config-env|upload-pack|receive-pack|exec|git-dir|work-tree)')) {
        Stop-Gate 'git -c, --exec-path, --upload-pack, --git-dir and similar options are not allowed.'
    }
    if (Test-Token 'config') { Stop-Gate 'git config is not allowed.' }
    if (Test-Token 'push') {
        if ((Test-Match '^--(force|force-with-lease|force-if-includes|mirror|delete|prune|all)') -or (Test-Token '-f') -or (Test-Token '-d')) {
            Stop-Gate 'force push, delete, mirror and --all are not allowed.'
        }
        if (Test-Match '^[+:]') { Stop-Gate 'refspecs starting with + or : (force or delete) are not allowed.' }
        if ((Test-Match '(^|[:/])main$') -or (Test-Match '(^|[:/])master$')) { Stop-Gate 'never push to main.' }
    }
    if ((Test-Token 'rebase') -and ((Test-Match '^--exec') -or (Test-Token '-x'))) { Stop-Gate 'git rebase --exec is not allowed.' }
}

if ($tool -eq 'gh') {
    foreach ($d in @('secret', 'variable', 'auth', 'workflow', 'label', 'alias', 'extension', 'ssh-key', 'gpg-key', 'codespace', 'config', 'ruleset', 'attestation')) {
        if (Test-Token $d) { Stop-Gate "gh $d is not allowed." }
    }
    if (Test-Pair 'pr' 'merge') { Stop-Gate 'gh pr merge is not allowed. Humans merge.' }
    if ((Test-Token 'repo') -and ((Test-Token 'delete') -or (Test-Token 'edit') -or (Test-Token 'archive') -or (Test-Token 'rename') -or (Test-Token 'create') -or (Test-Token 'fork') -or (Test-Token 'sync') -or (Test-Token 'deploy-key'))) {
        Stop-Gate 'gh repo changes are not allowed.'
    }
    if (Test-Match '^--(add|remove)-(assignee|reviewer|project)') { Stop-Gate 'never change assignees, reviewers or projects.' }
    if ((Test-Match '^--(assignee|reviewer|project|milestone)$') -and -not (Test-Token 'list')) { Stop-Gate 'never set assignees, reviewers or projects.' }
    if (Test-Token '--approve') { Stop-Gate 'helpers never approve PRs.' }
    # The only label a helper may add or remove is "soru".
    for ($i = 0; $i -lt ($low.Count - 1); $i++) {
        if ($low[$i] -match '^--(add|remove)-label$') {
            foreach ($part in ($low[$i + 1] -split ',')) {
                if ($part.Trim() -ne 'soru') { Stop-Gate 'the only label you may add or remove is soru.' }
            }
        }
    }
    if ((Test-Match '^(--label|-l)$') -and -not (Test-Token 'list')) { Stop-Gate 'labels may only be used for filtering (gh ... list --label).' }
    if (Test-Token 'api') {
        # gh api is read-only: GET only, no body fields, no GraphQL.
        for ($i = 0; $i -lt ($low.Count - 1); $i++) {
            if (($low[$i] -eq '-x' -or $low[$i] -eq '--method') -and $low[$i + 1] -ne 'get') { Stop-Gate 'gh api: only GET is allowed.' }
        }
        if (Test-Match '^(-f|--field|--raw-field|--input)$') { Stop-Gate 'gh api: body fields are not allowed (read-only).' }
        if (Test-Match 'graphql') { Stop-Gate 'gh api graphql is not allowed.' }
    }
}

# Run directly, no shell. stdin is closed so nothing waits for input.
$null | & $tool @cmdArgs 2>&1 | ForEach-Object { [string]$_ }
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }
Write-Output ('[exit {0}]' -f $code)
exit $code

<#
.SYNOPSIS
  Tests for scripts/agy-git.ps1 (the local Gemini helper's command gate).
.DESCRIPTION
  Builds a throw-away git clone in %TEMP%, writes .agy-cmd.txt for each case and runs the gate with
  AGY_GATE_DRYRUN=1, so the gate only checks and prints ALLOWED / REFUSED (nothing is executed,
  nothing touches GitHub). Exit code = number of failed cases.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tests\Test-AgyGate.ps1
#>
param([string]$GatePath = '')   # default: ../agy-git.ps1
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding $false
if (-not $GatePath) { $GatePath = Join-Path $PSScriptRoot '..\agy-git.ps1' }
$Gate = (Resolve-Path $GatePath).Path
$Clone = Join-Path ([System.IO.Path]::GetTempPath()) ('agy-gate-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Clone | Out-Null
Push-Location $Clone
& git init -q
& git remote add origin https://github.com/Kosmint/drone-catchers.git
$CleanConfig = [System.IO.File]::ReadAllText((Join-Path $Clone '.git\config'))

$script:Failed = 0
$script:Passed = 0

function Invoke-Gate([string[]]$Lines) {
    [System.IO.File]::WriteAllText((Join-Path $Clone '.agy-cmd.txt'), (($Lines -join "`n") + "`n"), $Utf8)
    $env:AGY_GATE_DRYRUN = '1'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Gate 2>&1 | Out-String
    return $out.Trim()
}

function Test-Case([string]$Expect, [string[]]$Lines, [string]$Why) {
    $out = Invoke-Gate $Lines
    $ok = $false
    if ($Expect -eq 'allow') { $ok = $out.StartsWith('ALLOWED:') } else { $ok = $out.StartsWith('REFUSED:') }
    $label = ($Lines -join ' ')
    if ($ok) {
        $script:Passed++
    } else {
        $script:Failed++
        Write-Host ("FAIL [{0}] {1}  ({2})`n      got: {3}" -f $Expect, $label, $Why, $out) -ForegroundColor Red
    }
}

function Set-Config([string]$Extra) {
    [System.IO.File]::WriteAllText((Join-Path $Clone '.git\config'), ($CleanConfig + $Extra), $Utf8)
}

try {
    # ---------------- existing behaviour (kept) ----------------
    Test-Case allow  @('git', 'status') 'plain status'
    Test-Case allow  @('git', 'add', 'plan/README.md') 'add'
    Test-Case allow  @('git', 'commit', '-m', 'Fix wording') 'commit -m'
    Test-Case allow  @('git', 'commit', '-s', '-m', 'x') 'commit -s (signoff) is harmless'
    Test-Case allow  @('git', 'push', '-u', 'origin', 'gemini/8-fix') 'push own branch'
    Test-Case refuse @('git', 'push', 'origin', 'main') 'push main'
    Test-Case refuse @('git', 'push', '--force', 'origin', 'gemini/8-fix') 'force push'
    Test-Case refuse @('git', 'push', 'origin', 'gemini/8-fix:main') 'refspec to main'
    Test-Case refuse @('git', 'config', 'user.name', 'x') 'git config'
    Test-Case refuse @('git', '-c', 'core.pager=sh', 'log') 'global -c'
    Test-Case refuse @('git', 'log', '--output', 'x.txt') 'write a file'
    Test-Case refuse @('git', 'diff', '--ext-diff') 'external diff'
    Test-Case refuse @('python', 'x.py') 'not git or gh'
    Test-Case allow  @('gh', 'issue', 'view', '8', '--comments') 'issue view'
    Test-Case allow  @('gh', 'issue', 'edit', '8', '--add-label', 'soru') 'soru label'
    Test-Case refuse @('gh', 'issue', 'edit', '8', '--add-label', 'lider-onayi') 'other label'
    Test-Case refuse @('gh', 'issue', 'edit', '8', '--add-assignee', 'x') 'assignee'
    Test-Case refuse @('gh', 'pr', 'merge', '18') 'merge'
    Test-Case refuse @('gh', 'secret', 'list') 'secrets'
    Test-Case refuse @('gh', 'auth', 'token') 'auth'
    Test-Case allow  @('gh', 'pr', 'create', '--draft', '--title', 'x', '--body-file', 'b.md') 'pr create'
    Test-Case allow  @('gh', 'pr', 'create', '--title', 'see https://create.roblox.com/docs', '--body-file', 'b.md') 'text containing a URL is fine'

    # ---------------- gh: only this repository ----------------
    Test-Case allow  @('gh', 'pr', 'list', '-R', 'Kosmint/drone-catchers') '-R ours'
    Test-Case allow  @('gh', 'pr', 'list', '--repo', 'kosmint/DRONE-catchers') '--repo ours, any case'
    Test-Case allow  @('gh', 'pr', 'list', '--repo=Kosmint/drone-catchers') '--repo= ours'
    Test-Case refuse @('gh', 'pr', 'list', '-R', 'evil/repo') '-R other'
    Test-Case refuse @('gh', 'pr', 'list', '-Revil/repo') '-R attached other'
    Test-Case refuse @('gh', 'pr', 'list', '-R=evil/repo') '-R= other'
    Test-Case refuse @('gh', 'issue', 'list', '--repo', 'evil/repo') '--repo other'
    Test-Case refuse @('gh', 'issue', 'list', '--repo=evil/repo') '--repo= other'
    Test-Case refuse @('gh', 'pr', 'list', '-R') '-R without value'
    Test-Case refuse @('gh', 'pr', 'view', 'https://github.com/evil/repo/pull/1') 'URL of another repo'
    Test-Case allow  @('gh', 'pr', 'view', 'https://github.com/Kosmint/drone-catchers/pull/18') 'URL of ours'
    Test-Case refuse @('gh', 'repo', 'view', 'evil/repo') 'repo view other'
    Test-Case allow  @('gh', 'repo', 'view', 'Kosmint/drone-catchers') 'repo view ours'

    # ---------------- gh api: GET, ours only ----------------
    Test-Case allow  @('gh', 'api', 'repos/Kosmint/drone-catchers/pulls/18/comments') 'api ours'
    Test-Case allow  @('gh', 'api', '/repos/Kosmint/drone-catchers/issues/8', '--jq', '.title') 'api ours with jq'
    Test-Case allow  @('gh', 'api', 'repos/kosmint/drone-catchers/git/matching-refs/heads/gemini/8-', '--paginate') 'api ours paginate'
    Test-Case refuse @('gh', 'api', 'repos/{owner}/{repo}/pulls/18/comments') 'placeholder path'
    Test-Case refuse @('gh', 'api', 'user') 'api user'
    Test-Case refuse @('gh', 'api', 'repos/evil/repo/contents/x') 'api other repo'
    Test-Case refuse @('gh', 'api', 'repos/Kosmint/drone-catchers/../../user') 'path traversal'
    Test-Case refuse @('gh', 'api', 'repos/Kosmint/drone-catchers%2f..%2fx') 'encoded traversal'
    Test-Case refuse @('gh', 'api', 'repos/Kosmint/drone-catchers-evil/issues') 'prefix trick'
    Test-Case refuse @('gh', 'api', '-X', 'DELETE', 'repos/Kosmint/drone-catchers/issues/8') 'method'
    Test-Case refuse @('gh', 'api', '--method=PATCH', 'repos/Kosmint/drone-catchers/issues/8') 'method='
    Test-Case refuse @('gh', 'api', 'repos/Kosmint/drone-catchers/issues/8/comments', '-f', 'body=x') 'body field'
    Test-Case refuse @('gh', 'api', '-H', 'X-HTTP-Method-Override: DELETE', 'repos/Kosmint/drone-catchers/issues/8') 'header'
    Test-Case refuse @('gh', 'api', 'graphql', '-f', 'query=x') 'graphql'
    Test-Case refuse @('gh', 'api', 'repos/Kosmint/drone-catchers/issues', 'repos/evil/x') 'two endpoints'

    # ---------------- gh: refused commands ----------------
    Test-Case refuse @('gh', 'pr', 'review', '18', '--approve') 'pr review approve'
    Test-Case refuse @('gh', 'pr', 'review', '18', '--comment', '-b', 'x') 'pr review comment'
    Test-Case refuse @('gh', 'release', 'list') 'release'
    Test-Case refuse @('gh', 'run', 'list') 'run'
    Test-Case refuse @('gh', 'cache', 'list') 'cache'
    Test-Case refuse @('gh', 'gist', 'create', 'x.txt') 'gist'
    Test-Case refuse @('gh', 'issue', 'delete', '8') 'issue delete'
    Test-Case refuse @('gh', 'issue', 'transfer', '8', 'evil/repo') 'issue transfer'
    Test-Case refuse @('gh', 'issue', 'lock', '8') 'issue lock'
    Test-Case refuse @('gh', 'label', 'create', 'x') 'label'

    # ---------------- git: subcommand allow-list ----------------
    foreach ($s in @('fetch', 'pull', 'checkout', 'switch', 'branch', 'log', 'diff', 'show', 'rev-parse', 'restore', 'rm', 'mv', 'merge', 'ls-files')) {
        Test-Case allow @('git', $s) "git $s is allowed"
    }
    Test-Case allow  @('git', 'rebase', '--continue') 'rebase --continue'
    Test-Case allow  @('git', 'rebase', '--abort') 'rebase --abort'
    Test-Case refuse @('git', 'rebase', 'main') 'rebase onto'
    Test-Case refuse @('git', 'rebase', '-i', 'HEAD~2') 'interactive rebase'
    foreach ($s in @('stash', 'reset', 'remote', 'ls-remote', 'cat-file', 'grep', 'blame', 'describe', 'merge-base', 'submodule', 'clone', 'tag', 'worktree', 'gc', 'filter-branch', 'archive', 'bundle', 'daemon', 'instaweb', 'difftool', 'mergetool', 'send-email', 'credential', 'st', 'co', 'lol')) {
        Test-Case refuse @('git', $s) "git $s (not on the list, or an alias)"
    }
    Test-Case refuse @('git', 'STATUS') 'case trick (git is case-sensitive; STATUS would be an alias)'
    Test-Case allow  @('git', 'fetch', 'origin') 'fetch origin'
    Test-Case allow  @('git', 'pull', 'origin', 'gemini/8-fix') 'pull origin branch'
    Test-Case refuse @('git', 'fetch', 'https://evil.example/repo.git') 'fetch URL'
    Test-Case refuse @('git', 'pull', 'ext::sh -c evil') 'ext transport'
    Test-Case refuse @('git', 'fetch', 'origin', '+refs/heads/*:refs/heads/*') 'refspec writing local refs'
    Test-Case refuse @('git', 'fetch', '--recurse-submodules') 'submodules'
    Test-Case refuse @('git', 'merge', '-s', 'evil', 'x') 'merge strategy'
    Test-Case refuse @('git', 'merge', '--strategy=evil', 'x') 'merge strategy ='
    Test-Case refuse @('git', 'commit', '-S', '-m', 'x') 'signing'

    # ---------------- .git/config and hooks ----------------
    $bad = @(
        @("`n[alias]`n`tst = !sh -c evil`n", 'shell alias'),
        @("`n[core]`n`tfsmonitor = evil.exe`n", 'core.fsmonitor'),
        @("`n[core]`n`thooksPath = evilhooks`n", 'core.hooksPath'),
        @("`n[core]`n`tsshCommand = evil`n", 'core.sshCommand'),
        @("`n[core]`n`tpager = evil`n", 'core.pager'),
        @("`n[core]`n`teditor = evil`n", 'core.editor'),
        @("`n[CORE]`n`tEditor = evil`n", 'upper-case section and key'),
        @("`n[core] editor = evil`n", 'setting on the header line'),
        @("`n[diff]`n`texternal = evil`n", 'diff.external'),
        @("`n[filter `"lfs`"]`n`tclean = evil`n", 'filter.*'),
        @("`n[include]`n`tpath = ../evil.cfg`n", 'include'),
        @("`n[includeIf `"gitdir:/`"]`n`tpath = ../evil.cfg`n", 'includeIf'),
        @("`n[url `"https://evil/`"]`n`tinsteadOf = https://github.com/`n", 'url insteadOf'),
        @("`n[credential]`n`thelper = !evil`n", 'credential helper'),
        @("`n[remote `"evil`"]`n`turl = https://evil/x.git`n", 'another remote'),
        @("`n[remote `"Origin`"]`n`turl = https://evil/x.git`n", 'case trick on remote name'),
        @("`n[commit]`n`tgpgSign = true`n", 'commit.gpgsign'),
        @("`n[merge `"evil`"]`n`tdriver = evil %A`n", 'merge driver')
    )
    foreach ($pair in $bad) {
        Set-Config $pair[0]
        Test-Case refuse @('git', 'status') (".git/config: " + $pair[1])
    }
    # origin pointing elsewhere
    [System.IO.File]::WriteAllText((Join-Path $Clone '.git\config'), ($CleanConfig -replace 'Kosmint/drone-catchers', 'evil/repo'), $Utf8)
    Test-Case refuse @('git', 'status') 'origin url changed'
    # harmless settings stay allowed
    Set-Config "`n[alias]`n`tst = status`n[branch `"gemini/8-fix`"]`n`tremote = origin`n`tmerge = refs/heads/gemini/8-fix`n[user]`n`tname = x`n"
    Test-Case allow  @('git', 'status') 'plain alias, branch tracking and user settings are fine'
    Set-Config ''
    Test-Case allow  @('git', 'status') 'clean config again'
    # gh is not blocked by git config (it doesn't read it)
    Set-Config "`n[core]`n`teditor = evil`n"
    Test-Case allow  @('gh', 'issue', 'view', '8') 'gh ignores .git/config'
    Set-Config ''

    $hook = Join-Path $Clone '.git\hooks\pre-commit'
    [System.IO.File]::WriteAllText($hook, "#!/bin/sh`necho evil`n", $Utf8)
    Test-Case refuse @('git', 'commit', '-m', 'x') 'active hook file'
    Remove-Item -LiteralPath $hook
    [System.IO.File]::WriteAllText((Join-Path $Clone '.git\hooks\pre-commit.sample'), "#!/bin/sh`n", $Utf8)
    Test-Case allow  @('git', 'commit', '-m', 'x') '.sample hooks are fine'
} finally {
    Remove-Item Env:AGY_GATE_DRYRUN -ErrorAction SilentlyContinue
    Pop-Location
    Remove-Item -LiteralPath $Clone -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("agy-git.ps1: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
exit $script:Failed

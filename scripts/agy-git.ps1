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

  - gh works only on Kosmint/drone-catchers (-R/--repo, URLs); gh api is GET-only and only on
    repos/Kosmint/drone-catchers/... paths.
  - gh pr review / merge, release, run, cache, gist, secret, auth, workflow, label, and issue
    delete/transfer/lock are refused.
  - git: a fixed list of subcommands (aliases are never run). The clone is refused when .git/config
    holds settings that can run programs or redirect git, or .git/hooks holds a non-.sample file.

  gemini-helper.ps1 copies this file outside the clone before every run, so the agent cannot edit it.
  git runs with hooks, fsmonitor, pager and editor switched off.

  Tests: scripts/tests/Test-AgyGate.ps1 (sets AGY_GATE_DRYRUN=1: check only, print ALLOWED, run nothing).
#>
$ErrorActionPreference = 'Continue'
$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8
$Here = (Get-Location).Path
$CmdFile = Join-Path $Here '.agy-cmd.txt'
$RepoSlug = 'kosmint/drone-catchers'   # the only repository gh may touch (compared lower-case)

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
function Get-Positionals([string[]]$ArgList, [string[]]$ValueFlags) {
    # Arguments that are not options (and not the value of an option that takes one).
    $out = @()
    $skip = $false
    foreach ($a in $ArgList) {
        if ($skip) { $skip = $false; continue }
        if ($a -eq '--') { continue }
        if ($a.StartsWith('-')) {
            if (($ValueFlags -contains $a.ToLowerInvariant()) -and -not $a.Contains('=')) { $skip = $true }
            continue
        }
        $out += $a
    }
    return , $out
}

# Never allowed with either tool: options that run programs, open editors/browsers or write files.
if (Test-Match '^--(exec|exec-path|upload-pack|receive-pack|config-env|config|output|ext-diff|textconv|editor|web|git-dir|work-tree|hostname|recurse-submodules|strategy|gpg-sign|header)$') { Stop-Gate 'that option is not allowed.' }
if (Test-Match '^-(c|e|w|o)$') { Stop-Gate 'that option is not allowed.' }
if ($sub.StartsWith('-')) { Stop-Gate 'put the subcommand first; global options are not allowed.' }

$runArgs = $cmdArgs
$gitPrefix = @()

# ---------------------------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------------------------
function Test-OriginUrl([string]$Url) {
    $u = $Url.Trim().Trim('"').ToLowerInvariant()
    return ($u -match '^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)kosmint/drone-catchers(\.git)?/?$')
}

function Get-ConfigProblem([string]$Path) {
    # Returns a description of the first dangerous setting in a git config file, or $null.
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $section = ''      # e.g. core, alias, remote
    $subsection = ''   # e.g. origin  (from [remote "origin"])
    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[\s*([A-Za-z0-9.-]+)(\s+"([^"]*)")?\s*\]') {
            $after = $line.Substring($Matches[0].Length).Trim()
            # git also reads "[core] editor = x" on one line: refuse anything after the header.
            if ($after -and -not ($after.StartsWith('#') -or $after.StartsWith(';'))) { return "a setting on the section header line ($line)" }
            $name = $Matches[1].ToLowerInvariant()
            $subsection = ''
            if ($Matches[3]) { $subsection = $Matches[3] }
            if ($name.Contains('.')) {   # old style [branch.main]
                $dot = $name.IndexOf('.')
                $subsection = $name.Substring($dot + 1); $name = $name.Substring(0, $dot)
            }
            $section = $name
            if (@('include', 'includeif', 'filter', 'credential', 'url', 'gpg', 'pager', 'http', 'protocol', 'uploadpack', 'receive', 'sequence', 'submodule', 'trailer', 'difftool', 'mergetool') -contains $section) {
                return "[$section] section"
            }
            if (($section -eq 'diff' -or $section -eq 'merge') -and $subsection) { return "[$section `"$subsection`"] driver" }
            if ($section -eq 'remote' -and $subsection -cne 'origin') { return "[remote `"$subsection`"] (only origin is allowed)" }
            continue
        }
        if ($line.StartsWith('[')) { return "unreadable section header ($line)" }
        $key = $line; $value = ''
        $eqPos = $line.IndexOf('=')
        if ($eqPos -ge 0) { $key = $line.Substring(0, $eqPos).Trim(); $value = $line.Substring($eqPos + 1).Trim() }
        $key = $key.ToLowerInvariant()
        $v = $value.Trim('"').Trim()
        if ($section -eq 'alias' -and $v.StartsWith('!')) { return "alias.$key runs a shell command" }
        if ($section -eq 'core' -and @('fsmonitor', 'hookspath', 'sshcommand', 'pager', 'editor', 'askpass', 'gitproxy', 'worktree') -contains $key) { return "core.$key" }
        if ($section -eq 'diff' -and @('external', 'tool', 'guitool') -contains $key) { return "diff.$key" }
        if ($section -eq 'merge' -and @('tool', 'guitool') -contains $key) { return "merge.$key" }
        if ($section -eq 'remote') {
            if (@('url', 'pushurl') -contains $key) {
                if (-not (Test-OriginUrl $v)) { return "remote.origin.$key is not github.com/Kosmint/drone-catchers" }
            } elseif (@('uploadpack', 'receivepack', 'proxy', 'vcs', 'mirror') -contains $key) { return "remote.origin.$key" }
        }
        if ($section -eq 'extensions' -and $key -eq 'worktreeconfig') { return 'extensions.worktreeConfig' }
        if (($section -eq 'commit' -or $section -eq 'tag') -and $key -eq 'gpgsign') { return "$section.gpgsign" }
    }
    return $null
}

if ($tool -eq 'git') {
    $okGit = @('status', 'add', 'commit', 'push', 'fetch', 'pull', 'checkout', 'switch', 'branch', 'log', 'diff', 'show', 'rev-parse', 'restore', 'rm', 'mv', 'merge', 'rebase', 'ls-files')
    # Only exact built-in names, case-sensitive: git commands are case-sensitive, so "STATUS" would
    # not be the built-in status but an alias lookup. An alias is never run.
    if ($okGit -cnotcontains $cmdArgs[0]) { Stop-Gate ('git ' + $cmdArgs[0] + ' is not allowed.') }
    if ($sub -eq 'rebase' -and -not ($rest.Count -eq 1 -and ($rest[0] -eq '--continue' -or $rest[0] -eq '--abort'))) { Stop-Gate 'only git rebase --continue and git rebase --abort are allowed.' }
    # -s on merge/pull = merge strategy (runs git-merge-<name>); -S = GPG signing (runs a program).
    if ($sub -eq 'merge' -or $sub -eq 'pull') {
        foreach ($a in $cmdArgs) { if ($a -cmatch '^-(s|S)') { Stop-Gate 'merge strategies and signing are not allowed.' } }
    }
    if ($sub -eq 'commit') {
        foreach ($a in $cmdArgs) { if ($a -cmatch '^-S') { Stop-Gate 'signing is not allowed.' } }
    }
    if ($sub -eq 'fetch' -or $sub -eq 'pull') {
        # Only from origin: no URLs, paths or other remotes, no refspecs that write local refs.
        $pos = Get-Positionals @($cmdArgs | Select-Object -Skip 1) @('--depth', '--deepen', '--shallow-since', '--shallow-exclude', '-j', '--jobs')
        if ($pos.Count -ge 1 -and $pos[0] -cne 'origin') { Stop-Gate 'fetch/pull only from origin.' }
        foreach ($p in @($pos | Select-Object -Skip 1)) {
            if ($p -cnotmatch '^[A-Za-z0-9._/-]+$') { Stop-Gate 'fetch/pull: only plain branch names after origin.' }
        }
    }
    if ($sub -eq 'push') {
        # Only: git push [-u|--set-upstream] origin <gemini|claude>/<branch>   (explicit branch, never main).
        $r = @($cmdArgs | Select-Object -Skip 1)
        if ($r.Count -ge 1 -and ($r[0] -ceq '-u' -or $r[0] -ceq '--set-upstream')) { $r = @($r | Select-Object -Skip 1) }
        if ($r.Count -ne 2 -or $r[0] -cne 'origin') { Stop-Gate 'allowed push form: git push [-u] origin <gemini|claude>/<branch>' }
        if ($r[1] -cnotmatch '^(gemini|claude)/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$') { Stop-Gate 'push only branches named gemini/... or claude/..., one explicit branch.' }
    }
    if ($sub -eq 'branch' -and (Test-Match '^--(set-upstream-to|unset-upstream|edit-description)')) { Stop-Gate 'that git branch option is not allowed.' }

    # Refuse a clone whose config can run programs or redirect git (the agent can edit .git/ with its file tools).
    foreach ($cfgName in @('config', 'config.worktree')) {
        $problem = Get-ConfigProblem (Join-Path $Here ".git\$cfgName")
        if ($problem) { Stop-Gate (".git/$cfgName contains a setting that can run programs or redirect git ($problem). Ask a human to clean it.") }
    }
    $hooksDir = Join-Path $Here '.git\hooks'
    if (Test-Path -LiteralPath $hooksDir) {
        $hook = Get-ChildItem -LiteralPath $hooksDir -Force -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.sample' } | Select-Object -First 1
        if ($hook) { Stop-Gate (".git/hooks contains '" + $hook.Name + "'. Ask a human to remove it.") }
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

# ---------------------------------------------------------------------------------------------
# gh
# ---------------------------------------------------------------------------------------------
if ($tool -eq 'gh') {
    # Never: these whole command groups, and these single commands.
    $deniedGroups = @('release', 'run', 'cache', 'gist', 'secret', 'variable', 'auth', 'workflow', 'label', 'alias', 'extension', 'config', 'codespace', 'ssh-key', 'gpg-key', 'org', 'project', 'ruleset', 'attestation', 'browse')
    $deniedPairs = @('pr review', 'pr merge', 'pr close', 'pr reopen', 'issue delete', 'issue transfer', 'issue lock', 'issue unlock', 'issue close', 'issue reopen', 'issue pin', 'issue unpin', 'issue develop')
    if ($deniedGroups -contains $sub) { Stop-Gate "gh $sub is not allowed." }
    $pair = if ($low.Count -ge 2) { $low[0] + ' ' + $low[1] } else { $low[0] }
    if ($deniedPairs -contains $pair) { Stop-Gate "gh $pair is not allowed." }

    # Only this repository: -R/--repo, and any URL in the arguments.
    for ($i = 0; $i -lt $cmdArgs.Count; $i++) {
        $a = $cmdArgs[$i]
        $val = $null
        if ($a -ceq '-R' -or $a.ToLowerInvariant() -eq '--repo') {
            if ($i + 1 -ge $cmdArgs.Count) { Stop-Gate 'missing value for -R/--repo.' }
            $val = $cmdArgs[$i + 1]
        } elseif ($a -cmatch '^-R=?(.+)$') {
            $val = $Matches[1]
        } elseif ($a.ToLowerInvariant().StartsWith('--repo=')) {
            $val = $a.Substring(7)
        }
        if ($null -ne $val) {
            $v = $val.Trim().ToLowerInvariant() -replace '^(https?://)?github\.com/', ''
            if ($v.TrimEnd('/') -ne $RepoSlug) { Stop-Gate 'gh only works on Kosmint/drone-catchers.' }
        }
        # An argument that IS a URL (gh pr view <url>, gh issue comment <url> ...) must be ours.
        # (Text that merely contains a URL, like a --title, is fine.)
        $al = $a.Trim().ToLowerInvariant()
        if ($al -match '^([a-z][a-z0-9+.-]*://|github\.com/|www\.github\.com/)') {
            if ($al -notmatch '^(https?://)?(www\.)?github\.com/kosmint/drone-catchers(/|$|\?|#)') { Stop-Gate 'gh only works on Kosmint/drone-catchers (URL points elsewhere).' }
        }
    }
    Remove-Item Env:GH_REPO -ErrorAction SilentlyContinue
    Remove-Item Env:GH_HOST -ErrorAction SilentlyContinue

    if ($sub -eq 'api') {
        if ($rest.Count -lt 1) { Stop-Gate 'gh api needs an endpoint.' }
        # Read-only: no method flag, no body fields, no input file, no headers, no GraphQL.
        if (Test-Match '^(-x|--method|-f|--field|--raw-field|--input|-h|--header)$') { Stop-Gate 'gh api is read-only: method flags, body fields and headers are not allowed.' }
        if (Test-Match 'graphql') { Stop-Gate 'gh api graphql is not allowed.' }
        foreach ($a in $cmdArgs) { if ($a -cmatch '^-[A-Za-z]*[fFXxH]') { Stop-Gate 'gh api: short flags that set a method, body or header are not allowed.' } }
        $pos = Get-Positionals @($cmdArgs | Select-Object -Skip 1) @('-q', '--jq', '-t', '--template', '--cache', '-p', '--preview')
        if ($pos.Count -ne 1) { Stop-Gate 'gh api takes exactly one endpoint.' }
        $ep = $pos[0].ToLowerInvariant().TrimStart('/')
        if ($ep.Contains('..') -or $ep.Contains('%2e') -or $ep.Contains('%2f') -or $ep.Contains('\')) { Stop-Gate 'gh api: that endpoint is not allowed.' }
        if ($ep -notmatch '^repos/kosmint/drone-catchers(/|\?|$)') { Stop-Gate 'gh api only reads repos/Kosmint/drone-catchers/... (write the owner and repo out, no {owner}/{repo}).' }
    } else {
        # Allow-list of "<group> <verb>". Everything else is refused.
        $okGh = @('issue view', 'issue list', 'issue comment', 'issue edit', 'pr view', 'pr list', 'pr create', 'pr ready', 'pr comment', 'pr edit', 'pr diff', 'pr checks', 'pr status', 'repo view')
        if ($okGh -notcontains $pair) { Stop-Gate "gh $pair is not allowed." }
        if ($pair -eq 'repo view') {
            $pos = Get-Positionals @($cmdArgs | Select-Object -Skip 2) @('-b', '--branch', '-q', '--jq', '-t', '--template', '--json')
            foreach ($p in $pos) { if ($p.ToLowerInvariant().TrimEnd('/') -ne $RepoSlug) { Stop-Gate 'gh repo view only for Kosmint/drone-catchers.' } }
        }
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

if ($env:AGY_GATE_DRYRUN -eq '1') {
    # Test mode (scripts/tests/Test-AgyGate.ps1): the command passed every check; don't run it.
    Write-Output ('ALLOWED: ' + $tool + ' ' + ($cmdArgs -join ' '))
    exit 0
}

# Run directly, no shell. stdin is closed so nothing waits for input.
$null | & $tool @gitPrefix @runArgs 2>&1 | ForEach-Object { [string]$_ }
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }
Write-Output ('[exit {0}]' -f $code)
exit $code

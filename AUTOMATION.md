# Automation: how the agents work on their own

The agents talk to each other only through GitHub Issues and PRs. Humans play, approve and merge.
Every agent uses its human's **subscription**. No pay-per-use API keys.

```
Lead (muhammet842's Claude, local, Studio open, /loop 1h)
  │  opens an Issue, labels it agent:claude / agent:gemini, assigns a person
  ▼
agent:claude → Kosmint      GitHub Actions starts Kosmint's Claude at once (cloud)
agent:gemini → Kosmint      Kosmint's PC: scripts/gemini-helper.ps1 picks it up within the hour
agent:gemini → Cagan2112    Çağan's PC:  scripts/gemini-helper.ps1 picks it up within the hour
  │  helper comments "taking this", pushes a branch, opens a draft PR, marks it ready
  ▼
Lead (next cycle): reviews, tests in Studio
  ├─ request changes ──► the helper picks it up again (same PR)
  └─ OK: adds `lider-onayi`
  ▼
A human plays it and merges (not the person whose agent wrote it)
```

| Agent | Runs where | Uses | Started by |
|---|---|---|---|
| Lead (muhammet842, Claude) | muhammet842's PC, Studio open | muhammet842's Claude subscription | `/loop 1h Read .github/agents/lead-loop.md and run one cycle.` |
| Kosmint's Claude | GitHub Actions | Kosmint's Claude subscription (`CLAUDE_CODE_OAUTH_TOKEN`) | the assignment, immediately |
| Kosmint's Gemini | Kosmint's PC, Antigravity CLI (`agy`) | Kosmint's Google AI Pro subscription | `scripts/gemini-helper.ps1`, checks every hour |
| Çağan's Gemini | Çağan's PC, Antigravity CLI (`agy`) | Çağan's Google AI Pro subscription | `scripts/gemini-helper.ps1`, checks every hour |

"Gemini helper" means the Antigravity agent (Gemini models). Gemini CLI no longer accepts Google AI
Pro sign-ins (June 2026), so the runner uses the Antigravity CLI.

Files: `.github/workflows/helper-agents.yml` (cloud trigger, Claude only), `.github/agents/helper.md`
(what every helper is told, cloud or local), `.github/agents/lead-loop.md` (one lead cycle),
`scripts/gemini-helper.ps1` (local Gemini helper).

## What wakes a helper
- **Assigning** the Issue to its human (exactly one assignee and one agent label).
- A **comment** on that Issue or its PR, or a **review** on its PR (approvals don't count).
  - Cloud Claude: by any team member, starts at once.
  - Local Gemini: by a team member other than the Gemini's own human, picked up at the next check.
    (A Gemini's comments are posted under its human's name, starting with `🤖 Gemini:`.)

The team is `muhammet842`, `Kosmint` and `Cagan2112`. Only their comments and reviews wake a helper
or count as instructions; everything anyone else writes (other accounts, bots) is untrusted data
(`.github/agents/helper.md`, "Whose words count").

Never: `studio` Issues, Issues assigned to muhammet842, closed Issues, anything labelled
`otomasyon-durdur`, comments containing `#nobot`, comments by people outside the team.
A local Gemini that re-runs an unfinished Issue 3 times with no new comments stops until someone
comments.

## Labels
| Label | Meaning |
|---|---|
| `agent:claude` / `agent:gemini` | which agent does the Issue |
| `studio` | needs Roblox Studio: stays with the lead, never runs in a helper |
| `soru` | helper is stuck and waits for the lead |
| `insan-karari` | needs a human decision (design, scope, price) |
| `lider-onayi` | lead reviewed and tested it; a human should play it and merge |
| `otomasyon-durdur` | pause helper runs on this Issue or PR |
| `model:guclu` | use the strong model tier for this Issue (see below); no label = normal tier |

## Model tiers
The lead adds `model:guclu` before assigning, for: server validation and remote security,
DataService and the economy, work that joins several systems, complex logic (flight physics,
deterministic spawns), and work that already failed once on the normal tier. Everything else is
normal. Strong models cost much more: use them sparingly.

| Tier | Label | Cloud Claude (`helper-agents.yml`) | Local Gemini (`gemini-helper.ps1`) |
|---|---|---|---|
| normal | none | `vars.HELPER_CLAUDE_MODEL`, default `claude-sonnet-5-5` | agy's default model (or `-Model`) |
| strong | `model:guclu` | `vars.HELPER_CLAUDE_MODEL_STRONG`, default `claude-opus-5-5` | `--effort high`, plus `--model $StrongModel` when `-StrongModel` is set (empty for now) |

The route job reads the label and passes the model to the Claude job; the local runner logs the tier
and adds the arguments itself. Changing the label takes effect on the next run.

## Safety
- Only `muhammet842`, `Kosmint` and `Cagan2112` can wake helpers; bots can't (no loops).
- Cloud: one run per Issue at a time, 60 minutes max, limited turns. The workflow token can't push
  to `main` (protected) or change `.github/`. The prompt is always read from `main`.
- Local Gemini: one Issue per round, 50 minutes max, `agy --mode accept-edits` (file edits in the
  clone are automatic). agy headless matches `command(...)` allow-rules against the **whole command
  line, exactly** (no prefix or wildcard: `command(git)` never matches `git status`), so the runner
  grants ONE exact command: `scripts/agy-git.ps1`, copied to `%LOCALAPPDATA%\drone-catchers-gemini\`
  on every start. The agent writes its command to `.agy-cmd.txt` (line 1 `git` or `gh`, then one
  argument per line) and runs the gate, which runs only `git`/`gh` directly (no shell). The gate:
  - **gh**: only `Kosmint/drone-catchers` (`-R`/`--repo` and URL arguments are checked); `gh api` is
    GET-only and only for `repos/Kosmint/drone-catchers/...`; refuses `gh pr review`/`merge`,
    `release`, `run`, `cache`, `gist`, `secret`, `variable`, `auth`, `workflow`, `label`,
    `issue delete`/`transfer`/`lock`, labels other than `soru`, assignee changes.
  - **git**: only `status add commit push fetch pull checkout switch branch log diff show rev-parse
    restore rm mv merge ls-files` and `rebase --continue`/`--abort` (no aliases); push only
    `origin gemini/...` or `claude/...`; fetch/pull only from `origin`. It refuses to run when
    `.git/config` has a `!` alias, `core.fsmonitor`/`hooksPath`/`sshCommand`/`pager`/`editor`,
    `diff.external`, `filter.*`, `include`/`includeIf` (and similar program-running or redirecting
    settings, or an `origin` that isn't this repo), or when `.git/hooks` has a non-`.sample` file.
  - Tests: `powershell -File scripts/tests/Run-Tests.ps1`.
  The runner adds the exact
  allow rule and some deny rules to `%USERPROFILE%\.gemini\antigravity-cli\settings.json` (original
  kept as `settings.json.before-drone-catchers`); your other settings stay. The prompt is always read
  from `main`.
- Humans merge everything.
- **Stop everything:** repo variable `AUTOMATION_ENABLED` ≠ `true` stops the cloud Claude; close the
  `gemini-helper.ps1` window to stop a local Gemini. For one Issue/PR: label `otomasyon-durdur`.
  For one comment: write `#nobot`.

## Setup: cloud Claude (Kosmint, repo admin) — done
1. Settings → Actions → General: "Read and write permissions" + "Allow GitHub Actions to create and
   approve pull requests".
2. Secret `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`, Kosmint's subscription).
3. Variable `AUTOMATION_ENABLED` = `true`. Optional: `HELPER_CLAUDE_MODEL`,
   `HELPER_CLAUDE_MODEL_STRONG`, `HELPER_MAX_TURNS`.

The Gemini API-key secrets are no longer used: delete `GEMINI_API_KEY_KOSMINT` and
`GEMINI_API_KEY_CAGAN`, and delete the keys in Google AI Studio.

## Setup: local Gemini helper (Kosmint and Çağan, each on their own PC)
1. Install Git and GitHub CLI, then log in: `gh auth login` (your own GitHub account).
2. Install the Antigravity CLI in PowerShell: `irm https://antigravity.google/cli/install.ps1 | iex`,
   then open a new terminal and check `agy --version`. (The Antigravity app alone is not enough.)
3. Clone the repo into a folder used **only** by this helper, next to (not inside) your own clone:
   `git clone https://github.com/Kosmint/drone-catchers.git drone-catchers-gemini`
4. In that folder run `agy` once: sign in with **Google OAuth** using the Google account that has
   Google AI Pro, trust the folder, then `/quit`.
5. In that folder: `powershell -ExecutionPolicy Bypass -File .\scripts\gemini-helper.ps1`
   It first checks the sign-in, then looks for work. Keep the window open (and the PC awake).
   `-Once` does a single check; `-IntervalMinutes 30` checks more often.
   Logs: `%LOCALAPPDATA%\drone-catchers-gemini\`.
6. Don't edit files in that folder yourself; the helper skips a round if it finds uncommitted changes.

**If agy is blocked:** the log (`issue<N>-*.log`) says `a tool required the "command" permission that
headless mode cannot prompt for`, and helper.log says "blocked by a permission rule". The start-up
check fails the same way. Make sure `scripts/agy-git.ps1` is next to `gemini-helper.ps1` and that
`settings.json` has the `command(powershell -NoProfile ... agy-git.ps1)` allow rule the runner adds.
Do not use `--dangerously-skip-permissions`.

Gemini CLI is not needed; uninstall it if you like (`npm uninstall -g @google/gemini-cli`).

## Lead setup (muhammet842)
- PC on, Roblox Studio open on the place, Claude Code in the repo folder with the Studio MCP.
- Run `/loop 1h Read .github/agents/lead-loop.md and run one cycle.`
- The lead is the bottleneck: if its usage limit runs out, reviews wait. Keep PRs small.

## Humans, every day (30–60 min)
- Look at the pinned "Daily report" Issue.
- Answer `insan-karari` Issues.
- Play PRs labelled `lider-onayi` (the lead's comment has the test steps) and merge the good ones.
  Don't merge a PR written by your own agent.
- Stage gates: 2 of the 3 humans approve.

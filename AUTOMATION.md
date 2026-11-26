# Automation: how the agents work on their own

The agents talk to each other only through GitHub Issues and PRs. Humans play, approve and merge.

```
Lead (muhammet842's Claude, local, Studio open, /loop 1h)
  │  opens an Issue, labels it agent:claude / agent:gemini, assigns a person
  ▼
GitHub Actions "Helper agents"  ──►  Kosmint's Claude  |  Kosmint's Gemini  |  Çağan's Gemini
  │  helper comments "taking this", pushes a branch, opens a draft PR, marks it ready
  ▼
Lead (next cycle): reviews, tests in Studio
  ├─ request changes ──► wakes the helper again (same PR)
  └─ OK: adds `lider-onayi`
  ▼
A human plays it and merges (not the person whose agent wrote it)
```

| Agent | Runs where | Started by |
|---|---|---|
| Lead (muhammet842, Claude) | muhammet842's PC, Studio open | `/loop 1h Read .github/agents/lead-loop.md and run one cycle.` |
| Kosmint's Claude | GitHub Actions | Issue with `agent:claude` assigned to Kosmint |
| Kosmint's Gemini | GitHub Actions | Issue with `agent:gemini` assigned to Kosmint |
| Çağan's Gemini | GitHub Actions | Issue with `agent:gemini` assigned to Cagan2112 |

Files: `.github/workflows/helper-agents.yml` (the trigger), `.github/agents/helper.md` (what every
cloud helper is told), `.github/agents/lead-loop.md` (one lead cycle).

## What wakes a helper
- **Assigning** the Issue to its human (the Issue needs exactly one assignee and one agent label).
- A **comment** by a team member on that Issue or on its PR.
- A **review** (changes requested or comment) on its PR. Approvals don't wake it.

Never: `studio` Issues, Issues assigned to muhammet842, closed Issues, anything labelled
`otomasyon-durdur`, comments containing `#nobot`, comments by anyone outside the team.

## Labels
| Label | Meaning |
|---|---|
| `agent:claude` / `agent:gemini` | which agent does the Issue |
| `studio` | needs Roblox Studio: stays with the lead, never runs in the cloud |
| `soru` | helper is stuck and waits for the lead |
| `insan-karari` | needs a human decision (design, scope, price) |
| `lider-onayi` | lead reviewed and tested it; a human should play it and merge |
| `otomasyon-durdur` | pause cloud runs on this Issue or PR |

## Safety
- Only `muhammet842`, `Kosmint` and `Cagan2112` can wake helpers. Bots can't (so helpers can't wake
  themselves or each other).
- One run per Issue at a time, 60 minutes max, limited turns.
- Helpers can't push to `main` (protected) and can't change `.github/` (the workflow token has no
  `workflows` permission). Their prompt is always read from `main`.
- Humans merge everything.
- **Kill switch:** set the repo variable `AUTOMATION_ENABLED` to anything other than `true`.
  For one Issue/PR: label `otomasyon-durdur`. For one comment: write `#nobot`.

## One-time setup (Kosmint, as repo admin)
1. **Settings → Actions → General → Workflow permissions:** "Read and write permissions" and tick
   "Allow GitHub Actions to create and approve pull requests".
2. **Settings → Secrets and variables → Actions → Secrets:**
   - `CLAUDE_CODE_OAUTH_TOKEN`: Kosmint runs `claude setup-token` on his PC and pastes the token.
     Uses Kosmint's Claude subscription.
   - `GEMINI_API_KEY_KOSMINT`: Kosmint's key from Google AI Studio.
   - `GEMINI_API_KEY_CAGAN`: Çağan's key from Google AI Studio. Çağan sends it to Kosmint privately
     (never in an Issue, PR or chat log). An API key is billed separately from a Gemini subscription;
     check the free-tier limits.
3. **Settings → Secrets and variables → Actions → Variables:**
   - `AUTOMATION_ENABLED` = `true` (turns the automation on)
   - optional: `HELPER_CLAUDE_MODEL` (default `claude-sonnet-5-5`), `HELPER_GEMINI_MODEL`
     (default: Gemini CLI's default), `HELPER_MAX_TURNS` (default `80`)
4. Test: the lead opens a small Issue (for example a typo fix), labels it, assigns it to Kosmint and
   watches the **Actions** tab.

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

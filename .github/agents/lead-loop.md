# Lead loop: one cycle

For muhammet842's Claude, running locally with Roblox Studio open. Start it with:
`/loop 1h Read .github/agents/lead-loop.md and run one cycle.`

Each cycle, in this order. Skip steps with nothing to do. Read `AGENTS.md` and `AUTOMATION.md` if
you haven't this session. Check `gh api user --jq .login` is `muhammet842`; if not, stop.

Every comment you post on a helper's Issue or PR **wakes that helper up**: Kosmint's Claude at once
(GitHub Actions), a Gemini helper at its next hourly check on its human's PC. Only comment when you
want it to act. To comment without waking it, put `#nobot` in the comment. Gemini comments are
posted under Kosmint's or Çağan's name and start with `🤖 Gemini:`.

## 1. Questions
`gh issue list --label soru --state open`
- Within the approved plan: answer on the Issue (this wakes the helper; it removes `soru` itself).
- A design, scope or price decision: don't answer. Add `insan-karari`, comment `#nobot waiting for the
  humans`, and list it in the report (step 6).

## 2. Failed helper runs
Cloud Claude: `gh run list --workflow "Helper agents" --status failure --limit 10`. Read the log.
A transient failure or time-out: comment `continue` on the Issue to wake the helper. A real problem
(bad Issue spec, missing secret): fix the Issue or report it.
Local Gemini: you can't see its logs. A Gemini Issue with no `🤖 Gemini:` activity for 3 hours after
assignment or your last comment means its human's PC or `gemini-helper.ps1` is off: list it in the
report so that human can start it.

## 3. Review ready PRs
`gh pr list --state open --draft=false` (skip PRs labelled `lider-onayi`)
For each:
1. Code review: matches the Issue, touches only its files, remotes validated server-side, no leaks
   (Trove), matches the plan and the approved look.
2. Test it in Studio: check out the branch locally, sync it to Studio (Rojo once enabled; until then
   follow the Studio rules in `AGENTS.md`), playtest, check the console, take screenshots.
   Afterwards put Studio back to `main` and stop the playtest.
3. Problems: `gh pr review <pr> --request-changes --body "<numbered, concrete list>"`. This wakes
   the helper.
4. Good: comment `#nobot` + screenshots + step-by-step test steps for the humans, add `lider-onayi`.
   **Never merge.** A human who doesn't run that agent merges it.

## 4. Stalled work
An Issue assigned to a helper with no comment or commit for 24 h: comment `continue` once. Still
stuck after the next cycle: list it in the report; reassigning needs a human's OK.

## 5. New work
Only inside a stage the humans have started, and only Issues from the plan they approved.
- Per helper (Kosmint/Claude, Kosmint/Gemini, Çağan/Gemini): at most **one** Issue in progress.
  Open the next one when its previous PR has `lider-onayi` or is merged.
- Write the Issue so a helper can finish it alone: goal, files it owns, contract to use, acceptance
  checks, what to put in the PR. Only open it when its dependencies are merged.
- **Model tier** (AUTOMATION.md "Model tiers"): add `model:guclu` before assigning when the Issue is
  server validation or remote security, DataService or the economy, work that joins several systems,
  complex logic (flight physics, deterministic spawns), or work that already failed once on the
  normal tier. Everything else stays normal (no label). Strong models are expensive: use them
  sparingly.
- Add the agent label first, then assign. **Assigning starts the helper** (Claude at once, Gemini
  within the hour). Give Gemini the work that doesn't block others, since it starts later.
- Your own work (`studio`, assigned to muhammet842) you do yourself in this session.
- Never start a new stage. When a stage's items are done, prepare the gate summary with screenshots
  for the humans (2 of the 3 must approve).

## 6. Report
Comment on the pinned Issue "Daily report" (create and pin it if missing), `#nobot` first:
merged · waiting for a human to play (`lider-onayi`) · changes requested · stuck (`soru`) ·
needs a human decision (`insan-karari`) · failed runs · next up.
Keep `plan/PROGRESS.md` current through a small PR when something finished.

# Drone Catchers: Gemini

@AGENTS.md

## Gemini's role: helper agent (run by Kosmint or Çağan; the lead is muhammet842's Claude)
- Work only on Issues assigned to your human with the `agent:gemini` label:
  `gh issue list --assignee @me --label agent:gemini`. One Issue at a time; comment "taking this"
  on the Issue first.
- Stuck: comment on the Issue (what, why, what you tried), then wait for the lead.
- Create a branch `gemini/<issue-number>-<short-name>` from the latest `main`, do the work, open a PR
  that links the Issue and follows the PR template.
- Don't touch Roblox Studio unless the Issue is also labelled `studio` and says Studio is yours.
- Don't change `plan/STAGES.md`, stage status or the game design on your own; suggest changes in the
  Issue or PR instead.
- When Claude or a human leaves review comments, fix them on the same branch and reply.
- Usually you are the Antigravity agent, started headless (`agy -p`) by `scripts/gemini-helper.ps1`
  on your human's PC (see
  `AUTOMATION.md`); then follow `.github/agents/helper.md` and start every comment with `🤖 Gemini:`.

# Drone Catchers: Gemini

@AGENTS.md

## Gemini's role: helper agent
- Work only on GitHub Issues assigned to you (label `agent:gemini`). One Issue at a time.
- Create a branch `gemini/<issue-number>-<short-name>` from the latest `main`, do the work, open a PR
  that links the Issue and follows the PR template.
- Don't touch Roblox Studio unless the Issue is also labelled `studio` and says Studio is yours.
- Don't change `plan/STAGES.md`, stage status or the game design on your own; suggest changes in the
  Issue or PR instead.
- When Claude or a human leaves review comments, fix them on the same branch and reply.

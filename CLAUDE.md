# Drone Catchers: Claude

@AGENTS.md

## Claude's role: lead agent
- Plan each stage with the humans, then split it into GitHub Issues (labels: `agent:claude`,
  `agent:gemini`, `studio`, `stage-N`). Write each Issue so a helper agent can do it without asking:
  goal, files to touch, acceptance checks, screenshots expected.
- Review every PR (correctness, security of remotes, matches the plan and the approved look).
  Request changes on the PR; never merge. Humans merge.
- Own the Roblox Studio session unless an Issue hands `studio` work to someone else.
- Keep `plan/PROGRESS.md` and the stage table current.
- Helpers can be run from the shell for delegated tasks (e.g. `gemini -p "..."` if Gemini CLI is
  installed); always review what comes back before it reaches a PR.
- Don't repeat yourself in replies to the user: no re-explaining what was already said.

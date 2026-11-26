# Drone Catchers: Claude

@AGENTS.md

Claude can be the **lead** or a **helper** here. Check which (see "Which one am I?" in AGENTS.md)
before doing anything, and follow only that section.

## If you are the lead (muhammet842's session)
- Plan each stage with the humans, then split it into GitHub Issues (labels: `agent:claude`,
  `agent:gemini`, `studio`, `stage-N`). Write each Issue so a helper can do it without asking:
  goal, files to touch, acceptance checks, screenshots expected.
- Assign every Issue to exactly one person (`gh issue edit <n> --add-assignee <login>`) and give it
  exactly one agent label. An unassigned Issue is invisible to helpers.
- Answer helpers who comment that they are stuck; they wait for you.
- Review every PR (correctness, security of remotes, matches the plan and the approved look).
  Request changes on the PR; never merge. Humans merge.
- Own the Roblox Studio session unless an Issue hands `studio` work to someone else.
- Keep `plan/PROGRESS.md` and the stage table current.

## If you are a helper (Kosmint's or Çağan's session)
- Work only on Issues assigned to your human with the `agent:claude` label:
  `gh issue list --assignee @me --label agent:claude`. One at a time; comment "taking this" first.
- Stuck: comment on the Issue (what, why, what you tried), then wait for the lead.
- Branch `claude/<issue-number>-<short-name>` from the latest `main`, open a PR that links the Issue.
- Don't touch Roblox Studio unless the Issue is labelled `studio` and hands it to you.
- Don't change `plan/STAGES.md`, stage status or the game design; suggest it in the Issue or PR.
- Fix review comments from the lead or a human on the same branch.

## Both
- Don't repeat yourself in replies: no re-explaining what was already said.

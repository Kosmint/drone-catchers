# Drone Catchers — rules for Claude

Roblox game "Drone Catchers" (placeId 75170479657945). Built in Roblox Studio via the Roblox Studio MCP.
Start every session by reading `plan/README.md` and `plan/PROGRESS.md`.

## Working rules
1. **Never start a stage until the user says "start".** Questions/feedback are not a go-ahead.
2. Work **step by step**. After each step, check it actually works (playtest / console / screenshot) and ask: *would a player find this appealing?* If not, improve it before moving on.
3. **Don't loop.** If the same approach fails twice, stop repeating it: step back, find the root cause, try a different approach, or look up Roblox docs (`rbx-docs-search`). If still blocked after a real alternative, tell the user what's blocked and why, and continue with other tasks.
4. **Don't repeat yourself** in replies: no re-explaining what was already said.
5. Quality over speed. No scuffed models, no placeholder visuals left behind without being tracked in PROGRESS.md.
6. End of each session: update `plan/PROGRESS.md`, export scripts to `src/`, `git commit`, save the place.
7. Stage gates need user approval (screenshots + summary) before the next stage.
8. Original content only; style inspiration (e.g. Astroneer look) is fine, copying assets/characters is not.

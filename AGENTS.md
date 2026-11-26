# Drone Catchers: rules for every AI agent

Read this file first. It applies to all agents (Claude, Gemini, others) and to humans working with them.
`CLAUDE.md` and `GEMINI.md` only add each agent's role on top of these rules.

Roblox game **Drone Catchers** (placeId 75170479657945, universeId 10778873502). A kid-friendly
collection/farm game: a rocket carries a drone up through sky layers, the player catches creatures
with a beam, brings them home and earns from them.

Start every session by reading `plan/README.md` and `plan/PROGRESS.md`. The plan lives in `plan/`:
`00_GAME_DESIGN`, `01_ARCHITECTURE`, `02_CONTENT`, `03_ART_AND_AUDIO`, `STAGES`, `PROGRESS`.

## Team and roles
- **Humans (the owners):** approve stage gates and merge pull requests. Only humans merge.
- **Claude (lead agent):** plans stages, splits work into GitHub Issues, reviews every PR,
  keeps `plan/PROGRESS.md` current, owns the Roblox Studio session by default.
- **Helper agents (Gemini and others):** take one Issue at a time, work on their own branch,
  open a PR, and answer review comments. They do not change the plan or stage status on their own.

## Working rules
1. **Never start a stage until a human says "start".** Questions and feedback are not a go-ahead.
2. Work **step by step**. After each step, check it actually works (playtest / console / screenshot)
   and ask: *would a player find this appealing?* If not, improve it before moving on.
3. **Don't loop.** If the same approach fails twice, stop: find the root cause, try a different
   approach, or read the Roblox docs. If still blocked, say what is blocked and why in the Issue/PR.
4. Quality over speed. No scuffed models, no placeholder visuals left behind without being tracked
   in `plan/PROGRESS.md` ("Placeholders to replace").
5. Stage gates need human approval (screenshots + summary) before the next stage.
6. **Original content only.** Style inspiration is fine; copying assets, characters or a specific
   existing game is not.

## Git workflow (main is protected)
- Never push to `main`. One Issue = one branch = one PR.
- Branch names: `<agent>/<issue-number>-<short-name>`, e.g. `gemini/12-beam-vfx`, `claude/15-hud`.
- Small, focused PRs. Fill in the PR template, link the Issue (`Closes #12`), add screenshots for
  anything visual and say whether it was tested in Studio.
- Claude reviews, a human merges. Fix review comments on the same branch.
- Don't commit secrets, `.rbxl` place files or `.claude/settings.local.json`.
- Update `plan/PROGRESS.md` in the same PR when you finish a checklist item.

## Roblox Studio: one agent at a time
The live game is in Roblox Studio (Team Create). `src/` mirrors the scripts.
- **Only one agent drives the Studio MCP at a time.** Studio work (scenery, uploads, playtests)
  belongs to whoever holds an Issue labelled `studio`. Others edit files only.
- `default.project.json` maps `src/` for **Rojo** (when the team turns Rojo sync on, `src/` becomes
  the source of truth). Until then, whoever changes a script in Studio must export it to `src/` in
  the same PR, and byte-check Studio vs file.
- Code that only lives in Studio (not in `src/`): `ReplicatedStorage.Assets`, `ReplicatedStorage.Inputs`,
  remotes, Workspace scenery. Don't delete them.

## Project facts agents keep getting wrong
- Flight is 2.5D: the drone moves on an X/Y plane at `Balance.flight.origin` (20000, 100, 0), seen by a
  fixed side camera (FOV 35, 62 studs visible vertically). **0.1 studs = 1 demo unit.**
- Chapter 1 zones (200 studs each): **Low Sky** 0–200, **Sunset Heights** 200–400, **Edge of Space**
  400–600. There is no Storm Layer.
- Flight look = the approved browser demo: flat low-poly 2D sky and clouds (`SkyController`,
  art from `art/demo_sky.py`, asset ids in `Config/SkyArt`).
- Server is authoritative (ExpeditionService validates catches). Never trust the client; validate
  every remote argument (see `src/ReplicatedStorage/Shared/Net.luau`).
- Debug commands (Studio/owner only) via `ReplicatedStorage.Remotes.DebugCommand`:
  `engine <1-30>`, `drone "<stat> <lvl>"`, `cooldown`, `coins`, `reset`, `dump`.

## Studio MCP quirks
- The place has **no PlayerModule**: never `WaitForChild("PlayerModule")`.
- `execute_luau` runs in a separate VM: `require` gives fresh module copies, not the running game's
  state. Inspect instances instead. Studio's HttpService can't reach localhost.
- Launch a test flight by clicking `LocalPlayer.PlayerGui.HUD.Base.Launch` (gamepad keys don't fire
  Input Action bindings from the MCP).
- SurfaceGui art gets washed out by tone mapping; the zone presets add CC saturation/contrast for it.
- PowerShell 5.1 mangles UTF-8: use .NET `ReadAllText`/`WriteAllText` with UTF-8 (no BOM).

## End of a work session
Update `plan/PROGRESS.md`, make sure `src/` matches Studio, commit on your branch, open/update the PR,
and save the place if you changed Studio.

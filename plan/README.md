# Project Plan — Drone Catchers

This folder is Claude's build bible for the game. Read this file first at the start of every work session, then `PROGRESS.md`, then the current stage in `STAGES.md`.

## Files

| File | What it holds |
|---|---|
| `README.md` | This index + the working rules (non-negotiable). |
| `00_GAME_DESIGN.md` | The full game vision: core loop, flight, launch, base, creatures, boosts, evolution, progression, mood system. Everything the user and Claude agreed on. |
| `01_ARCHITECTURE.md` | Technical design: Studio hierarchy, modules, client/server split, remotes, data schema, flight-space coordinate system, anti-exploit. |
| `02_CONTENT.md` | Chapters, zones, creature roster, rarities, boosts, upgrade tables, economy numbers. |
| `03_ART_AND_AUDIO.md` | Visual direction per zone, lighting, VFX, UI style, music + intensity system, SFX list. |
| `STAGES.md` | The stage-by-stage build plan with tasks, acceptance criteria and quality gates. |
| `PROGRESS.md` | Live tracker: current stage, done/undone tasks, decisions log, known issues. |

## Working rules (from the user — follow exactly)

1. **This is a 1–2 week project, not a 1-day rush.** Quality over speed. Never compress stages to "finish faster".
2. **Stage by stage.** Finish a stage completely → test it in Studio (playtest, screenshots, console clean) → show the humans → only move on when **at least 2 of the 3 humans** (Kosmint, muhammet842, Çağan) approve (see `AGENTS.md`).
3. **No scuffed models, no boring gameplay.** Greybox (plain parts) is allowed *only* inside a stage as a temporary step to prove gameplay; it must be replaced by finished visuals before that stage's visual gate (or explicitly listed as "replaced in Stage X" in PROGRESS.md).
4. **It must actually be playable** — every stage ends with something the user can press Play on and enjoy.
5. **Solo game.** Multiplayer competitive mode is a *maybe-later* idea; keep code modular enough to add it, but don't build it.
6. **Original game.** Original names, creatures, art. No copying existing games' assets/characters.
7. Keep `PROGRESS.md` updated after every work session (what was done, what's next, problems).
8. Before writing Roblox code in an area, load the matching Roblox skill (`list_roblox_skills` / `get_roblox_skill`) and the matching `roblox-dev:*` skill (security, datastores, performance, ui, architecture, luau-strict-typing). Use Roblox docs (`rbx-docs-search`) instead of memory for any API Claude is unsure about.
9. Save the place (`save_place`) at the end of every session and copy a backup `.rbxl` into `backups/` at every stage gate (`backups/stageXX_<date>.rbxl`).
10. **Code backup every session:** export all scripts from Studio into `src/` (same hierarchy, `.luau`), then `git commit` with a short message of what changed. Never end a session with code only inside Studio.
11. **Never start a stage until the user says "start".**

## Agreed vision in one paragraph

A **2.5D** sky-and-space exploration collector. The player has a **3D base** with a big **rocket** carrying a **drone**. They launch (with a small skill-based **launch mini-game**), the camera swings to a **side view**, and they pilot the drone on an X/Y plane through **realistic skies and space**, using a **suction beam** to catch **creatures** (rarer ones resist and must be held in the beam). Batteries and cargo create risk; the **return trip** is a tense descent. Back home, creatures **earn money**, can be **evolved**, and give **boosts** when placed in **habitat slots**. The player upgrades **rocket** (how far) and **drone** (battery, speed, beam, range, cargo, scanner, armor) and expands the base with stations (workshop, hangar, habitat, evolution lab, observatory, collection book, research). Progression runs through **chapters**: Earth → Near Space → Solar System → Deep Space → Another Galaxy → Black Hole. Music is **calm and relaxing** normally and switches to **intense music + screen effects** when danger happens.

**Genre focus:** at heart it's a **collection/farm simulator** for a broad (kid-friendly) Roblox audience: launch → catch → bring home → creatures earn **online and offline**. Flight is the fun part, but the loop must stay simple and rewarding.

**RNG layer:** every launch has a tiny chance to open a **Rift** (9 tiers, 1 in 500 → 1 in 1,000,000,000), each tier with a bigger, more dramatic entrance (screen effects for common rifts, cinematics for the rarest), a "drone feed" 2.5D zone and exclusive creatures. **Everything is 2.5D, including rifts.** **Luck** raises the odds (free upgrades + creatures + paid gamepasses/potions).

**Art direction:** soft **stylized low-poly**, smooth gradients, warm pastel skies, chunky rounded shapes — *inspired by* the look of games like Astroneer (style inspiration only; all assets original). See `03_ART_AND_AUDIO.md`.

**Monetization:** gamepasses + developer products (luck, 2× coins, VIP, slots, potions, server luck). Odds always shown; free players always keep a real chance. See `00_GAME_DESIGN.md` §9–§11.

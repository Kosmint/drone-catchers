# PROGRESS

**Current stage:** Stage 0 — Foundations (built & tested; waiting on git install + user gate approval)
**Last session:** 2026-11-24 — Stage 0 built in Studio, all tests passed, scripts exported to `src/`, place saved (Roblox version 6).

## Stage 0 checklist
- [x] Hierarchy (Shared/Config, Shared/Util, Assets/*, Services, Controllers, Workspace Map/Plots/FlightSpace/RiftSpace)
- [x] Utils: Signal, Trove, Spring, StateMachine, WeightedRandom, NumberFormat, Guard (Cinematic timeline deferred to Stage 4 where it's first needed)
- [x] Net (single remote list, server-created, token-bucket rate limit + pcall per handler)
- [x] Config: Rarities (28), Modifiers (14), Chapters (Ch1+Ch2 zones), Creatures (12 Ch1), Upgrades, Balance
- [x] ServerMain / ClientMain two-phase bootstraps
- [x] DataService (UpdateAsync, retries, session lock, stale-lock recovery, autosave staggered, BindToClose, migrations + reconcile, kick on failed load; Studio uses separate store `PlayerData_v1_studio`)
- [x] DebugService (Studio/owner only): help, coins, reset, save, dump
- [x] DataController (client read-only copy + Changed signal)
- [x] Tests (via execute_luau): NumberFormat, WeightedRandom determinism + distribution, Signal/Trove, StateMachine, Spring, config cross-references, cost formula — ALL PASS
- [x] Playtests: data loads; NaN/inf/overspend/bad names rejected; rate limit (10 of 60 burst allowed); save → restart → coins persisted; fake foreign lock → save refused + player kicked + data untouched; join while locked → kicked; stale lock (>210s) → auto-recovered
- [x] StreamingEnabled = false (flight space is far from the character)
- [x] Scripts exported to `src/` (20 files, byte-size verified against Studio)
- [ ] git — **not installed on this PC**; user to install Git for Windows, then `git init` + first commit
- Note: Edit-mode DataStore WRITES are forbidden for the MCP tool (502 Access forbidden); reads work. Do data fixes from the Server datamodel during a playtest.
- Note: `[NEP...]` log lines come from a Studio plugin on the user's PC (not in the place). User asked to check Plugins → Manage Plugins.

## Stage status
| Stage | Status | Gate approved |
|---|---|---|
| 0 Foundations | ✅ built & tested (git pending) | awaiting user |
| 0.5 Style Test | ⏳ | — |
| 1 Flight Prototype | ⏳ | — |
| 2 Flight Visuals Ch1 + Catch Presentation | ⏳ | — |
| 3 Mood, Hazards, Return, Soundscape | ⏳ | — |
| 4 Rocket & Launch | ⏳ | — |
| 5 Base Core & Economy | ⏳ | — |
| 6 Creatures, Aquarium, Boosts, Modifiers | ⏳ | — |
| 7 Evolution/Fusion, Research, Potions, Persistence | ⏳ | — |
| 8 Packs, Sky Events, Observatory | ⏳ | — |
| 9 Chapter 2 | ⏳ | — |
| 10 Achievements, Quests, Tutorial, Balance | ⏳ | — |
| 11 Luck & Rift Ladder | ⏳ | — |
| 12 Monetization, Skins, Retention | ⏳ | — |
| 13 Buffer | ⏳ | — |
| 14 Polish & Release | ⏳ | — |

## Decisions log
- 2026-11-24: 2.5D (3D world, side-view flight camera, X/Y drone movement).
- 2026-11-24: Theme = realistic skies & space (not cute, not eerie); calm music normally, intense music + screen effects in danger.
- 2026-11-24: Solo game; competitive multiplayer is a maybe-later separate mode.
- 2026-11-24: Creatures earn money + give boosts in habitat slots; evolution via duplicates.
- 2026-11-24: Progression beyond Earth: 6 chapters to a black hole. Initial release = Ch1 + Ch2 polished.
- 2026-11-24: Soft penalties only (tow fee, drop one non-rarest creature) — never lose all cargo.
- 2026-11-24: No drone "size" upgrade (makes catching worse).
- 2026-11-24: Genre focus = collection/farm simulator for kids; online + offline earnings central.
- 2026-11-24: Art = stylized low-poly pastel, inspired by Astroneer's look (user screenshot). Original assets only. (Supersedes "realistic skies".)
- 2026-11-24: Normal flight stays 2.5D; full 3D free flight rejected (too big). 3D only inside Rifts.
- 2026-11-24: Rift ladder R1–R5: 1/500, 1/10k, 1/250k, 1/1M, 1/1B (Null Rift, name TBD). Escalating entrances.
- 2026-11-24: Monetization ON: luck gamepasses + luck potions + server luck + 2× coins/VIP/slots/etc. Odds shown; PolicyService respected; prices confirmed with user before publishing.
- 2026-11-24: Retention: daily rewards, missions, codes, group reward, leaderboards. Rebirth = future.

- 2026-11-24: Browser demo flight approved by user (movement, drone tilt, meteor showers, gameplay). Visuals of demo rejected (planets, Earth, base, blocky shapes) → must be proper 3D.
- 2026-11-24: Rarity ladder expanded to 19 normal rarities (Common → Secret) + rift rarities (Anomalous → Null, highest). Unlock progressively per chapter.
- 2026-11-24: Catch celebrations escalate per rarity tier (T0–T10), unique sound/effect/UI; Catch Card for Epic+.
- 2026-11-24: Modifiers/Enchantments on catches (Glossy → Nebula, rift-only Glitched/Null-touched) + Modifier Infuser base upgrade + Modifier Potion. Replaces "Shiny".
- 2026-11-24: User will make/provide music later; use swappable placeholders.
- 2026-11-24: **Rifts are 2.5D** (3D rejected). Rift view = "Drone Feed" overlay. Ladder expanded to 9 tiers (1/500, 2.5k, 10k, 50k, 250k, 1M, 10M, 100M, 1B). R1–R5 screen effects, R6–R9 cinematics.
- 2026-11-24: Added: creature team-ups/packs, more behaviors (Mimic, Burrower, Caller), zone-based Sky Events with modifier boosts shown in the Observatory, otherworldly endgame hazards, hazards boost rare spawns.
- 2026-11-24: Hull 0 → drone explodes, capsule returns half cargo (rarest saved). Replaces "drop one creature".
- 2026-11-24: Habitat → **Galaxy Aquarium** with zero-g swimming. Storage limited (coins/gamepass).
- 2026-11-24: Evolution Lab = Stage Evolution + **Fusion** (3/5/10 → next rarity); both timed; Evolution Potion.
- 2026-11-24: Research Station defined (tech tree, real-time). Potions system + Brewery. Achievement Board (Null = biggest reward). Quest NPCs via expansions. Rocket/drone skins with cosmetic effects.
- 2026-11-24: Monetization: fair value, no absurd passes. Rare creature calls with direction hints. Audio sourcing plan incl. AI tools (license check).
- 2026-11-24: Plan grew to 15 stages (0–14), ≈2.5–3.5 weeks.

- 2026-11-24: Added Stage 0.5 Style Test (approve the look before mass assets) and git + `src/` code backup each session.
- 2026-11-24: User set Lighting.Technology to Realistic. ShadowSoftness currently 0.2 → tune in Style Test (likely 0.4–0.6). Scripts can't change Technology (capability blocked).
- 2026-11-24: Empty folders already created in Studio (Shared/Config, Shared/Util, Assets/*, Services, Controllers, Workspace Map/Plots/FlightSpace/RiftSpace) before user stopped the premature start.
- 2026-11-24: Place published as **"Drone Catchers"** (placeId 75170479657945, universeId 10778873502). Studio API access ON — DataStore read verified. ShadowSoftness = 0.5. Devices: PC, phone, tablet.

## Approved movement numbers (from browser demo — starting point for Roblox port)
Demo units ≈ studs at 1:1 to start, retune to Roblox scale if needed.
- Drone accel 1250 u/s², exponential drag k=2.6/s (`v *= exp(-2.6*dt)`), max speed 430 u/s, slight idle bob (sin 1.3 Hz).
- Thin air above Edge-of-Space start: accel ×0.85.
- Tilt = clamp(vx × 0.0013, ±0.45 rad), smoothed with k=8.
- Camera target = drone + vel×(0.35 x, 0.25 y), smoothed k=3.5.
- Ceiling: spring push-down `vy -= (y-max)*14*dt`, one-time toast "upgrade engine".
- Beam: range 230, half-angle 0.38 rad, pull time = rarity resistance, decay 0.55/s off-beam, Rare+ struggle jerk ~2.2/s.
- Meteor shower: 2.4s warning banner → 5s active, meteors every 0.35–0.7s, each with 0.9s red dashed telegraph line, speed ~400–470 diagonal; next shower 11–16s.
- Hit: hitstop 0.07s, shake 0.7, knockback 0.5×meteor velocity; armor first, then lose lowest-rarity cargo creature.
- Mood vignette: amber in Tension, pulsing red in Danger; rise fast (k=4), fall slow (k=1.2).

## Placeholders to replace (track greybox here)
_(none yet)_

## Known issues
_(none yet)_

## Session notes
- 2026-11-24: Plan folder written. Next: user approval → Stage 0.

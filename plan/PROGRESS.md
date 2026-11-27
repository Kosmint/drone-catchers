# PROGRESS

**Current stage:** Stage 2 — Flight Visuals Ch1 + Catch Presentation (started 2026-11-24)

## Stage 1 gate feedback (user, 2026-11-24) — APPROVED, "continue with the second phase"
Liked: drone movement (lean, propellers, floor bounce), battery system, zones changing as you climb, launch/lounge flow.
Must change:
1. **UI** looks "AI-ish and simple" → real Mission Control HUD design (Stage 2).
2. **Clouds** look bad, especially in the distance → new cloud art; **each zone gets its own cloud types** (storm ≠ low sky).
3. **No green ground** → below the flight band is atmosphere/cloud sea, not an Earth-like field.
4. **Edge of Space: custom stars built into the scene** (not Roblox's skybox stars).
5. **Creatures must move/face in 3D**: pitch up when rising, down when sinking, turn left/right with movement.
6. Creature **models** too simple → Stage 6 (kept on list).
7. **Recall = player-controlled descent**, not an instant cut to base → Stage 3 re-entry (already planned).
8. Rocket launch into space → Stage 4 (already planned).

## Stage 2 — RESET to the demo look (user, 2026-11-25) ← current direction
User: scrap the painted sky, the 3D clouds and the whole Storm Layer; copy the approved Stage 0.5 browser demo style (flat low-poly 2D) into the game. Keep the drone + creature models. Zones = **Low Sky / Sunset Heights / Edge of Space** (no storm: "not realistic, clouds end in Low Sky"). Later chapters will be much longer (Low Sky ~300 km+).
- [x] `SkyController` (client) rebuilds the demo sky every flight, 1:1 with the demo code: altitude sky gradient (demo keyframes), sun glow (fades by 35 km), 180 twinkling stars, ringed planet, moon (new), Earth curve with blue rim, far blue mountains (depth 0.3), **80 flat faceted 2D clouds** at depths 0.4/0.6/0.85/1/1.25 tinted per altitude like the demo (1.25 = half-transparent in front of the drone). World layers sit at real 3D depths so perspective = the demo's parallax; screen layers are camera-locked cards in demo screen units.
- [x] Art: `art/demo_sky.py` → `art/out/demo` (8 clouds, planet, moon, earth, sun glow, 4 mountain tiles), asset ids in `Config/SkyArt`.
- [x] Chapters: Storm Layer → **Sunset Heights**; km like the demo (0–35 / 35–70 / 70–105). Storm creatures replaced by demo ones: Dusk Moth, Ember Ray, Amber Kite (new Rare), Dusk Manta; Edge gets Star Krill (Common).
- [x] ZoneLighting: no atmosphere, CC sat +0.28 / contrast +0.12 (undoes tone-mapper wash-out so the flat art shows demo colours). Deploy altitude 30 → **165 studs** (demo drops the drone at 1650 units).
- [x] Deviation from the demo: depth-1 clouds sit 1 stud *behind* the drone plane (in the demo they could hide the drone).
- [x] StormController deleted. Old scenery (painted sky, Clouds3D, Storm3D, SkyFX) parked in `ServerStorage.OldScenery` (`*_scrapped2`) — delete after the user approves the new look.
- [ ] User approval of the demo-style sky (screenshots: deploy / Sunset Heights / Edge of Space).
- [x] Earth redrawn (#30): faceted low-poly globe (ocean, original continents, polar ice, cloud streaks) in 2 tiles of 990×607 px instead of the demo wedges; colours pre-toned for the Edge of Space colour correction. Merged 2026-11-27 (muhammet842); confirm at the Stage 2 gate. Ground hills/base from the demo not ported (user earlier: no green ground).

## Stage 2 checklist (older items below the reset are superseded where they mention painted/3D clouds or the Storm Layer)
- [x] Creatures move in 3D: yaw follows travel (turns through a 3/4 view toward the camera), pitch up/down with climb/sink, bank into turns, strain away from the drone while beamed.
- [x] Clouds rebuilt per zone from the approved cloud mesh, tinted per zone via SpecialMesh.VertexColor (AI meshes + ellipsoid clouds tried and rejected: pillar/mushroom shapes, balloon look). Natural proportions, varied clusters:
  - Low Sky: soft white/peach cumulus clusters (sparse, lower half) + **cloud sea** below (green ground removed).
  - Storm Layer: slate storm towers with anvil tops, dark undercast shelves, broken storm puffs, **rain** (near streaks + distant curtains).
  - Edge of Space: violet cloud deck below (storm-tower tops poke through), high cirrus streaks, **custom twinkling stars + faint galaxy band** (camera-locked = no parallax, only above the deck horizon). Roblox skybox stars off (`Sky.StarCount = 0`).
- [x] Particle layers driven by the zone blend (`ZoneLighting.fxStars/fxRain`, emitters tagged `FxLayer`/`BaseRate`; camera-locked parts tagged `SkyLockY/Z/Roll`).
### Stage 2 — art direction change (user, 2026-11-25): "3D clouds look AI-made" → painted 2.5D sky
User showed two painted sunrise/sea-of-clouds references (style only — not copied; one is a film still, one a watermarked stock image).
- [x] **Painted parallax sky** (`art/paint_sky.py`, original procedural paintings → uploaded decals): sky gradient + glowing sun with light pillar/glare + high wisps; cloud sea in 3 tileable layers (far bands → mid rolls → near billowy rolls with silver linings, lilac shadows, painterly colour steps). Cards in `FlightSpace.Chapter1.Painted`, moved by the parallax rig (attributes SkyLockY/Z, ParallaxX/Y, AnchorAlt) — camera never rotates so flat cards are perfect.
- [x] Real sun placed behind the painted sun (Low Sky: clock 8.605, latitude −54.6) → warm back-light on drone/creatures. SunRays off where the sun is in frame (it washed the painting pink); Low Sky fog ≈ 0 (painting has its own haze); SurfaceGui Brightness 0.8 + CC contrast/saturation to beat tone-mapping wash-out.
- [x] Old 3D clouds parked in `ServerStorage.OldScenery` (delete once the painted look is approved).
- [x] Stars animated: twinkle pulses, slow rotation, size breathing, spinning glints, bright 4-point stars, shooting stars (painted sprites `star_glint`/`star_dot`).
- [x] Cloud sea rebuilt as 10 thin parallax bands (no visible layer seams when climbing).
- [x] Low Sky floating clouds = real 3D clusters (approved cloud mesh, cream tint) in `FlightSpace.Chapter1.Clouds3D` (user: must be 3D, not painted cards).
- [x] Storm Layer (user reference: dark grey storm clouds; sunset/orange version rejected): volumetric-style painted grey-teal layers + overhead ceiling (`PaintedStorm`), grey mist bands scrolling, rain; **StormController**: lightning flash every 4–10 s (double flicker, cards brighten, bolt sprite, small shake); 30% of flashes back-light a giant **sky-whale** silhouette gliding behind the clouds.
- [ ] Storm: sound + lightning strike hazard (Stage 3); whale silhouette could get a nicer second pass.
- [ ] Edge of Space painted set (deep gradient, curved atmosphere glow line, cloud deck far below) — currently plain dark sky + stars
- [ ] Sun glow / lens flare overlay; painted floating clouds near the action plane; painted-layer transitions between zones
- [ ] 3D low-poly Earth curve at Edge of Space (may become part of the painted Edge set)
### Stage 2 — catch presentation + polish (2026-11-27, through helper Issues; contract #21)
- [x] Catch contract (#21): `CatchEvents` (Caught / Landed / CardRequested / CardClosed), `Config/Celebrations`, `TimeScale`, Studio test hook `ReplicatedStorage.DevHooks.FakeCatch:Fire(<rarity>, {mods}, size)`.
- [x] Beam VFX (#22 → PR #25): rarity-tinted glow + bright core, intensity by pull progress, energy tether with flowing particles, struggle flicker, catch-snap flash, creature lean/wobble.
- [x] Catch animation (#27 → PR #34): corkscrew pull along the beam, squash & stretch, intake flash, drone gulp-hop; `Landed` fires once per catch.
- [x] Celebrations T0–T5 (#28 → PR #35): bursts, rings, light pulses, screen flash, edge glow, golden rays, T5 colour grade + particle storm; slow-mo via `TimeScale`. T3+ show the Catch Card instead of the toast.
- [x] Drone polish (#31 → PR #37): white outline, thruster glow/trail by speed, red/green blinking nav lights, rotor spin-up on deploy.
- [x] Earth redraw (#30 → PR #36), see above.
- [x] Mission Control HUD (#24 → PR #38, Çağan/Gemini): dark panels + cyan accents, battery states, hull pips, altimeter with zone bands + engine limit, cargo bay with pop, `warning(text, level)` banner, restyled toasts/base/results. Phone: touch targets ≥ 44 px, labels ≥ 10 px.
- [x] Catch Card (#23 → PR #41, Kosmint/Claude): spinning creature viewport, rarity gradient, modifier/size chips, T4 shine, T5 big card + glow, queue, 4 s auto-close; right side on PC, top-right on touch (clear of BEAM/RECALL).
- [x] Epic blink (#43 → PR #44, from Kosta's playtest): Epics teleport behind/left/right of the drone 1–2 times while pulled; deterministic from the run seed (`Shared/EpicBlink`), server minimum catch time updated, tunables in `Balance.epicBlink`.
- [x] Earth sinks as you climb (#42 → PR #46, bug from Kosta's playtest): bottom third at Edge of Space entry → bottom fifth at 600 studs (`SkyArt.earth` fill/scale).
- [ ] Scanner (#29, Çağan/Gemini): assigned 2026-11-27.
- [ ] HUD polish: "MAX LIMIT" tag overlaps "Edge of Space" at the top engine level (#47, Kosmint/Gemini).
- [ ] Mobile check of everything (#32, lead): after the scanner.
- [ ] Stage 2 gate: screenshots + summary, 2 of the 3 humans approve; then delete `ServerStorage.OldScenery`.
- Open questions for the humans: drone size (~11% of the screen height; bigger = more readable, but moves the beam nozzle); T5 pink screen and disc-looking rings (#35) to judge while playing.
- Scenery is ~1,150 static parts (no shadows). Watch mobile perf in Stage 14.
- [x] Rojo live-sync on (#12): Rojo 7.7.1 (`rokit.toml`), plugin 7.7.1, `servePlaceIds` locked to this place, `.luau` at LF. First connect changed nothing (33 scripts hash-identical before and after). From now on `src/` is the source of truth; only the lead syncs (see `AGENTS.md`).
**Last session:** 2026-11-27 (evening) — PRs #38 HUD, #41 Catch Card, #44 Epic blink, #46 Earth fix merged after Studio tests on PC + phone (Device Simulator); T3+ toast off; rule: only the lead edits PROGRESS (#45).

## Stage 1 checklist
- [x] Demo feel ported 1:1 at **0.1 studs per demo unit** (demo showed 620 units vertically = 62 studs on screen): accel 125, drag 2.6, max 43 studs/s, tilt, bob, thin air, soft walls, ceiling spring, floor. Zones are 200 studs tall (= 2000 demo units). *User must confirm it feels the same.*
- [x] FlightSpace (`Workspace.FlightSpace`, origin X=20000) + Scriptable side camera (FOV 35, distance so 62 studs fill the height, lead 0.35/0.25, smoothing 3.5, shake w/ settings toggle).
- [x] InputController on the **Input Action System** (`ReplicatedStorage.Inputs`: FlightContext Move/Beam/Aim/AimStick/Recall, BaseContext Launch). PC: WASD/arrows, mouse aim, LMB/Space beam, R recall. Gamepad: sticks, RT beam, B recall, Y launch. Touch: dynamic left thumbstick (Scriptable binding), BEAM button (auto-aim), RECALL button.
- [x] Drone sim + model: `Assets.Drones.Tier1` = the AI red quadcopter (user's pick) ×1.4, one anchored Root assembly, 4 rotors spun via Motor6D (faster when moving), tilted toward camera, catch bounce, nozzle light.
- [x] Virtual altitude → zone detection → "ENTERING <ZONE>" banner; per-zone lighting blend (`Config/ZoneLighting`: Low Sky = style baseline, Storm = slate, Edge = dark starry sky above the cloud deck), restored on return.
- [x] ExpeditionService: RequestLaunch (cooldown 20 s, seed, stats, maxAltitude from engine level) → deterministic `Shared/SpawnGen` plan (same on client + server, verified) → ReportCatch validation (spawn exists/not caught/active in its zone queue, cargo, plausible pull time) → server modifier + size roll → EndRun (cargo → inventory + collection + stats, tow fee when battery-dead). Leaving mid-run keeps cargo. Timeout safety net.
- [x] Creatures (`CreatureSimClient`): pooled per id, only rendered near the camera; Drifter, Skittish (darts away from a fast drone), Swarm (schools orbiting a moving centre, beam pulls up to 3 at once). Other behaviours fall back to Drifter until Stage 3.
- [x] Beam: aim, 0.38 rad cone, range 23 studs, pull = strength/resistance, decay off-beam, Rare+ struggle (jerk + shake), swarm multi-pull, spiral intake, progress tag above the target.
- [x] Battery (90 s idle, ×1.6 while beaming, low warning at 25%), cargo (5), Recall (dive + fade), Emergency Tow, results screen.
- [x] Temporary Mission-Control HUD (battery, hull, cargo pips, altimeter with zone bands + engine limit, toasts, wallet, launch/refuel button, results).
- [x] Debug commands (Studio/owner): `engine <1-30>`, `drone "<stat> <lvl>"`, `cooldown` (plus Stage 0 ones).
- [ ] **User playtest + feel approval** (gate).

## Stage 1 notes / decisions
- Battery base changed 60 s → **90 s** (demo was ~95 s); beam range 30 → **23 studs** (demo 230 units). Creature density raised to **12 per 100 studs** (demo-equivalent 7 felt empty in 3D). Swarm drift slowed to demo speeds.
- Engine level 1 reaches 260 studs (Low Sky + bottom of Storm Layer); level 30 reaches the top (600). Use `engine 30` to see Edge of Space now.
- This place has **no PlayerModule** in PlayerScripts → the character is frozen during flight by anchoring HRP + zeroing WalkSpeed/Jump.
- Studio only: a session lock left by a previous Studio playtest is ignored (stopping a playtest can cut the release save short → next playtest got kicked). Live servers keep the strict lock.
- Testing tips: `user_mouse_input` uses GUI coordinates (viewport y − 58 top inset). Studio's MCP HTTP allowlist blocks localhost (a local file server to sync `src/` would need the user to allow `localhost` under Assistant Settings → MCP Permissions).

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
- [x] git initialized (branch `main`), first commit b47c428. `.rbxl` files ignored (place versions live on Roblox). Note: PowerShell needs PATH refresh in this session to find git.
- Note: Edit-mode DataStore WRITES are forbidden for the MCP tool (502 Access forbidden); reads work. Do data fixes from the Server datamodel during a playtest.
- Note: `[NEP...]` log lines come from a Studio plugin on the user's PC (not in the place). User asked to check Plugins → Manage Plugins.

## Stage status
| Stage | Status | Gate approved |
|---|---|---|
| 0 Foundations | ✅ built & tested | ✅ |
| 0.5 Style Test | ✅ built (scene `Workspace.StyleTest`), style guide in 03 §1a | ✅ 2026-11-24 |
| 1 Flight Prototype | ✅ built & tested | ✅ 2026-11-24 |
| 2 Flight Visuals Ch1 + Catch Presentation | 🔨 in progress | — |
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

- 2026-11-24 (Stage 0.5 feedback): user OK'd the sky/clouds look for early stage; models "too simple/blank" for now (fine for early stage, detail/animation/effects later). User **likes the red AI quadcopter** (`StyleTest.Drone_AI`) more than the hand-built drone → use it as drone base (re-check it from the side flight camera in Stage 1). Its baked propellers were replaced: mesh segmented (body/arms/legs), 4 hand-built rotors (`Drone_AI.Rotors.Rotor1-4`: Hub + Cap + exactly 2 gray blades welded to Hub, verified spinning in playtest). No spin script yet (add in Stage 1/2: rotate each Rotor's Hub; blades follow via welds). User likes the AI Cloud Puff too (possible variant/other common creature).
- FIXED (2026-11-24, Stage 1 session): editor camera was left `Scriptable` by screen_capture → reset to `Fixed`. If it happens again, run `workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed` in the command bar.
- Place saved to Roblox version 9. Roblox save gave transient HTTP 500 once; retry later works.

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
- All 12 creatures use one tinted Cloud Puff model (`Assets.Creatures.Placeholder`) → final models **Stage 6** (`Assets.Creatures.<Id>` is picked up automatically).
- Celebration sounds are empty slots (`Config/Celebrations`) → **Stage 3** audio.
- HUD is temporary → final Mission Control HUD **Stage 2**.
- Launch = fade to the sky (no rocket) → rocket + launch sequence **Stage 4**. Return = short dive + fade → re-entry **Stage 3**.
- `Workspace.StyleTest` reference scene still sits above the spawn (visible from the base) → remove/move when the base is built (**Stage 5**).

## Known issues
_(none yet)_

## Session notes
- 2026-11-24: Plan folder written. Next: user approval → Stage 0.
- 2026-11-25: Flight visuals = the approved browser demo style (flat low-poly 2D sky + clouds). Storm Layer removed → Sunset Heights. Thunderstorm sky event will need a new home zone (Stage 8).

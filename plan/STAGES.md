# STAGES — Build Plan

Each stage ends at a **Gate**. A gate passes only when ALL are true:
1. Every task checked in `PROGRESS.md`.
2. Playtested in Studio (`start_stop_play`), console has **no errors/warnings from our code**.
3. Screenshots (`screen_capture`, `video_capture` for motion) of key moments, judged against the quality bar (`03_ART_AND_AUDIO.md` §1).
4. Works on PC + mobile emulation (from Stage 2 on).
5. Summary + screenshots shown to the user, **user approves**.
6. Place saved + backup in `backups/`.

Estimates are guides, not targets. Total ≈ **2.5–3.5 weeks** of focused work. Never rush a gate.

---

## Stage 0 — Foundations (≈0.5 day)
- [ ] Inspect the place (`search_game_tree`), clear default junk, Lighting = Future, decide StreamingEnabled (likely off; revisit in polish).
- [ ] Hierarchy from `01_ARCHITECTURE.md` §2.
- [ ] Shared utils: Signal, Trove, Spring, StateMachine, WeightedRandom, NumberFormat, Cinematic timeline, Types.
- [ ] `Net` module: all remotes in one place, rate limiting + type validation.
- [ ] Config modules stubbed with Chapter 1 data (rarities, modifiers, creatures, upgrades, balance).
- [ ] ServerMain / ClientMain bootstraps with ordered init + error isolation.
- [ ] DataService v1 (session lock, retries, autosave, BindToClose, migration hook; Studio fallback).
- [ ] Debug command module (Studio/owner only).
- [ ] Unit tests: NumberFormat, WeightedRandom, cost formulas.
- [ ] **Code backup:** `git init` in the project folder (with `.gitignore` for backups/*.rbxl if large), export every script from Studio into `src/` (mirroring the Studio hierarchy, `.luau` files), first commit.
**Gate:** game runs, data persists, debug commands work, tests pass, code backed up in git.

## Stage 0.5 — Style Test (≈0.5 day) — protects the whole project
**Goal:** prove the Astroneer-inspired stylized low-poly look works in Roblox *before* mass-producing assets.
- [ ] Lighting baseline: Technology Realistic/Future (set by user), ShadowSoftness (try ~0.4–0.6 for soft stylized shadows), Atmosphere, ColorCorrection, Bloom tuned to the pastel palette.
- [ ] Build in final style: **1 creature** (e.g. Cloud Puff, with idle motion + rarity glow), **1 cloud cluster**, **the T1 drone**, **a slice of Low Sky** (sky gradient + parallax clouds) and a hint of the base ground.
- [ ] Try both approaches and pick the better: hand-built faceted Parts/MeshParts vs. `generate_mesh`/`generate_procedural_model` refined by hand.
- [ ] Screenshots from the side-view flight camera angle (how players will actually see it) + a close-up.
- [ ] Write the chosen recipe (materials, colors, facet density, glow rules) into `03_ART_AND_AUDIO.md` as the style guide all later assets follow.
**Gate:** user approves the look. If not → iterate here, never move on with a look the user dislikes.

## Stage 1 — Flight Prototype (greybox, ≈1 day)
- [ ] Port the **approved demo feel** (PROGRESS.md numbers); user confirms it feels the same in Roblox.
- [ ] FlightSpace + side-view `Scriptable` camera (lead + smoothing).
- [ ] InputController (PC / gamepad / mobile) — load `rbx-input-action-system`.
- [ ] Drone sim: accel/drag, tilt, bounds, ceiling.
- [ ] Virtual altitude + Ch1 zone detection + basic sky color change.
- [ ] ExpeditionService: launch → runState with seed; deterministic spawn lists client & server.
- [ ] Creature spawning (pooled) with Drifter / Skittish (fish-like darting) / Swarm.
- [ ] Beam: aim, cone, pull, struggle; ReportCatch validation; server modifier/size roll.
- [ ] Battery, cargo, Recall, basic return; temporary HUD.
**Gate:** user plays and it feels good. Greybox allowed only here.

## Stage 2 — Flight Visuals Ch1 + Catch Presentation (≈2 days)
- [ ] Zone presets 1.1/1.2/1.3 (Atmosphere, Sky, ColorCorrection, Bloom, SunRays) with smooth blending, Astroneer-inspired pastel low-poly look.
- [ ] Parallax layers (horizon, cloud banks, storm clouds, aurora, stars) + foreground layers.
- [ ] 3D low-poly **Earth** at Edge of Space (continents, cloud layer, atmosphere glow).
- [ ] Drone T1 model (thrusters, lights, tilt, deploy anim).
- [ ] Beam VFX (rarity-tinted, intensity by progress) + creature stretch/struggle.
- [ ] Catch animation: spiral pull, squash & stretch, intake flash, drone bounce, cargo pop.
- [ ] Celebration tiers T0–T5 with distinct VFX/sound/UI; **Catch Card** (ViewportFrame, rarity gradient, modifier tag).
- [ ] Final flight HUD (Mission Control): altimeter, battery, hull, cargo icons, scanner ring, Recall, warning banner, active potions row (placeholder).
- [ ] Scanner: "?" edge blips, Hidden reveal.
**Gate:** every zone screenshot is thumbnail-worthy; catches feel rewarding; mobile HUD checked.

## Stage 3 — Mood, Hazards Ch1, Return Trip, Soundscape (≈1.5 days)
- [ ] MoodController (Calm/Tension/Danger/Triumph) + post-processing, shake, vignette, FOV; shake accessibility toggle.
- [ ] Audio foundation: SoundGroups, placeholder music layers (calm/tension/danger/base), crossfades, Config/Audio.
- [ ] Ch1 hazards at high quality: wind gusts, storm + telegraphed lightning, meteor showers (close-pass whoosh/shockwave/shake even on misses), sky predators, thin air/cold.
- [ ] Hazard rewards: boosted rare spawns/modifiers during hazards.
- [ ] Hull system; **drone explodes at 0 hull → emergency capsule returns half the cargo** (rarest always saved).
- [ ] Re-entry descent; battery death → Emergency Tow + fee.
- [ ] Remaining behaviors: Phaser, Heavy, Hidden, Conditional, Aggressive, Mimic, Burrower, Caller.
- [ ] SoundscapeController: living-sky ambience (growls, roars, creaks, whale calls, panned), giant background silhouettes, **rare creature calls + direction hint**.
**Gate:** a run goes calm → tense → intense → relief; hazards look and sound great; rare calls make the user want to hunt.

## Stage 4 — Rocket & Launch Sequence (≈1 day)
- [ ] Rocket T1 (scrappy) + T2 (clean) at high quality; engine levels visibly add engines/exhausts/fins/lights.
- [ ] Launch pad + console (ProximityPrompt), chapter selector.
- [ ] Countdown, ignition VFX/SFX, pad steam, rumble.
- [ ] Timing mini-game (Perfect/Good/Bad), server-clamped.
- [ ] 3D rocket filmed side-on, ascent → smooth transition to flight view; separation; drone deploy.
- [ ] Ascent debris steering (ready for Ch2); launch cooldown.
**Gate:** launch looks/sounds great, no camera pops.

## Stage 5 — Base Core: Plot, Hangar, Workshop, Market, Storage, Economy (≈2 days)
- [ ] Base environment: plateau, terrain, paths, lighting, sky view, day/night, ambient life.
- [ ] BaseService: plot assignment, station unlock flags, expansion framework.
- [ ] Drone Hangar (model + UI): 7 drone upgrades, drone display updates.
- [ ] Rocket Workshop: engine/fuel/heat shield; rocket on pad updates.
- [ ] Market: sell UI + **High Demand board** (rotating, countdown, +50–200%).
- [ ] Storage Vault: capacity + upgrades.
- [ ] EconomyService (online income ticks), UpgradeService, purchase animations.
**Gate:** full loop playable: launch → catch → sell → upgrade → fly higher. Base looks finished.

## Stage 6 — Creatures, Galaxy Aquarium, Boosts, Modifiers, Collection (≈2.5 days)
- [ ] Final models for 12 Ch1 creatures × 3 stages, idle animations, consistent style.
- [ ] **Galaxy Aquarium**: beautiful starry zero-g dome, **zero-g swim controller** (PC/mobile/gamepad), creatures roam (boids), click for info card.
- [ ] Boost slots UI + BoostService (5 families) + boost display.
- [ ] Income per creature (×2 in boost slots).
- [ ] **Modifiers**: 12 visual presets (flight + aquarium), multipliers, Catch Card tag.
- [ ] **Modifier Infuser** + **Luck Reactor** stations (luck math hooked up; rifts come later).
- [ ] Collection Book (silhouettes, stages, modifiers seen, completion rewards).
- [ ] Size roll (decide with user).
**Gate:** creatures look great in flight AND aquarium; swimming among them feels magical.

## Stage 7 — Evolution Lab, Research, Potions, Persistence & Expansion (≈2 days)
- [ ] Evolution Lab machine: **Stage Evolution** (duplicates, coins, time) and **Fusion** (3/5/10 same-rarity → next rarity) with animations and timers.
- [ ] Research Station: tech tree (Drone Tech / Economy / Exploration / Lab), real-time timers.
- [ ] PotionService: all potions (Luck, Modifier, Speed, Battery, Magnet, Coin, Evolution, Research), HUD timers, stacking rules; **Potion Brewery** (coins + essence).
- [ ] Offline earnings + "Welcome back" popup.
- [ ] Base expansions (build-in animation), more slots/storage/aquarium size.
- [ ] Settings menu (music/SFX volume, shake toggle).
- [ ] Data stress tests: rejoin, leave mid-run, rapid purchases, mid-timer leaves, shutdown.
**Gate:** no data loss; timers survive offline; returning feels rewarding.

## Stage 8 — Creature Packs, Sky Events, Observatory (≈1.5 days)
- [ ] Pack system: Guarded Giant, Herd + Leader, Escort, Bait & Ambush, Symbiotes.
- [ ] SkyEventService: zone-based events (Thunderstorm, Meteor Shower, Star Shower, Aurora Night, Crystal Hail, Whale Migration, Rift Storm… Ch2 ones in Stage 9), schedules + random, spawn/modifier multipliers, server-wide timers.
- [ ] Event visuals/audio + "EVENT ACTIVE" HUD indicator.
- [ ] Observatory: telescope camera view with sky map showing **where** events are active, upcoming timers, rare sightings.
**Gate:** events make the user want to launch *now*; packs are challenging but fair.

## Stage 9 — Chapter 2: Near Space (≈2.5 days)
- [ ] Orbital Booster tech unlock cinematic + Rocket T3.
- [ ] Zones 2.1/2.2/2.3 presets + parallax; **3D planets/Moon** at a high bar (not "AI-ish").
- [ ] Hazards: debris, satellites, micrometeoroids, radiation belt, asteroid collisions; ascent debris dodging.
- [ ] Ch2 events: Nebula Bloom, Solar Flare, Comet Pass, Eclipse, Blood Moon.
- [ ] 11 Ch2 creatures × 3 stages (Mythic, Celestial; Nebula modifier), Ch2 packs.
- [ ] Space music set + space soundscape; Drone T2.
**Gate:** reaching space feels like a big moment; Ch2 clearly a new world.

## Stage 10 — Achievements, Quest NPCs, Tutorial, Balancing (≈1.5 days)
- [ ] Achievement Board (rocket levels, collection, rarities, rifts incl. huge Null reward, skill, economy).
- [ ] Quest NPCs (Collector, Engineer, Astronomer, Merchant) with houses unlocked by expansions, rotating daily quests, chains.
- [ ] Daily/weekly missions, daily login streak.
- [ ] Onboarding tutorial (first 5 minutes).
- [ ] Balancing pass with a simulation script: pacing Ch1 45–75 min, Ch2 2–3 h; luck/modifier/fusion economy; no grind walls.
**Gate:** fresh player goes from zero to space without confusion; always has a goal.

## Stage 11 — Luck & Rift Ladder (2.5D) (≈2.5 days)
- [ ] RiftService: server roll per launch, 9 tiers (1/500 → 1/1B), odds ÷ luck, cap.
- [ ] Drone Feed overlay (scanlines, noise, timestamp, glitchy HUD).
- [ ] Rift zones R1–R9 (2.5D) with visuals, hazards (incl. otherworldly: Reality Tears, Echo Drone, Void Tendrils, Color Drain, Collapsing Space, Watcher Eyes, Singing Stars, Gravity Flip), exclusive creatures.
- [ ] Entrances: screen effects R1–R5; cinematics R6–R9; Null full cinematic.
- [ ] Rift rarities + celebration tiers T6–T10 + rift-only modifiers (Glitched, Null-touched).
- [ ] One **Secret** creature each for Ch1 and Ch2.
- [ ] Announcements (server R3+, global R6+ via MessagingService), Rarest Finds leaderboard, Rift Shrine/Odds Board, Collection Book rift page.
- [ ] Debug: force rift tier.
**Gate:** every entrance recorded with `video_capture`; Null makes the user say "wow".

## Stage 12 — Monetization, Skins, Retention Extras (≈2 days)
- [ ] Load `rbx-process-receipt-misuse`, `rbx-open-cloud-usage`, `roblox-dev:roblox-security`.
- [ ] MonetizationService: pass ownership cache, idempotent ProcessReceipt with dedupe, PolicyService checks.
- [ ] Create passes/products — **prices confirmed with user**, fair value, no absurd passes.
- [ ] Gamepasses: Lucky Drone, Super Lucky Drone, 2× Coins, VIP, Extra Boost Slots, Bigger Storage, Auto-Collect, Fast Launch, Bigger Cargo.
- [ ] Products: potions, Server Luck (announced), Coin Packs, Instant Recharge, premium skins.
- [ ] **Skin Bay + SkinService**: rocket & drone skins with cosmetic effects (beam, trail, capture, flame, sound); coin / Robux / achievement / event sources.
- [ ] Shop Kiosk + HUD shop; odds displayed wherever luck is sold.
- [ ] Codes, group reward, leaderboards (OrderedDataStore).
- [ ] Purchase tests incl. rejoin/duplicate receipts.
**Gate:** purchases grant exactly once; restricted players see no paid random items; free path complete.

## Stage 13 — Buffer: Combos / Extra Content / Fixes (≈1 day)
- Combo bonuses, extra creatures/events, or fixes from earlier stages. Skip if not needed.

## Stage 14 — Polish, Performance, QA, Release (≈1.5 days)
- [ ] Perf profiling (`rbx-perf-profiling`), leak check (`rbx-luau-heap-profiling`), mobile 60 FPS.
- [ ] Device Simulator pass (phone/tablet/console).
- [ ] Security review (`roblox-dev:roblox-reviewer`).
- [ ] Sound mix, UI consistency, typo pass; swap in user's music if ready.
- [ ] Game icon/thumbnails captured in-game, title, description.
- [ ] Full playthrough Ch1→Ch2 + forced rift of every tier + every purchase + aquarium + lab; zero critical bugs.
**Gate:** user is proud to publish it.

---

## Future (after release)
- Chapters 3–6 (Solar System → Deep Space → Another Galaxy → Black Hole), each ≈2–3 days, with new rarities, events, otherworldly hazards, rocket tiers T4–T7.
- More rift tiers and rarities.
- Rebirth / "Re-launch Program".
- Holiday events.
- Optional competitive multiplayer mode.

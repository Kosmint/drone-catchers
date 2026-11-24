# 01 — Technical Architecture

## 1. Tooling & workflow
- Place file: `myrobloxgametestclaude.rbxl` (workspace root). Built directly in **Roblox Studio via the Roblox Studio MCP** (`multi_edit`, `execute_luau`, `script_read`, `search_game_tree`, `inspect_instance`, `start_stop_play`, `screen_capture`, `get_console_output`, `save_place`).
- All scripts use `--!strict` Luau where practical (load `roblox-dev:luau-strict-typing`).
- **ModuleScript architecture** (load `roblox-dev:roblox-architecture`): one Server bootstrap `Script`, one Client bootstrap `LocalScript`, everything else ModuleScripts. No `_G`.
- **Mirror source to disk:** after each session, export all script sources into `src/` (via `script_read`) so code is reviewable/diffable. (Optional upgrade: Rojo later.)
- Backups: `backups/stageXX_<date>.rbxl` at each gate.

## 2. Studio hierarchy
```
ReplicatedStorage
  Shared/
    Config/            -- pure data, no logic
      Chapters         -- chapters, zones, altitude ranges, sky presets, hazards
      Creatures        -- full roster (id, name, rarity, zone, behavior, value, income, boost, evolution)
      Rarities         -- full ladder (19 + rift rarities), colors/gradients, weights, resistance, value mult, celebration tier
      Modifiers        -- modifier list, weights, value mult, visual preset (material/color/particles), availability (chapter/rift-only)
      Upgrades         -- rocket / drone / base upgrade tables + cost formulas
      Boosts           -- boost families, stacking rules, caps
      Mood             -- intensity thresholds, effect values per state
      Audio            -- asset ids per zone/state, SFX ids
      Balance          -- global numbers (battery drain, offline cap, tow fee, etc.)
    Types              -- shared Luau types (PlayerData, CreatureInstance, RunResult...)
    Util/              -- Signal, Maid/Trove (cleanup), Spring, math helpers, NumberFormat (1.2K, 3.4M...)
    Net                -- remote definitions (single place to declare all remotes)
  Assets/
    Creatures/<Id>/Stage1..3 models
    Rockets/Tier1..N
    Drones/Tier1..N
    VFX/  (beam, catch pops, lightning, explosions, warp)
    Sky/  (parallax layer models/decals per zone)
    UI/   (image assets)
ServerScriptService
  ServerMain (Script)  -- bootstraps services in order
  Services/
    DataService        -- load/save, session lock, autosave, BindToClose, schema migration
    EconomyService     -- coins, income ticks, offline earnings, selling
    UpgradeService     -- validates & applies upgrades
    RunService_        -- (name: ExpeditionService) run lifecycle: start, seed, creature spawn list, catch validation, end/return, tow
    CreatureService    -- ownership, storage, habitat slots, evolution
    BoostService       -- computes active boosts from habitat → effective stats
    BaseService        -- player plot assignment, station unlocks, expansion, spawning base visuals
    ResearchService    -- timed research
    EventService       -- server-wide sky events / daily rare / market demand
    LuckService        -- computes total luck (upgrades × creatures × passes × potions × server boosts), cap
    RiftService        -- server-side rift roll per launch, rift run state, rift catch validation
    AnnounceService    -- server + cross-server (MessagingService) announcements, leaderboards (OrderedDataStore)
    MonetizationService-- gamepass ownership cache, ProcessReceipt (idempotent, purchase-id dedupe), PolicyService checks
    RetentionService   -- daily rewards, missions, codes, group reward
    AchievementService -- achievement tracks, progress counters, reward claims
    QuestService       -- NPC quests (rotating daily), quest chains
    PotionService      -- potion inventory, activation, timers, brewery
    FusionService      -- (part of CreatureService or separate) stage evolution + fusion timers and results
    SkinService        -- owned/equipped rocket & drone skins, cosmetic effect presets
    SkyEventService    -- zone-based sky events (schedule + random), spawn/modifier multipliers, Observatory data
StarterPlayerScripts
  ClientMain (LocalScript) -- bootstraps controllers
  Controllers/
    InputController    -- unified PC/mobile/gamepad (load rbx-input-action-system skill)
    CameraController   -- base camera, launch cinematic, side-view flight cam, shake
    LaunchController   -- console UI, countdown, timing mini-game, ascent
    FlightController   -- drone sim (X/Y), parallax, zone detection, hazards client-side
    BeamController     -- beam aim, pull progress, struggle, catch FX
    CreatureSimClient  -- spawns/animates creature visuals from server seed
    MoodController     -- calm/tension/danger state, audio crossfade, post-processing
    HUDController      -- altimeter, battery, cargo, scanner, toasts
    BaseUIController   -- station UIs (hangar, workshop, habitat, lab, book, observatory, research, market)
    TutorialController
    RiftController     -- per-tier entrance effects/cinematics, Drone Feed overlay
    AquariumController -- zero-g swim movement + creature wandering visuals
    SoundscapeController -- living-sky ambience, rare creature calls with direction hints, panning
    ShopController     -- shop UI, prompts purchases (never grants; server grants)
StarterGui
  (ScreenGuis built by code or as templates; one per major UI)
Workspace
  Map/ (shared world: terrain, background mountains, horizon)
  Plots/ (player base plots)
  FlightSpace/ (far-away region where flight happens; see §4)
Lighting
  Atmosphere, Sky, ColorCorrection, Bloom, SunRays, DepthOfField, Blur (driven by MoodController + zone presets)
SoundService
  SoundGroups: Music, Ambience, SFX, UI
```

## 3. Client/server split (solo game, but economy is server-authoritative)
- **Server owns:** coins, owned creatures, upgrades, unlocks, run start/end, what creatures exist in a run, catch acceptance, rewards.
- **Client owns:** drone movement, camera, visuals, audio, beam feel (for zero-latency feel).
- **Run flow:**
  1. Client `RequestLaunch(timingQuality)` → server validates (not mid-run, cooldown, timing value clamped) → creates `RunState` {runId, seed, maxAltitude, effective stats, startTime} → returns it.
  2. Client generates creature spawns deterministically from `seed` + zone config (server generates same list). Each spawned creature has a `spawnId`.
  3. On catch: client `ReportCatch(runId, spawnId)` → server rolls **modifier + size** (server RNG, with luck/modifier chance) and returns them so the client plays the right celebration. Server checks: spawnId exists in its list, not already caught, cargo not full, zone reachable with maxAltitude, minimum time since run start / since last catch plausible (≥ creature min catch time), rate limit. Server adds to run cargo (not to inventory yet).
  4. `Recall` / `Landed(runId, hitsTaken)` → server finalizes: cargo → inventory, applies dropped-creature penalty (server picks which), tow fee if battery-dead (server also tracks expected battery from timings).
  5. Leaving mid-run → cargo is auto-returned (generous).
- Load `roblox-dev:roblox-security` before writing remotes. All remotes rate-limited and type-checked.

## 4. Flight space & coordinates
- Roblox float precision degrades far from origin → flight space must stay within ~±20k studs.
- **Design:** flight happens in `Workspace.FlightSpace` at a far X offset (e.g. X = 20000) so the base isn't visible. The drone plane is Z = const.
- **Altitude is virtual.** Each zone is a vertical **segment** of ~1500 studs in world space. Displayed altitude (km) is mapped per zone (e.g. Low Sky 0–10 km, Storm 10–25 km, Edge of Space 25–100 km, Orbit 100–2000 km, … black hole = "∞" style).
- **Chapter streaming:** only the current chapter's zones are built in FlightSpace (each chapter ≤ ~5000 studs tall). Changing chapter mid-run isn't possible (chapter determined by rocket's max altitude); one run = one chapter's zones up to max altitude. Lower chapters still reachable by choosing a "target chapter" at the Launch console (so players can farm earlier zones).
- **Parallax:** background layers are parented to a camera-anchored folder and offset at fractions of drone movement (far 0.05, mid 0.2, near 0.5); foreground particles at 1.2.
- **Sky/Lighting blending:** zone presets (Atmosphere density/color/haze, Sky skybox, ColorCorrection, ambient) are lerped based on drone Y within transition bands.

## 4b. Rift zones (2.5D)
- Rifts are **2.5D** like normal flight (user decision). Each rift tier is a special zone built in `Workspace.RiftSpace` (separate far offset, e.g. X = −20000) from a prebuilt model in `ReplicatedStorage.Assets.Rifts`, cloned on entry and cleaned up after.
- Same drone sim, camera, beam and creature systems; rifts only swap the zone preset, parallax layers, creature table, hazards, and add the **"Drone Feed" overlay** (scanlines, noise, glitch, timestamp, distorted HUD).
- Entrances: R1–R5 = screen-effect overlays (ScreenGui + post-processing); R6–R9 = scripted cinematics (camera choreography + VFX + audio timeline), built with a small reusable **Cinematic timeline** utility.
- Rift roll: `RiftService` rolls server-side at launch with server `Random.new()`; result sent to the client only when the entrance starts.

## 4c. Galaxy Aquarium (zero-g habitat)
- An interior space on the base. On entering, the client switches the character to a **zero-g swim controller** (custom movement: Humanoid PlatformStand/physics-off + LinearVelocity, or a custom character mover), camera follows; leaving restores normal walking.
- Creatures roam using lightweight boid-style wandering (client-side visuals; ownership/income are server data).
- Instance budget: cap visible creatures (e.g. 40), LOD distant ones, pool models.

## 5. Data schema (v1)
```lua
PlayerData = {
  version = 1,
  coins = 0,
  stats = { totalRuns, totalCatches, bestAltitude, perfectLaunches, playTime },
  rocket = { engine = 1, fuel = 1, heatShield = 0, gravityShield = 0, tech = "Chemical" },
  drone = { battery = 1, speed = 1, beamStrength = 1, beamRange = 1, cargo = 1, scanner = 1, armor = 1 },
  creatures = { [uid] = { id = "CloudPuff", stage = 1, caughtAt = os.time(), modifiers = { "Blazing" }, size = "Normal" } },
  modifierInfuserLevel = 0,
  habitat = { slots = 2, placed = { uid1, uid2 } },
  collection = { [creatureId] = { caught = n, maxStage = s, firstCaughtAt = t } },
  base = { unlockedStations = {...}, expansions = {...} },
  research = { active = { id, endsAt }, done = { ... } },
  tutorial = { step = 0, done = false },
  luck = { reactorLevel = 0 },
  rifts = { seen = { [tier] = count }, best = tier },
  purchases = { processedReceiptIds = {...} },  -- dedupe ProcessReceipt
  retention = { loginStreak, lastLoginDay, missions = {...}, redeemedCodes = {...}, groupRewardClaimed },
  storage = { cap = 50 },
  lab = { evolutions = { { uid, targetStage, endsAt } }, fusions = { { inputs = {uids}, endsAt, resultSeed } } },
  potions = { owned = { [kind] = count }, active = { [kind] = endsAt } },
  achievements = { [trackId] = { progress, claimedTier } },
  quests = { active = { ... }, completedChains = { ... }, lastRefreshDay },
  skins = { owned = { ... }, equipped = { rocket = "Default", drone = "Default" } },
  settings = { musicVol, sfxVol, shake = true },
  lastOnline = os.time(),
}
```
- Load `roblox-dev:roblox-datastores`: session locking, retries with backoff, autosave every 60–120s, `BindToClose`, migration via `version`.
- Offline earnings on join: `min(now - lastOnline, offlineCap) * incomePerSec * offlineRate(0.5 base)`, shown in a "Welcome back" popup.

## 6. Shared utilities to write once
- `Signal`, `Trove` (cleanup of connections/instances — mandatory for every controller to avoid leaks), `Spring` (camera & UI smoothing), `Tween helpers`, `NumberFormat`, `WeightedRandom` (seeded with `Random.new(seed)`), `StateMachine` (used by Mood, Run, Tutorial).

## 7. Performance rules (load `roblox-dev:roblox-performance`)
- Pool creature models and VFX; never create/destroy per frame.
- Single `RenderStepped`/`PreRender` loop per controller; no per-frame table allocations in hot paths.
- Limit active creatures to what's near the camera (spawn ring); despawn far ones to pool.
- Parallax layers: low part counts, use decals/textures/billboards for distant layers.
- Target 60 FPS on mid phones; profile with `rbx-perf-profiling` at polish stages.

## 8. Testing approach
- Pure-logic modules (economy formulas, boost stacking, evolution costs, spawn tables, data migration) get unit tests (`rbx-unit-test` skill).
- Gated **debug commands** (only in Studio / for owner): give coins, set altitude, spawn creature, force mood state, unlock all — for fast QA (load `roblox-dev:roblox-testing`).
- Every stage gate: playtest via `start_stop_play`, `screen_capture` key moments, `get_console_output` must be free of errors/warnings from our code.
- After big systems: run `roblox-dev:roblox-reviewer` agent for security/leak review.

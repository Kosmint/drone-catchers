# 00 — Game Design Document

## 1. Pillars
1. **Every run feels like an expedition.** Launch → explore → catch → survive the return.
2. **Calm, then pressure.** Relaxing by default; danger is sudden, readable and exciting.
3. **Visible progress.** Rocket grows, base expands, sky gets further and stranger, collection book fills up.
4. **Long-term depth.** Chapters out to a black hole, evolution & fusion, boosts as a loadout, research, achievements, rifts.
5. **Polish over quantity.** Fewer, finished things beat many rough things. Every hazard, catch and sound must feel high quality.
6. **The sky is alive.** Sounds, silhouettes and events make players curious ("what was that roar?").

## 2. Core loop
```
BASE: collect income → upgrade rocket / drone / base → set habitat boosts → check Observatory (events) → take NPC quests
  ↓
LAUNCH: walk to launch pad → press Launch → timing mini-game → ascent (dodge debris) → (tiny chance: RIFT)
  ↓
FLIGHT (2.5D): drone deploys at max altitude → explore zones → scan → beam creatures → manage battery/cargo/hazards
  ↓
RETURN: press Recall (or battery dies) → re-entry descent with hazards → land
  ↓
BASE: catch reveal → creatures to Galaxy Aquarium/storage → money (online + offline) → evolve/fuse → repeat
```
Target run length: **3–6 minutes** early, up to ~8 later.

## 3. Launch sequence
1. Player interacts with the **Launch Console** at the pad (ProximityPrompt) → Launch UI (choose chapter to fly in, see active potions/luck).
2. **Countdown** 3‑2‑1 with smoke, rumble, camera shake.
3. **Timing mini-game:** a power bar sweeps; pressing in the green "sweet spot" gives a **Perfect Launch** (+10% max altitude this run, + small battery bonus); "Good" = normal; "Bad" = −10% altitude. Bar speed grows slightly per chapter. Never fails the launch.
4. **Ascent:** 3D rocket filmed from the side ("3D in a 2D perspective"), camera follows up, then transitions smoothly into the flight side view. During ascent (Chapter 2+) the player steers left/right to dodge debris; hits reduce altitude slightly.
5. **Rift check:** the server rolls the Rift Ladder (§9) during ascent. If a rift hits, its entrance plays instead of normal deploy.
6. **Stage separation:** boosters fall away with VFX, the **drone deploys** out of the nose cone. Flight begins.

## 4. Flight (2.5D)
- **View:** 3D world, `Scriptable` side camera, narrow FOV (~30–40) for a flat look, slight lead for smoothness. Drone moves on X/Y; Z fixed. **Movement feel approved from the browser demo** (numbers in `PROGRESS.md`) — may still be tuned during development.
- **Space:** wide horizontal band and vertical range from zone floor to the **rocket's max altitude** (engine-limit ceiling with visual warning).
- **Parallax:** 3–5 background layers per zone + foreground layers passing in front of the drone.
- **Drone stats (upgradable):** Battery, Speed, Beam Strength, Beam Range, Cargo Slots, Scanner Range, Armor (hull).
- **Battery:** drains steadily; faster while beaming and when hit. Low battery (<25%) → Tension.
- **Scanner:** creatures beyond scanner range show as faint "?" blips at the screen edge; inside range they reveal with a rarity ring. Hidden creatures appear only when scanned.
- **Altimeter HUD:** altitude, zone name, vertical zone map, engine limit line.

### Suction beam & catching
- Hold Beam → cone toward the aim direction (mouse / right stick / mobile auto-aim to nearest creature in cone).
- Pull progress = BeamStrength / Resistance. Rare+ **struggle** (jerk away, progress falls if the beam slips). High rarities may break free or fight back.
- Catch: **spiral pull along the beam**, squash & stretch, swallowed by the drone intake with a flash and drone bounce, cargo slot fills with a pop. Then the rarity's **celebration tier** plays (T0 pop → T10 Null cinematic; `02_CONTENT.md` §1b), each with its own sound, effect and UI. Epic+ show a **Catch Card** (spinning 3D creature, name, rarity, modifier, size).
- Each catch rolls a **Modifier/Enchantment** (`02_CONTENT.md` §1c) that multiplies value and changes the look.
- Rarity ladder: 19 normal rarities (Common → Secret) + rift rarities (Anomalous → **Null**, highest). `02_CONTENT.md` §1. More rarities will be added as the game grows.
- Cargo full → beam disabled, "CARGO FULL — Recall".

### Creature behaviors (variety in *how* you catch)
| Behavior | Description |
|---|---|
| Drifter | Floats slowly, easy. |
| Skittish | Like a fish: if you approach fast it darts away quickly. Approach slowly or cut it off. |
| Swarm | Moves in groups; one pull can catch several (cargo permitting). |
| Hidden | Invisible until scanned (scanner pulse reveals a shimmer). |
| Conditional | Only spawns during specific Sky Events (§4b). |
| Aggressive | Chases and damages the drone. Triggers Danger. |
| Heavy | Huge resistance, needs a strong beam; very valuable. |
| Phaser | Blinks between positions; catch during its visible window. |
| Mimic | Disguised as a cloud/rock/star until the scanner or beam touches it, then bolts. |
| Burrower | Hides inside cloud banks / asteroid holes and peeks out; beam it when it shows. |
| Caller | Emits a distinctive sound that attracts others of its kind (or warns them to flee). |

### Creature team-ups (packs) — user idea, **in scope**
Creatures can appear as **groups that work together**, making high-value catches harder:
| Pack | Composition | How it plays |
|---|---|---|
| **Guarded Giant** | 1 Heavy (valuable) + ring of 4–8 Aggressive guards | Guards orbit the giant and attack when you approach; lure guards away, catch them first, or dodge in and pull fast. |
| **Herd + Leader** | Swarm of commons led by a rare leader | If you catch the leader the herd scatters; if you catch followers first the leader flees. |
| **Escort** | Rare creature escorted by Skittish scouts | Scouts spot you and the whole group flees; approach from outside scouts' vision cone. |
| **Bait & Ambush** | Easy-looking Drifter + hidden Aggressive predators | Classic trap; scanner reveals the ambush if upgraded enough. |
| **Symbiotes** | Two creatures linked by an energy tether | Must be caught together (beam holds both) or the other one escapes and becomes enraged. |
Packs scale with chapter; guarded rewards are always worth the risk (higher modifier chance on pack catches).

### 4b. Sky Events (conditional spawns + boosted modifiers)
Events happen in a specific **zone** for a limited time (2–10 min). The **Observatory** shows where and when. During an event: special creatures spawn, some rarities spawn more often, and certain **modifiers are boosted**.
| Event | Where | Effect |
|---|---|---|
| Thunderstorm | Storm Layer | Lightning hazard; storm creatures; **Electric** modifier ×5 |
| Meteor Shower | any Ch1–2 | meteor hazard; **Molten/Blazing** ×3; meteor-rider creatures |
| Star Shower | Edge of Space+ | falling star sparkles to collect; **Starlit** ×5; luck ×1.5 in zone |
| Aurora Night | Edge of Space | calm, beautiful; Aurora creatures; **Prism** ×3 |
| Nebula Bloom | Ch2+ | colorful gas clouds lower visibility; **Nebula** modifier enabled; nebula creatures |
| Solar Flare | Ch2–3 | flare waves hazard; **Golden** ×4; heat creatures |
| Comet Pass | Ch2+ | a giant comet crosses; creatures ride its tail; Rare+ spawn ×2 |
| Eclipse | Ch2+ | world darkens; **Shadow** ×5; nocturnal creatures |
| Blood Moon | Ch2 Moon Approach | red sky; **Crimson** ×5; aggressive packs more common |
| Crystal Hail | Edge of Space / Ice Rings | ice shards hazard; **Glass/Frosted** ×4 |
| Gravity Tide | Ch3+ | gravity waves shift drone; Heavy creatures more common |
| Whale Migration | any | huge gentle sky whales cross the zone (visual spectacle), rare escorts |
| Rift Storm | rare, any | luck ×2 for 15 min, Anomaly rift chance ×3 |
| (Holiday events) | config-driven | seasonal creatures and modifiers |
Some events are server-wide schedules (everyone sees the same timer = social hype), some are random per run.

### Hazards (scale with distance) — high quality bar
Every hazard must look and sound **great**: big VFX, loud layered sound, camera shake/nudge, screen effects. Meteors passing close cause a whoosh + shockwave ring + camera shake + bass thump, even when they miss.
- **Chapter 1:** wind gusts (visible streaks + push), storm cells with **lightning** (flicker + rumble 1.5s before strike), aggressive sky predators, thin air & cold at the edge.
- **Chapter 2:** space debris fields, micrometeoroid showers, meteor showers, radiation belt (battery drain band with Geiger crackle), sweeping satellites.
- **Chapter 3:** solar flares (screen-wide wave, hide behind objects), gravity wells, ice shards, heat zones near the Sun.
- **Chapter 4:** pulsar beams (rhythmic sweeping lasers), nebula static (scanner off), starlight glare (white-out bursts).
- **Chapter 5:** sideways gravity, **inverted-control zones**, dark matter drag.
- **Chapter 6:** black hole pull, time-slow bubbles, spaghettification edges.
- **Otherworldly endgame hazards (Ch5–6 and high rifts):**
  - **Reality Tears** — cracks in space that cut across the screen; touching one teleports you randomly.
  - **Echo Drone** — a ghost copy of your drone replays your last 3 s of movement; colliding with it damages you.
  - **Void Tendrils** — reach out from the dark edges toward light (your beam attracts them).
  - **Color Drain** — the world desaturates; creatures become invisible except by sound.
  - **Collapsing Space** — the safe area shrinks from the edges; escape through the gap.
  - **Watcher Eyes** — giant eyes open in the background and fire slow beams where you were.
  - **Singing Stars** — sound-wave rings expand outward; pass through the gaps on the beat.
  - **Gravity Flip** — up becomes down for a few seconds (telegraphed by everything rotating).
- **Hazards also bring rewards:** during a hazard, rare creatures and modifiers appear more frequently (risk = reward), e.g. a meteor shower raises Molten chance and spawns meteor-riders.
- Rule: **every danger is telegraphed and readable** (warning icon, outline, sound). Pressure yes, confusion no.

### Return trip (Re-entry)
- Press **Recall** anytime → drone heads down; player steers to dodge hazards (lightning, debris, predators chasing). Descent 20–40 s; music intense if hazards present, calm if not.
- **Hull (armor) system:** hits remove hull points. At 0 hull, the **drone explodes** (big VFX) and the **emergency capsule** brings back **half the cargo** (server picks; the single rarest catch is always saved). Upgrading Armor = more hits before exploding.
- **Battery dies:** "Emergency Tow" — towed home, **tow fee** (15% of cargo value), creatures kept.
- Never lose everything.

## 5. Base (the lobby) — the player's own plot
Walkable 3D base on a hill/plateau with a view of the sky. Starts small; stations unlock as you progress.

| Station | Unlock | Purpose |
|---|---|---|
| **Launch Pad + Console** | Start | Rocket stands here. Rocket visibly upgrades (§5b). |
| **Drone Hangar** | Start | Drone upgrades (battery, speed, beam strength, beam range, cargo, scanner, armor). Drone on a stand, visibly changes. |
| **Galaxy Aquarium (Habitat)** | Start (small) | A zero-gravity starry dome. **Walk in and you float/swim through it** (custom zero-g movement) among your creatures, who roam freely. Slots in the aquarium grant boosts; creatures produce money. Click a creature for its card. Expansions make it bigger/add rooms. |
| **Storage Vault** | Start | Creatures not in the aquarium. **Limited capacity**; upgrade with coins or a gamepass. |
| **Market / Sell Terminal** | Start | Sell creatures. **High Demand board**: rotating creatures/rarities/modifiers sell for +50%…+200% for a limited time (rotates every few hours, visible countdown, so players plan when to sell). |
| **Rocket Workshop** | After first run | Rocket upgrades (engine, fuel, heat shield, gravity shield, propulsion tech per chapter) and **Rocket Skins**. |
| **Collection Book** | After first catch | Every creature, silhouettes for unknown, stages and modifiers seen, lore line, completion rewards per zone/chapter. |
| **Evolution Lab** | Ch1 mid | **Stage Evolution** and **Fusion** (§6). Both take time; Evolution Potion speeds them up. |
| **Observatory Telescope** | Ch1 late | Telescope camera view of the sky/space map: **shows which zone currently has an active event**, upcoming events with timers, today's rare spawn, "rare creature sighted" hints. |
| **Modifier Infuser** | Ch1 late | Coin upgrade: raises modifier chance. Glows with colors of modifiers you've found. |
| **Luck Reactor** | Ch1 late | Coin upgrade: +5% luck per level. Grows with level. Shows current luck ×. |
| **Achievement Board** | Start | Milestones with rewards (§12b). |
| **Research Station** | Ch2 | Research tree of permanent upgrades that take real time (§6b). |
| **Potion Brewery** | Ch2 | Brew potions from coins + creature essence (§11b) with brew timers. |
| **Rift Shrine / Odds Board** | Ch1 late | Rift ladder with base & effective odds, rift creatures caught. |
| **Skin Bay** | Ch1 mid | Equip/preview drone & rocket skins (§5b). |
| **Shop Kiosk** | Start | Gamepasses & products (also from HUD). |
| **Leaderboards & Daily Rewards** | Start | Boards at spawn, daily reward chest. |
| **Quest NPCs** | via expansions | NPC characters who give quests (§12c). |
| **Base Expansion** | Ongoing | Buy new land/rooms/interiors: bigger aquarium, more storage, new stations, decor, NPC houses. Opening a new area = reward moment. |

Base must feel alive: creatures floating in the aquarium, rocket steam, blinking lights, ambient sounds, day/night cycle.

### 5b. Rocket & drone visuals, skins
- **Rocket upgrades are visible:** more engines/boosters, bigger exhausts and flames, fins, stripes, lights, size; each propulsion tech is a new tier model (scrappy → clean → orbital boosters → ion ship → warp vessel → jump ship → singularity craft).
- **Skins (rocket + drone):** bought with coins (some), Robux (premium), unlocked by achievements/events (exclusive).
- **Skins have cosmetic effects:** custom beam effect (color/shape/particles), thruster/steering trail, capture animation, launch flame and smoke color, catch sound accent. **Cosmetic only** (no stat bonuses) to stay fair; maybe a tiny QoL like a unique trail.

## 6. Creatures: income, boosts, evolution, fusion
- Every creature has **Rarity**, **Zone**, **Behavior**, **Value**, **Income/sec**, **Boost** (family + strength), optional **Modifier** and **Size**.
- **Income:** every owned creature earns coins/sec **online and offline**; creatures placed in **aquarium boost slots** earn ×2 and give their **boost**.
- **Boost families** (what they mean): each creature's boost belongs to one family, and putting it in a boost slot applies that bonus to you:
  | Family | What it does | Examples |
  |---|---|---|
  | Money | earn more | +% income, +% sell price, bigger High Demand bonus |
  | Protection | survive longer in flight | +hull, ignore 1 lightning per run, battery back on catch |
  | Speed | do things faster | −% launch cooldown, +drone speed, faster ascent |
  | Time | wait less | +offline cap, −% research/evolution/brew time |
  | Luck | find rarer things | +% luck, +scanner range, +% modifier chance |
- **Boost slots** are limited (2 → 10 via expansion/gamepass) → choosing = loadout decision.
- **Stage Evolution** (same creature): Stage 1 → 2 → 3 (later 4). Costs duplicates of the same creature (3 for stage 2, 5 for stage 3) + coins + **time** (5 min → hours). Each stage: bigger, more detail/glow, new aura, stronger boost (×1.5 / ×2.5) and income. Modifiers are kept (highest one).
- **Fusion** (many → one): put **up to 10 creatures of the same rarity** into the Fusion Chamber → produces **one creature of the next rarity** (random species from the chapters you've reached), with a **guaranteed modifier** and value higher than the inputs combined. More inputs (5–10) = better odds of rare modifiers / bigger size. Takes time; animated fusion machine. Gives use to piles of commons.
- **Combos (later, Stage 12/future):** specific creature sets in boost slots give bonus effects (e.g. 3 Storm creatures → "Storm Season"). Kept in design, built later.

### 6b. Research Station (what it does)
A **tech tree of permanent upgrades** that cost coins and take **real time** to complete (continues offline). One research at a time (second slot via expansion). Examples:
| Branch | Researches |
|---|---|
| Drone Tech | Efficient Cells (+10% battery), Reinforced Hull (+1 hull), Wide Beam (+10% beam angle), Deep Scanner (reveal Hidden from further) |
| Economy | Market Contacts (+10% sell price), Long-term Storage (+1 h offline cap), Auto-Sorter (auto-sell chosen rarities), Compound Interest (+5% income) |
| Exploration | Event Forecast (see events 30 min earlier), Weather Radar (events show on altimeter), Rift Theory I–III (+5% rift odds each) |
| Lab | Quick Evolve (−15% evolve time), Stable Fusion (better fusion modifier odds), Brewing Mastery (−20% brew time) |
Durations: 10 min early → 8–24 h late. Research Potion halves remaining time.

## 7. Progression structure
- **Chapters** (each = new world, new propulsion tech): 1 Earth (Chemical Rocket) · 2 Near Space (Orbital Booster) · 3 Solar System (Ion Drive) · 4 Deep Space (Warp Drive) · 5 Another Galaxy (Jump Drive) · 6 Black Hole (Singularity Drive).
- Each chapter: 3 zones, ~8–12 creatures, unique hazards/events, unique sky, unique music set, new rarities.
- **Initial release:** Chapters 1 and 2 fully polished; 3–6 added later as content.
- Milestone moments: first catch, first Rare, first Perfect Launch, reaching space, new propulsion tech cinematic.

## 8. Mood / intensity system (central system)
States: **Calm → Tension → Danger** (+ **Triumph** stinger for big catches).
| Trigger | State |
|---|---|
| Normal flight / base | Calm |
| Storm forming, predator/pack nearby, battery <25%, cargo full + hazards, rare creature call heard | Tension |
| Lightning imminent, being chased, taking damage, hull 1, battery <10%, black hole pull | Danger |
| Legendary+ catch, new chapter | Triumph (overrides 3–5 s) |
Effects: music layer crossfade, ColorCorrection, vignette, camera shake, FOV tighten, heartbeat/alarm, red edge flashes in Danger. Smooth transitions with hysteresis.

## 9. Rift Ladder (rare RNG events) — **all 2.5D**
Rolled once per launch on the server during ascent. Highest tier rolled wins. Odds ÷ total Luck (§10). More tiers can be added later.

**Rifts stay 2.5D** (user decision): same side-view flight, but the screen becomes a **"DRONE FEED"** — you've lost normal contact and see the drone's own camera: scanlines, signal noise, glitch, timestamp, distorted HUD. Each rift is a special 2.5D zone with its own visuals, creatures and hazards (60–120 s).

| Tier | Name (working) | Base odds | Entrance |
|---|---|---|---|
| R1 | Anomaly | 1 / 500 | screen effect: glitch flicker, color shift |
| R2 | Flicker Rift | 1 / 2,500 | screen effect: strobing light, static |
| R3 | Static Rift | 1 / 10,000 | screen effect: signal lost → drone feed reconnects |
| R4 | Echo Rift | 1 / 50,000 | screen effect: screen tears, echoed sounds |
| R5 | Mirage Rift | 1 / 250,000 | screen effect: world melts/waves, colors invert |
| R6 | Prism Rift | 1 / 1,000,000 | **short cinematic**: world shatters into rainbow shards, drone mirror copies |
| R7 | Abyssal Rift | 1 / 10,000,000 | **cinematic**: darkness pulses, giant eyes open, heartbeat |
| R8 | Hollow Rift | 1 / 100,000,000 | **cinematic**: everything turns to outlines, gravity stops, whispers |
| R9 | **Null Rift** | 1 / 1,000,000,000 | **full cinematic** (below) |

- Normal rifts (R1–R5) use **screen effects** only; rarest (R6–R9) get **cinematics**.
- **Null Rift cinematic:** all audio cuts → screen black ~2 s ("did it crash?") → single heartbeat → drone breaks apart piece by piece, reassembles in a new form → creatures crawl in from the screen edges → camera pulls back to reveal a **colossal** creature → slow text "YOU HAVE ENTERED THE NULL". **Global announcement** to all servers.
- Each rift has exclusive creatures of its own rarity (Anomalous, Flickering, Static, Echo, Mirage, Prismatic, Abyssal, Hollow, **Null**).
- Too many hits → ejected early, keep everything caught.
- Announcements: R3+ server banner; R6+ global banner + "Rarest Finds" leaderboard.
- Rift entry can trigger on any chapter (farmed low chapters stay exciting).

## 10. Luck system
- **Luck multiplier** (e.g. "Luck ×2.35"): effective odds = baseOdds / luck. Also gently raises rare creature spawn weights.
- **Free sources:** Luck Reactor (+5%/level), luck-family creatures, research (Rift Theory), events (Rift Storm, Star Shower), achievements, daily streak, group reward.
- **Paid sources:** Lucky Drone gamepasses, Luck Potions, Server Luck.
- Stacking: additive within a category, multiplicative across categories. **Hard cap** (e.g. ×50) — math designed and simulated in the balance stage so numbers feel good but rifts stay special.
- All rolls server-side.

## 11. Monetization — fair and good value
Goal: earn Robux while keeping the game fair for free players. **No absurd passes** (e.g. no "+1000 luck for 5000 Robux"). Few passes, each clearly worth it; prices sensible and confirmed with the user.

**Gamepasses (one-time):** Lucky Drone (+50% luck) · Super Lucky Drone (+100% luck) · 2× Coins · VIP (tag, decor, +10% coins, trail) · Extra Boost Slots (+3) · Bigger Storage · Auto-Collect · Fast Launch (−50% cooldown) · Bigger Cargo (+3).

**Developer products (repeatable):** Luck Potion I/II · Modifier Potion · Evolution Potion · Research Potion · Speed Potion · Server Luck (buyer announced) · Coin Packs (progress-scaled) · Instant Recharge · Premium skins.

**Rules:** idempotent ProcessReceipt with receipt dedupe; odds always displayed; respect PolicyService paid-random-item restrictions; honest shop UI; free path reaches everything (paid = faster/luckier/cosmetic).

### 11b. Potions (earned AND purchasable)
| Potion | Effect | Duration |
|---|---|---|
| Luck I / II | +100% / +1000% luck | 60 / 10 min |
| Modifier | ×2 modifier chance | 30 min |
| Speed | +30% drone speed & ascent | 30 min |
| Battery | +50% battery | 5 runs |
| Magnet | +40% beam range | 20 min |
| Coin | ×2 coins | 30 min |
| Evolution | instantly finish / −50% evolution & fusion time | one use |
| Research | halve remaining research time | one use |
Sources: Potion Brewery (coins + creature essence from selling/fusing), achievements, quests, daily rewards, events, shop. Active potions shown in HUD with timers. Same-type potions stack duration, not strength (prevents abuse).

## 12. Retention
- **Daily login rewards** (7-day streak; day 7 = Luck Potion).
- **Daily/Weekly missions** → coins, potions.
- **Leaderboards:** Richest, Highest Altitude, Rarest Find, Most Rifts, Collection %.
- **Group reward** (+5% luck), **Codes**.
- **Rebirth / "Re-launch Program"** — future.
- **Holiday events** via config.

### 12b. Achievement Board
Milestone tracks with tiered rewards (coins, potions, skins, titles, boost slots):
- Rocket: reach Engine level 1/5/10/20 · unlock each propulsion tech.
- Collection: catch 10/100/1,000/10,000 creatures · complete each zone's book page · find every modifier.
- Rarity: first Rare/Epic/Legendary/Mythic/… · first Secret.
- Rifts: enter each rift tier → huge rewards scaling with rarity; **entering the Null Rift = the biggest reward in the game** (massive coins, rare potions, exclusive skin + title "Null Walker").
- Skill: 10/100 Perfect Launches · survive a meteor shower without hits · catch a Guarded Giant.
- Economy: earn 1K/1M/1B coins · sell during High Demand.

### 12c. Quest NPCs
NPCs move into the base as you buy expansions; each has a personality, a small house/stand and rotating quests:
- e.g. *the Collector*: "Bring me 5 Glossy creatures (any kind)" → reward.
- *the Engineer*: "Survive 3 storms" → rocket skin piece.
- *the Astronomer*: "Catch a creature during an Aurora Night" → Luck Potion.
- *the Merchant*: "Sell 10 creatures during High Demand" → coin bonus.
Quests rotate daily; quest chains unlock lore and exclusive items.

## 13. Atmosphere & ambience — essential, not optional
Without good sound and atmosphere the game feels bland, so this is a core feature:
- **Living sky soundscape:** distant growls, roars, creaks, whale-like calls, wind and space hum, panned left/right by where the source is.
- **Rare creature calls:** when a rare+ creature spawns in your zone, it makes a **distinctive sound** (unique per rarity tier/creature) and an on-screen direction hint after a moment → players hunt for it. Tension rises.
- **Giant silhouettes** swim far behind clouds/planets; **meteors** whoosh past with shockwaves.
- Every hazard and catch tier has layered, punchy sound.
- Details of audio sourcing (incl. AI tools) in `03_ART_AND_AUDIO.md` §5.

## 14. Onboarding
First 5 minutes guided: walk to launch console → launch (mini-game explained) → catch 3 commons (beam tutorial) → recall → sell one, put one in the Galaxy Aquarium → buy first drone upgrade. Short text, no walls of tutorial.

## 15. Platforms & controls
- **PC:** WASD/arrows move, mouse aims beam, LMB/Space hold to beam, R recall, Tab scanner pulse.
- **Mobile:** virtual thumbstick, beam button with auto-aim, recall button.
- **Gamepad:** left stick move, right stick aim, RT beam, B recall.
- Aquarium zero-g swim: WASD + Space/Ctrl (up/down), mobile thumbstick + up/down buttons.
- UI scales for phone/tablet/desktop; test with Device Simulator.

## 16. Out of scope (for now)
- Multiplayer competitive mode (possible future separate mode).
- Trading between players.
- Full 3D flight anywhere (rejected: too big; rifts also stay 2.5D).

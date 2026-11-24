# 02 — Content: Chapters, Zones, Creatures, Upgrades, Economy

All names are original working names; can be renamed with the user. Numbers are starting points — balance in Stage 9.

## 1. Rarities (full ladder, user-approved 2026-11-24)
Rarities unlock gradually: each chapter introduces 2–4 new top rarities, so there is always a new "highest" to chase. The rift rarities sit above everything, and **Null** is the highest in the game.

| # | Rarity | First appears | Color / look | Resistance @ beam 1 | Value mult | Celebration tier (see §1b) |
|---|---|---|---|---|---|---|
| 1 | Common | Ch1 | soft grey-white | 0.3s | ×1 | T0 |
| 2 | Uncommon | Ch1 | green | 0.8s | ×3 | T1 |
| 3 | Rare | Ch1 | blue | 2s, struggles | ×10 | T2 |
| 4 | Epic | Ch1 | purple | 3.5s | ×35 | T3 |
| 5 | Legendary | Ch1 | gold | 5s, may break free | ×150 | T4 |
| 6 | Mythic | Ch2 | red-pink | 6s, fights back | ×600 | T5 |
| 7 | Celestial | Ch2 | pale cyan + light rays | 7s | ×2,000 | T5 |
| 8 | Cosmic | Ch3 | deep blue starfield gradient | 8s | ×6,000 | T6 |
| 9 | Astral | Ch3 | silver-lilac shimmer | 8.5s | ×15,000 | T6 |
| 10 | Galactic | Ch4 | spiral purple-pink gradient | 9s | ×40,000 | T6 |
| 11 | Supernova | Ch4 | white-orange exploding glow | 9.5s | ×100k | T7 |
| 12 | Eclipse | Ch4 | black disc with gold corona | 10s | ×250k | T7 |
| 13 | Quantum | Ch5 | flickering teal, duplicates | 10.5s | ×600k | T7 |
| 14 | Interdimensional | Ch5 | shifting multi-color portal edge | 11s | ×1.5M | T8 |
| 15 | Singularity | Ch6 | black core, bending light | 12s | ×4M | T8 |
| 16 | Void | Ch6 | pure black with violet edge | 12.5s | ×10M | T8 |
| 17 | Transcendent | Ch6 (very rare) | white-gold, angelic glow | 13s | ×30M | T9 |
| 18 | Apex | Ch6 (ultra rare) | animated rainbow crown | 14s | ×100M | T9 |
| 19 | **Secret** | any chapter, 1 secret creature each, hidden conditions | glitching "???" until caught | 15s | ×250M | T9 + server announce |
| — | *Rift rarities* | | | | | |
| R1 | Anomalous | Anomaly rift (1/500) | glitch static | 5s | ×3,000 | T5 |
| R2 | Flickering | Flicker rift (1/2.5k) | strobing light | 6s | ×12k | T6 |
| R3 | Static | Static rift (1/10k) | TV-noise body | 7s | ×50k | T6 |
| R4 | Echo | Echo rift (1/50k) | doubled ghost outline | 8s | ×250k | T7 |
| R5 | Mirage | Mirage rift (1/250k) | wavy heat-haze, inverted colors | 9s | ×1M | T7 |
| R6 | Prismatic | Prism rift (1/1M) | refracting rainbow | 10s | ×5M | T8 |
| R7 | Abyssal | Abyssal rift (1/10M) | deep dark w/ glowing lures | 12s | ×50M | T9 |
| R8 | Hollow | Hollow rift (1/100M) | outline-only, transparent | 13s | ×300M | T9 |
| R9 | **Null** | Null rift (1/1B) | absence of color, inverted outline | 15s | ×2B | **T10 (highest)** |

Value multipliers are placeholders; balance them in the balance stage together with the zone base values. Rarity colors/gradients live in `Config/Rarities`; animated gradients use `UIGradient` rotation in UI and `Highlight`/particles in-world.

### 1b. Catch celebration tiers (escalating)
| Tier | Rarities | In-world effect | UI | Sound |
|---|---|---|---|---|
| T0 | Common | quick spiral-in, small pop | small toast | soft pop |
| T1 | Uncommon | pop + sparkles | toast with color | brighter pop |
| T2 | Rare | ring burst, light flash on drone | toast + rarity chip | chime |
| T3 | Epic | burst + screen-edge purple glow, short camera punch | **Catch Card** (3D creature in ViewportFrame spinning, name, rarity, modifier, size) slides in | epic stinger |
| T4 | Legendary | slow-mo 0.4s, golden light rays, flash | Catch Card w/ shine sweep | fanfare |
| T5 | Mythic, Celestial | slow-mo, color-grade shift, particle storm | big Catch Card, server chat message | big fanfare + choir hit |
| T6 | Cosmic, Astral, Galactic, Anomalous | camera orbit around catch, screen warp | fullscreen card, **server banner** | unique sting per rarity |
| T7 | Supernova, Eclipse, Quantum, Echo | screen fade to rarity color, creature reveal shot | fullscreen card, server banner | unique sting |
| T8 | Interdimensional, Singularity, Void, Prismatic | music cuts, world dims, creature reveal cinematic | fullscreen + **global banner** | unique sting + silence beat |
| T9 | Transcendent, Apex, Secret, Abyssal | multi-second cinematic, shockwave, everything else freezes | global banner + leaderboard entry | signature theme |
| T10 | Null | full Null cinematic (see design §9) | global banner, permanent "Null Finder" title | silence → heartbeat → swell |

**Catch animation (all tiers):** creature struggles in beam → gets pulled in a spiral along the beam, squash & stretch → swallowed by drone's intake with a flash → drone bounces slightly → cargo slot icon fills with a pop. Never a flat slide.

### 1c. Modifiers / Enchantments (working name: "Modifiers")
Rolled server-side on every catch. A creature normally has 0 or 1 modifier; a **double modifier** is an ultra-rare roll (1/50 of modified catches, later chapters only). Modifiers multiply value and income and change how the creature looks (material, color, particles, aura) both in flight and on the base.

Base chance any modifier: **1 in 25** (raised by Modifier upgrades, creatures, potions; capped). Then weighted pick:
| Modifier | Weight | Value × | Look |
|---|---|---|---|
| Glossy | 30 | ×1.5 | polished sheen |
| Frosted | 20 | ×2 | icy blue tint, frost particles |
| Blazing | 15 | ×2.5 | fire particles, orange glow |
| Electric | 12 | ×3 | crackling sparks |
| Glass | 8 | ×4 | transparent glass body, refraction |
| Molten | 6 | ×5 | lava cracks, ember trail |
| Crimson | 4 | ×6 | deep red tint, red mist |
| Golden | 2.5 | ×8 | gold material, sparkle |
| Starlit | 1.5 | ×10 | starfield texture inside body |
| Shadow | 0.6 | ×15 | black silhouette, purple outline |
| Prism | 0.3 | ×25 | rainbow shifting color |
| Nebula | 0.08 | ×50 | swirling nebula body (space chapters only) |
| Glitched | rift-only | ×100 | glitch flicker (Anomaly+ rifts only) |
| Null-touched | Null rift only | ×1000 | inverted colors, void aura |
- Modifiers stack with evolution and rarity multipliers.
- Collection Book tracks modifiers seen per creature (bonus rewards for collecting all modifiers of a creature).
- Shown on the Catch Card as a colored tag ("BLAZING Storm Hound").
- Replaces the old "Shiny" idea (Golden/Prism fill that role).

### 1d. Size roll (optional, adds variety)
Each catch rolls a size: Tiny (×0.8) · Normal (×1) · Big (×1.3) · Huge (×1.8, 1/50) · Colossal (×3, 1/1000). Affects model scale on base and value. Decide in Stage 6 whether to include.

## 2. Chapters & zones
Display altitude ranges are virtual (see architecture §4).

### Chapter 1 — Earth (Chemical Rocket)
| Zone | Display alt. | Look | Hazards |
|---|---|---|---|
| 1.1 Low Sky | 0–10 km | Bright blue, cumulus clouds, birds far away, sun glare | wind gusts |
| 1.2 Storm Layer | 10–25 km | Dark grey-blue, anvil clouds, rain streaks, lightning flashes | lightning strikes, turbulence |
| 1.3 Edge of Space | 25–100 km | Deep blue → near black, Earth curvature + thin blue atmosphere band, first stars, aurora | thin air (slower drone), cold (battery drain) |

### Chapter 2 — Near Space (Orbital Booster)
| Zone | Display alt. | Look | Hazards |
|---|---|---|---|
| 2.1 Low Orbit | 100–2,000 km | Black sky, big Earth below with cloud swirls, satellites, space station silhouette | debris fields, sweeping satellites |
| 2.2 Moon Approach | 2k–380k km | Moon large in view, craters, dust | micrometeoroid showers, radiation belt (battery drain band) |
| 2.3 Asteroid Belt (stylized) | — | Rocks of many sizes, dust glow | asteroid collisions, gravity of large rocks |

### Chapter 3 — Solar System (Ion Drive)
3.1 Gas Giant Storms (orange/brown bands, huge storm eye) · 3.2 Ice Rings (glittering ring plane, ice shards) · 3.3 Solar Corona (near Sun, heat zones, solar flares).

### Chapter 4 — Deep Space (Warp Drive)
4.1 Nebula (colorful gas clouds, low visibility) · 4.2 Star Cluster (bright stars, starlight glare) · 4.3 Pulsar Field (rhythmic beams sweeping — timing hazard).

### Chapter 5 — Another Galaxy (Galactic Jump Drive)
5.1 Galactic Arm (alien star colors) · 5.2 Dark Matter Drift (sideways gravity) · 5.3 Galactic Core (dense light, inverted-control pockets).

### Chapter 6 — Black Hole (Singularity Drive)
6.1 Accretion Disk (bright orange swirling ring) · 6.2 Photon Sphere (light bends, mirrored creatures) · 6.3 Event Horizon (pull toward center, time-slow bubbles, Cosmic creatures).

## 3. Creature roster

### Chapter 1 — Earth (12)
| Id | Name | Zone | Rarity | Behavior | Boost |
|---|---|---|---|---|---|
| CloudPuff | Cloud Puff | 1.1 | Common | Drifter | Money +2% income |
| BreezeFin | Breeze Fin | 1.1 | Common | Swarm | Speed +2% drone speed |
| SkySkipper | Sky Skipper | 1.1 | Uncommon | Skittish | Speed −3% launch cooldown |
| DewWing | Dew Wing | 1.1 | Uncommon | Drifter | Time +5% offline cap |
| HaloGlider | Halo Glider | 1.1 | Rare | Skittish | Luck +2% rare chance |
| StaticMote | Static Mote | 1.2 | Common | Swarm | Protection +3% armor |
| ThunderEel | Thunder Eel | 1.2 | Uncommon | Phaser | Protection: battery +1% on catch |
| RainRay | Rain Ray | 1.2 | Rare | Conditional (storm) | Money +5% sell price |
| StormHound | Storm Hound | 1.2 | Epic | Aggressive | Protection: ignore 1 lightning strike / run |
| AuroraWisp | Aurora Wisp | 1.3 | Rare | Hidden | Luck +5% scanner range |
| FrostDrifter | Frost Drifter | 1.3 | Epic | Heavy | Time −5% evolution time |
| Skyhorn | Skyhorn | 1.3 | Legendary | Phaser + struggle | Money +10% income |

### Chapter 2 — Near Space (11)
| Id | Name | Zone | Rarity | Behavior | Boost |
|---|---|---|---|---|---|
| OrbitMite | Orbit Mite | 2.1 | Common | Swarm | Money +3% income |
| SolarLeaf | Solar Leaf | 2.1 | Uncommon | Drifter | Protection: battery regen in sunlight |
| SatCrab | Sat Crab | 2.1 | Rare | Skittish (hides on debris) | Speed +5% ascent speed |
| CraterMoth | Crater Moth | 2.2 | Common | Drifter | Luck +2% creatures per zone |
| LunarJelly | Lunar Jelly | 2.2 | Uncommon | Drifter (glows) | Time +8% offline cap |
| DustSerpent | Dust Serpent | 2.2 | Epic | Aggressive | Protection +8% armor |
| GravityPearl | Gravity Pearl | 2.2 | Legendary | Heavy | Luck +6% rare chance |
| RockNibbler | Rock Nibbler | 2.3 | Common | Swarm | Money +4% sell price |
| CometFox | Comet Fox | 2.3 | Rare | Skittish, fast | Speed +6% drone speed |
| BeltWarden | Belt Warden | 2.3 | Epic | Heavy | Time −8% research time |
| VoidOrca | Void Orca | 2.3 | Mythic | Aggressive + fights back | Money +20% income |

### Chapters 3–6 (concept list; fill details when built)
- Ch3: Banded Whale, Storm Eye Sprite, Ring Skater, Ice Shard Swarm, Corona Phoenix (Legendary), Flare Serpent, Helios Moth, Sunspot (Mythic).
- Ch4: Nebula Drifter, Prism Ray, Star Shepherd, Cluster Bees, Pulsar Stag (Legendary), Warp Hare, Quasar Leviathan (Mythic).
- Ch5: Arm Glider, Dark Matter Shade (Hidden), Gravity Kite, Core Titan (Legendary), Twin Star Serpents, Galaxy Weaver (Mythic).
- Ch6: Disk Salamander, Photon Mirror (mirrored), Horizon Wraith, Time Moth (slows time), Singularity Spawn (Cosmic), Event Leviathan (Cosmic).

### Creature model rules
- Each creature: unique silhouette readable at flight distance, rarity-color accent + glow, idle animation (bob, flap, swim — via code-driven CFrame/TweenService or AnimationController), 3 evolution stages that clearly escalate (size + parts + particles + light).
- Built from well-made Parts/MeshParts (rounded, smooth, layered materials: Neon accents, SmoothPlastic/Glass bodies) or generated via `generate_mesh`/`generate_procedural_model` then refined. Must look intentional and cohesive — one art style across the roster.

### Rift creatures (exclusive, 2.5D, unique behaviors)
| Rift | Creatures (working names) | Notes |
|---|---|---|
| R1 Anomaly | Glitch Moth, Static Kitten, Flicker Fish | glitchy flicker |
| R2 Flicker | Strobe Ray, Blink Sprite | only visible on light pulses |
| R3 Static | Noise Eel, Snow Crab | hidden in TV-static clouds |
| R4 Echo | Echo Manta, Reverb Wisp, Mirror Bat | appear twice (echo copy), catch the real one |
| R5 Mirage | Haze Serpent, Oasis Jelly | fake copies that dissolve when beamed |
| R6 Prism | Prism Stag, Refraction Serpent, Shard Swarm | split into light copies; color-matching beam |
| R7 Abyssal | Abyss Angler, Hollow Eye, Deep Leviathan (colossal) | emerge from darkness, lure light |
| R8 Hollow | Outline Wraith, Empty Whale | only outlines; found by sound |
| R9 Null | Null Wanderer, Nothing Moth, **The Unmade** (colossal centerpiece) | ultimate trophy |
Rift creature boosts are the strongest in the game (e.g. Null: ×2 income + ×1.25 luck) and get a special pedestal in the habitat.

### Fusion (Evolution Lab)
| Inputs (same rarity) | Result | Bonus |
|---|---|---|
| 3 | 1 creature of next rarity | guaranteed Glossy+ modifier |
| 5 | same | modifier pool shifted up 1 step, +10% value |
| 10 | same | modifier pool shifted up 3 steps, Big+ size guaranteed, +30% value |
Time: 2 min (Common) → hours (high rarities). Fusion cannot produce Secret or rift rarities.

### Storage
Cap 50 → 500 via coin upgrades (`300 × 1.4^(level-1)`), +100 from the Bigger Storage gamepass.

### Modifier Infuser (base upgrade)
| Level | Effect | Cost |
|---|---|---|
| 1–40 | +4% modifier chance per level (multiplicative on base 1/25, max ×2.6) | `800 × 1.5^(level-1)` coins |
Other sources: modifier-family creature boosts, **Modifier Potion** (dev product, ×2 modifier chance 30 min), events ("Molten Hour"). Total modifier chance capped (e.g. 1 in 4).

### Luck Reactor (base upgrade)
| Level | Luck bonus | Cost |
|---|---|---|
| 1–50 | +5% per level (max +250%) | `500 × 1.45^(level-1)` coins |
Luck cap total ×50 (initial; tune).

## 4. Upgrades

### Drone (Hangar) — levels 1–25 each (caps raise per chapter)
| Stat | Lvl 1 | Per level | Notes |
|---|---|---|---|
| Battery | 90 s | +6 s | drain ×1.6 while beaming (Stage 1: demo ≈ 95 s) |
| Speed | 43 studs/s | +2.5% | (demo 430 units/s at 0.1 studs/unit) |
| Beam Strength | 1.0 | +8% | pull speed |
| Beam Range | 23 studs | +1.2 studs | (demo 230 units) |
| Cargo | 5 slots | +1 slot | |
| Scanner | 60 studs | +6 studs | reveals Hidden |
| Armor | 1 hit | +1 hit every 3 lvls | |
Cost: `base * 1.35^(level-1)`; base differs per stat (Battery 50, Speed 60, Beam 80, Range 70, Cargo 100, Scanner 90, Armor 120).

### Rocket (Workshop)
| Upgrade | Effect |
|---|---|
| Engine (1–30) | max altitude within the current tech's chapter (each level opens more of the zones) |
| Fuel (1–10) | ascent stability (fewer debris hits) + bigger Perfect window |
| Heat Shield (1–10) | required for Ch3 corona & re-entry damage reduction |
| Gravity Shield (1–10) | Ch5–6 pull resistance |
| **Propulsion Tech** | Chapter gate: Orbital Booster (Ch2), Ion Drive (Ch3), Warp Drive (Ch4), Jump Drive (Ch5), Singularity Drive (Ch6). Requires: engine maxed for current tech + coins + collection % of current chapter (e.g. 60%). Unlock = cinematic + rocket model jumps tier. |

Rocket visual tiers: T1 scrappy welded rocket → T2 clean white rocket → T3 orbital booster with side boosters → T4 ion ship (glowing blue engines) → T5 warp vessel (ring) → T6 jump ship → T7 singularity craft. Engine levels add visible details within a tier (fins, stripes, lights).

### Base
- Habitat slots: 2 → 10 (expansions).
- Storage cap: 50 → 500.
- Expansions: East Wing (Evolution Lab), Observatory Hill, Research Wing, Grand Habitat, Decor Garden.
- Launch cooldown: 20 s base (mostly to pace; reduced by boosts).

### Research (Chapter 2+), examples
Efficient Cells (+10% battery), Better Lenses (+10% scanner), Market Contacts (+10% sell), Long-term Storage (+1 h offline cap), Auto-Sorter (auto-sell commons option), Quick Evolve (−15% evolve time). Durations 10 min → 8 h.

## 5. Economy numbers (starting)
- Creature base values (Ch1 common): 10 coins. Value = `zoneBase × rarityMult × stageMult(1, 2.5, 6)`. Zone base: 1.1=10, 1.2=25, 1.3=60, 2.1=150, 2.2=400, 2.3=1000 (≈×2.5 per zone).
- Income/sec while owned: `value / 600` (in habitat ×2).
- Offline: 50% rate, cap 2 h (boostable).
- Tow fee: 15% of cargo value.
- Target pacing: Ch1 complete (tech to Ch2) in ~45–75 min; Ch2 in ~2–3 h. Later chapters longer.
- Number formatting: 1.2K, 3.4M, 5.6B, 7.8T, then aa/ab style.

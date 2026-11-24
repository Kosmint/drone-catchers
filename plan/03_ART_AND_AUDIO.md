# 03 — Art, VFX, UI & Audio Direction

## 1. Overall visual style
- **Stylized low-poly, smooth and appealing** — *inspired by* the look of Astroneer (user's reference screenshot, 2026-11-24): faceted low-poly shapes with soft flat shading, **warm pastel gradient skies** (peach, coral, lavender, mint, teal), painterly layered clouds, chunky rounded tech, small cheerful details, strong silhouettes, high color harmony. **Style inspiration only — no copied assets, characters or logos.**
- Not cute-baby, not eerie: friendly, wondrous, clean. Natural sky progression (blue day sky → sunset-pastel high sky → deep violet/teal space) rendered in that stylized palette.
- Implementation in Roblox: low-poly MeshParts/Parts with `SmoothPlastic`/flat materials (avoid noisy realistic textures), color gradients via vertex-colored meshes / `SurfaceAppearance` color maps / layered transparent parts, `Atmosphere` for haze, Neon only for energy accents. Generated meshes (`generate_mesh`, `generate_procedural_model`, `generate_texture`) must be prompted for "stylized low-poly, soft flat shading, pastel" and refined to match.
- Creatures: rounded, faceted, readable silhouettes, glowing accents in rarity colors, gentle idle motion. Planets: big faceted spheres with banded pastel colors, low-poly craters/rings.
- Lighting: `Future` technology, `Atmosphere` heavily used, `Bloom` subtle, `SunRays` in Earth zones, `ColorCorrection` per zone, `DepthOfField` on base camera.
- One consistent material language: smooth surfaces, metal + glass for tech, Neon for energy (beam, engines, creature accents), never random colors.
- **Quality bar check (every visual gate):** take `screen_capture` of the scene, honestly judge: Would this look good as a Roblox game thumbnail? If not → iterate before showing the user.

## 1b. Lessons from the browser demo (user feedback 2026-11-24)
The 2D demo (https://claude.ai/artifact/L686j8cTiyJqbvFYGpZy5U) **movement and gameplay are approved**. Its visuals are explicitly NOT the target:
- **Planets** (the ringed planet) looked "AI-ish" → in Roblox: real 3D low-poly planet models with hand-tuned facet colors, soft atmosphere rim glow (Highlight/transparent shell), proper ring with shadow and particles, slow rotation.
- **Earth at Edge of Space** was flat color stripes → in Roblox: a large 3D low-poly Earth with continents, oceans, cloud layer (separate slightly larger rotating mesh), atmospheric glow shell, city lights on the night side; seen at a curve below the drone.
- **Clouds, creatures, drone** looked blocky/flat → smooth faceted 3D models with soft lighting, not 2D polygons.
- **Rocket launch** liked → must be 3D rocket filmed from the side (3D in a 2D perspective), with real smoke volumes, light from the flame, pad shaking.
- **Base** looked bad → fully modeled 3D base (Stage 5 quality bar is high).
- **Catch** felt like a "slide into inventory" → replaced by spiral pull + intake + rarity celebration tiers (`02_CONTENT.md` §1b) + Catch Card UI.
- Kept from the demo: drone weight/drift/tilt, camera lead, parallax depth layers, telegraphed meteor lines, red/amber mood vignette, zone "ENTERING" banner, altimeter with zone bands and engine-limit line.

## 2. Zone visual presets (lerped in flight)
| Zone | Sky / Atmosphere | ColorCorrection | Parallax layers | Particles |
|---|---|---|---|---|
| 1.1 Low Sky | soft pastel blue → peach near horizon, sun high, haze low | warm, sat +0.1 | distant mountains/horizon, big cumulus, mid clouds | soft cloud wisps, occasional birds far |
| 1.2 Storm | dark slate, dense haze | cool, contrast +0.15, sat −0.2 | dark anvil clouds, rain curtains | rain streaks, lightning flash lights |
| 1.3 Edge | deep blue→black gradient, thin blue horizon band | cool, slight purple | Earth curve, aurora ribbons, stars | cold sparkles |
| 2.1 Orbit | black, starfield | neutral, contrast up | big Earth, satellites, station | small debris specks |
| 2.2 Moon | black | slightly desaturated | big Moon, crater detail | dust |
| 2.3 Belt | black w/ dust glow | warm dust tint | layered asteroids | rock dust, tiny pebbles |
(Ch3–6 presets defined when built.)

## 3. Key VFX list
- Rocket: ignition smoke (big rolling), flame (Beam + particles + light), launch pad steam, shockwave ring, booster separation, contrails.
- Drone: thrusters reacting to movement, idle hover, damage sparks, low battery blinking, deploy animation.
- **Suction beam**: cone of light (Beams + particles flowing toward drone), color tinted by target's rarity, intensity grows with pull progress; creature stretches toward drone, struggle jerks.
- Catch: spiral pull + squash/stretch + intake flash, then the rarity **celebration tier** T0–T10 (`02_CONTENT.md` §1b). Each high rarity (T6+) gets its **own** look and sting, not a recolor.
- Modifier visuals: each modifier = a reusable preset (material/color override, particle emitter, light, aura) applied to any creature model, in flight and on base.
- Hazards: lightning (telegraph flicker → bolt Beam + flash + thunder), debris trails, solar flare wave, gravity well distortion (rings), black hole lensing (sky warp via rotating layers + blur).
- Evolution machine: energy charging, glass chamber glow, reveal burst.
- **Rift entrances (escalating, all 2.5D):** screen effects for R1–R5 (glitch flicker → strobe/static → signal lost & reconnect → screen tears/echo → melting/inverted mirage), cinematics for R6–R9 (rainbow shatter + mirror drones → darkness pulse + giant eyes → outline world + whispers → Null: full black → drone disassembly/reassembly → creatures crawling from screen edges → colossal reveal → title). Inside rifts the **Drone Feed** overlay (scanlines, noise, timestamp, glitchy HUD) is always on. Built with ScreenGui overlays, post-processing, camera choreography and particles.
- **Galaxy Aquarium:** dark-blue starry dome interior, soft nebula glow, floating rocks/plants, creatures gliding; it should be the most beautiful room on the base.
- **Skins:** each skin = preset bundle (materials/colors + beam effect + trail + capture effect + flame/smoke color + sound accent).
- Rarest-find **announcement banner** (server/global) with tier color and shimmer.
- Warp / new chapter cinematic: star streaks, FOV punch, white flash, title card.

## 4. UI style — "Mission Control"
- Clean, semi-transparent dark panels (#0B1220 @ 80%), thin accent lines, rounded 8px, icons + numbers, one accent color (cyan #39D5FF) + rarity colors. Font: GothamSSm/Montserrat-like via `Font.new` (Builder Sans / Gotham).
- Flight HUD styled like a drone operator monitor: altimeter (left vertical bar with zone marks), battery (top-left with % and drain animation), cargo slots (bottom icons filling up with creature icons), scanner ring around the drone, Recall button, warning banner area (top center).
- Base UIs: station panels slide in with tweens, hover/press feedback, satisfying purchase animation (button squish + coin burst + stat bar fill).
- Toasts for catches, unlocks, achievements. Popups minimal.
- Responsive: `UIScale` + `UIAspectRatioConstraint`, safe areas on mobile, large touch targets (≥44px). Load `roblox-dev:roblox-ui` and test with `rbx-device-simulator-lua`.

## 5. Audio
### Where the sounds and music come from (user asked: how, when making the game with AI?)
1. **Roblox Creator Store audio (start here):** thousands of free, licensed tracks and sound effects that are safe to use in Roblox games (Claude can search them with `search_asset`). Great for ambience beds (wind, space hum, rain), SFX (whooshes, explosions, chimes) and placeholder music.
2. **Layering:** Claude builds richer sounds by combining several library sounds in code (e.g. roar = low growl + pitched-down whale call + reverb; meteor = whoosh + bass hit + debris crackle), with random pitch/volume so they don't repeat.
3. **AI music/SFX tools (user's choice):** AI music generators and AI sound-effect generators can create original tracks and effects. **Check each tool's license allows commercial use** (paid plans usually do), export, then upload to Roblox (audio upload needs a verified account; uploads are moderated).
4. **Roblox's built-in effects:** `ReverbSoundEffect`, `PitchShiftSoundEffect`, `EqualizerSoundEffect`, `DistortionSoundEffect`, `EchoSoundEffect` let Claude make space/rift sounds feel distinct from the same source files.
All ids live in `Config/Audio` so music/sfx can be swapped any time.

- Source: Roblox Creator Store licensed audio (`search_asset`) + user-provided uploads. Record chosen asset ids in `Config/Audio` with names.
- **Music layers per chapter:**
  - Calm: ambient, airy pads (Earth), spacious synths (Space).
  - Tension: same key/tempo-compatible track with pulse/percussion (or a separate tense track crossfaded).
  - Danger: intense, fast percussion/strings/synth.
  - Base theme: relaxing, warm.
  - Stingers: Legendary catch, Chapter unlock, Perfect Launch.
- Crossfade 1.5 s via TweenService on `Volume`; danger in 0.5 s, back to calm slow (3 s) with 4 s hysteresis.
- **Ambience:** wind (strength by zone), rain/thunder (storm), near-silence + soft hum (space), radio chatter on base (subtle).
- **Rare creature calls:** each rare+ creature (and every T6+ rarity) has a distinctive call that plays when it spawns in your zone, panned toward it; after ~3 s an edge arrow hints the direction. Players learn the sounds ("that's a Skyhorn!").
- **Hazard audio quality bar:** meteors = whoosh doppler + shockwave boom + bass thump + debris crackle; lightning = rising crackle → crack → rolling thunder; explosions with sub-bass; every hazard paired with camera shake/nudge.
- **Living-sky ambience events** (random, positional/panned): distant growls & roars of unseen giants (with a huge silhouette passing far behind clouds), **meteors** whooshing past with shockwave ring + bass thump + camera nudge, whale-like calls in space, eerie low drones near anomalies, crackling energy. Kept atmospheric, not horror.
- **Catch sounds per tier:** pop (Common) → chime (Rare) → stinger (Epic) → fanfare (Legendary) → choir hit (Mythic/Celestial) → unique sting per rarity from T6 up. Modifier adds a layered accent sound (sizzle for Blazing, crack for Glass, zap for Electric...).
- **Music:** the user plans to make/provide music; until then use licensed placeholders and keep all ids in `Config/Audio` so they're easy to swap.
- **Rift audio:** each tier has its own entrance sting, ambience bed and arena music; rarer = longer, deeper, louder. Null Rift: total silence → single heartbeat → huge low swell.
- **SFX:** launch countdown beeps, ignition roar, rumble, separation clunk, drone thrusters (pitch by speed), beam hum (pitch by pull progress), creature struggle squeaks, catch pops (per rarity), lightning crack, debris impact, alarm (low battery), heartbeat (danger), UI clicks/hover, coin collect, upgrade purchase, evolution charge + reveal.
- SoundGroups with user volume settings (Music/SFX sliders in settings).

## 6. Camera & game feel
- Springs for all camera movement; shake via noise with amplitude from MoodController.
- FOV punch on boosts/catches; slight tilt of drone with velocity.
- Hit-stop (0.05–0.1 s) on damage; slow-mo for big catches.
- Option to reduce screen shake (accessibility).

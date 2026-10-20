# Raining Hell — early alpha

**Version 0.3.0-rc.3 is a release candidate for an unfinished game in active development.**

A native macOS 2D voxel destruction sandbox prototype. **UI & graphics are subject to change.** Audio and gameplay are also provisional. No engine installation, downloaded assets, or runtime dependencies needed.

## Play

Open **dist/Raining Hell.app**, or mount **dist/Raining Hell-macOS.dmg** and drag the app into Applications. **dist/Raining Hell-macOS-portable.zip** contains the same self-contained app plus this README and release notes; unzip and run it from any folder. Versioned release candidates are in **dist/releases/0.3.0-rc.3/**. Quit an older running copy before launching the new one.

Requires macOS 12 or newer. The app is built for Apple Silicon Macs. This local development build is ad-hoc signed, not Developer ID signed or notarized. If a downloaded copy is blocked, use macOS Privacy & Security → Open Anyway after trying to launch it.

| Control | Action |
| --- | --- |
| E / Deploy | Open or close the requisition menu (troops and supply drops) |
| 1 / 2 / 3 / 4 | Pick rifleman, grenadier, rifle squad, or RPG gunner, then click inside the green landing zone to place it |
| Left-click terrain with only RPG gunners selected | Fire one rocket from each loaded gunner along the amber aim line to the pointer |
| Q / Support | Open the requisition menu on the Support tab; 1 picks the supply crate, then click the map where it should land |
| Right-click / Escape while placing | Finish deploying |
| Left-click terrain | Selected soldiers continuously attack that point |
| Left-click soldier | Select that soldier (click the only selected soldier again to deselect) |
| Shift-click soldier | Add/remove from selection |
| A / Select All button | Select all soldiers; if all are already selected, deselect them |
| Escape with soldiers selected | Clear the selection (press again for the pause menu) |
| Right-click | Move selected soldiers; cancels their attack orders |
| H | Hold fire (cease fire and hold position) |
| S / ⚙ button (main menu, top right) | Settings: sound, volume and full screen, plus a Danger Zone tab that deletes save data (the bank) or resets settings after you type DELETE / RESET to confirm |
| Escape / ☰ button (top left) | Pause menu: resume (Esc), restart the map (R), settings (S: sound, volume, full screen), or exit (Q), which asks whether to go to the main menu (M) or quit the game (Q) |
| Space / P / pause switch (top right) | Pause/resume |
| T / speed switch (top right) | Cycle game speed 1× → 2× → 4× (click a cell to pick one; picking a speed also resumes); new missions start at 1× |
| Tab / F1 / ? button (top left) | Show/hide the field guide: objective and full control list |
| O / HVT header | Expand or collapse the high-value target list under the minimap |
| M / pause menu Sound row | Mute/unmute all sound (a MUTED tag in the top bar also unmutes) |
| [ / ] | Lower/raise volume in 10% steps |
| Scroll wheel / pinch / = and - | Zoom in and out (25%–300%) around the pointer |
| Two-finger scroll / arrow keys / middle-drag | Pan the camera |
| Click or drag the minimap | Jump the camera to that part of the level |
| C | Centre the camera on the selected soldiers |
| X / Extract | Complete the mission once the point requirement is met |
| 0 | Return to 100% zoom |
| F | Toggle fullscreen |
| Command-Q | Quit |

The test level, Operation Ashfall, is a 5.7 km-wide (720 × 150 block) front, about seven times the area of the original map, laid out as six sectors from left to right: landing zone Alpha and the abandoned outpost bunker; a cratered no-man's land with a stepped trench and a burnt-out tank; the Kessel river gorge with a two-pier concrete bridge; the ruined town of Holloway (apartment blocks, a church with a bell tower, a gutted tower block); the Works No. 4 factory hall, chimney stack, and fuel tanks; and a hilltop fortress with a gun emplacement above a concrete-lined tunnel depot. Every structure is built from destructible blocks and stands under the structural rules below. The camera starts at 100% on the landing zone. Zoom out to see the whole front at once, or zoom in for close fighting. A minimap in the upper right shows the full level, your soldiers, the attack target, and the current view. Distant background layers move with parallax, and sounds off screen are panned and fade with distance.

Troops cost points. Each level grants starting points (Operation Ashfall: 2,000), and everything you earn by destroying infrastructure can be spent on more troops: rifleman 250, grenadier 500 (bigger blasts, slower reload), rifle squad of four 900, RPG gunner 1,200 (see below). Click **Deploy** (or press **E**), choose a unit, and click inside the green deployment zone at the landing zone to place it; placement stays armed while you can afford another. Spending lowers the same point balance that counts toward the mission requirement, so the menu shows a **safe to spend** amount and locks purchases once spending more would put the requirement out of practical reach: your points, plus 40% of the building value still standing (terrain and rubble excluded), plus unpaid HVT bonuses, must still cover it. You never have to level the whole map to recover from buying troops.

Ammo is limited. Riflemen carry 40 rounds and grenadiers 12. A small ammo bar floats over every soldier: green while stocked, amber with a **LOW** tag at a quarter load or less, and a blinking red **NO AMMO** tag once empty. The TROOPS readout counts soldiers who are low or out, and the minimap marks them amber or red. Empty soldiers keep their attack orders, stop firing, and show no trajectory line. They open fire again as soon as they are rearmed. To rearm, open the **Support** tab (**Q**) and call in a **supply crate** for 150 points. Click anywhere on the map: a cargo plane flies in low from the west and releases the crate just before the spot. The crate carries forward under its parachute, lands on the spot you clicked, and settles on whatever is beneath it. The plane then flies off. For up to 45 seconds the crate refills soldiers inside its dashed green ring (a 120 px radius). Each crate holds 400 rounds, enough to fully rearm 10 riflemen; partial top-ups draw only what they need. Its label counts the rounds left, and it disappears once empty. Each refilled soldier shows a green **REARMED** tag. Supply crates have no cooldown, so you can call as many as you have credits for; the Deploy button prompts for a supply drop when soldiers run low. Support purchases also follow the same safe-to-spend lock as troops.

The Support tab's second option is a **gun run** for 1,000. Pick it (**2** on the Support tab) and click the ground: a red line marks the 480 px strip it will hit, with the jet's line of fire onto it. A twin-engine ground-attack jet dives in from the west and fires a 120-round 30 mm burst, walking the impacts from the near end of the strip to the far end. It then pulls up and leaves. Each round is a high-explosive blast (radius 12 px): it chews through roofs, walls, and sandbags but only scuffs open ground. Rounds fly as ordinary shots, so a building between the jet and the strip takes the hits meant for the ground behind it. Over the tallest parts of the town and fortress, the jet stays near the top of the map, so zoom out to watch it. A gun run locks only itself for 30 seconds after it is called in; its card in the Support tab shows the countdown.

The third option is **firebombs** for 2,000. Pick it (**3** on the Support tab) and click the ground: orange arcs preview where each canister will fall, and a bar marks the burning pool each one leaves. A C-130 runs in from the west at the supply plane's height and rolls eight napalm canisters off its rear ramp, spaced 64 px apart and timed so each lands on its mark. A canister punches through up to 10 blocks of roof, wall, or trim until it breaks into a room, then bursts. It spreads a pool of burning gel across the surface it hit and splashes burning gobbets up and forward that stick to whatever they touch. Gel left with nothing under it runs down through holes. A firebomb run locks only itself for 90 seconds.

Fire is simulated cell by cell. Room contents, timber crates, and sandbags burn. Concrete, brick, steel, rubble, and glass don't, but they weaken in the heat. Heat rises, so flames climb toward ceilings and spread more slowly sideways and down. Fuel catches once it has absorbed enough heat, and that heat leaks away again if the fire moves on. Windows shatter, ceilings and roofs spall a block at a time, and burning crates and sandbags burn away. Each destroyed block scores like a blasted one and can bring down whatever it was holding up. Strong fires send up smoke and throw embers that can start spot fires in nearby rooms. Every fire runs out of fuel and dies out, usually within two to five minutes, leaving soot-blackened rooms and scorched surfaces. The minimap marks burning areas in orange. Weather doesn't affect fire yet; the rain is visual only.

Newly deployed soldiers are selected. There is no limit on how many soldiers can be deployed. Aim at the bunker, sandbags, crates, or ground to destroy individual eight-pixel blocks. Rock is more resistant than soil. Soldiers settle into craters and can step over small obstacles; tall bunker walls block movement. Explosive rounds follow ballistic arcs and collide with surviving blocks. Each soldier with an attack order shows a faded dashed trajectory line predicting where its next round will land (brighter for selected soldiers); the line stops where the arc would first hit a block. Orders continue until changed or cancelled.

This is a graphics and interaction test: one large map, one soldier type, explosive weapons, procedural pixel graphics, rain, debris, muzzle flashes, and impact effects. Buildings use finite beam spans and column load limits: removing supports or overloading a narrow column makes masonry detach, rotate, fall, and crumble into persistent collidable rubble. Overhangs add up: a floor resting on another overhang, or a building whose ground is blasted away, falls once it sits too far sideways from a column that reaches the ground (concrete 16 blocks, brick 9). Soil and rock rest on the ground beneath them: undercut terrain can overhang only a few blocks (soil 3, rock 5) before it breaks off and falls. Fallen soil and rock stay soil and rock and can settle on rubble or buildings; only building materials crumble into rubble. Rear panels and fixtures are destructible and disappear with the floors or ceilings that support them. This is an approximate game physics model, not an engineering simulation. Falling sections collide with static terrain and settled rubble; moving sections do not collide with one another. No enemies, soldier damage, advanced pathfinding, saving, or campaign yet.

**RPG gunners** are aimed by hand. They never take attack orders. Select only RPG gunners (one or several) and an amber dashed line runs from each tube toward the pointer: the rocket flies straight at the pointer and keeps going past it, sagging lower the further it travels, so aim high for distant targets. The line stops where the rocket would hit, and a ring marks its blast. Left-click to fire one rocket from every selected gunner that is loaded. Each gunner carries 7 rockets and needs 7 seconds to reload after every shot. Clicking during the reload fires nothing and the status line reads **RPG RELOADING**; nothing on the map shows the reload. Gunners walk at about grenadier pace and at half that while reloading. In a mixed selection (RPG gunners with riflemen or grenadiers), the aim lines are hidden and a left click gives the attack order to the other troops only; the gunners hold fire. Supply crates refill rockets like any other ammo.

## Mission scoring

Every mission has a point requirement (Operation Ashfall: 150,000), measured against your point balance: starting points plus points earned, minus points spent on troops. The Extract button and **X** stay locked until you reach it. After extracting you can return to the main menu or keep fighting to raise your score. Destroying infrastructure is the objective. Concrete and brick are worth 10 points a block. Glass, sandbags, and crates are worth 5. Clearing rubble is worth 2, and soil or rock only 1. Blocks that collapse score the same as blocks that are blasted.

The top bar shows one wide **POINTS** readout, with the goal and a progress bar beside it. Every point value in the game, including impact popups, HVT bonuses, troop costs, and the Extract button, is written as "N PTS", so points can't be confused with other numbers. Rounds fired, grid references, and range readouts were removed from the HUD.

High-value targets are marked with red brackets and listed under the minimap (click the header or press **O** to expand the list). Their blocks are worth triple, and each pays a bonus once 60% of its original structure is gone: outpost bunker +1,500, Kessel bridge +5,000, church bell tower +2,000, fuel depot and stack +4,000, gun emplacement +3,000, and tunnel depot +4,000. Other objective types, such as placing charges, are planned.

## Audio

Includes original synthesized gunfire, explosions, shattering glass, structural creaks and collapse rumbles, rubble impacts, footsteps, deployment and order acknowledgements, selection/pause/reset cues, and a seamless wind/rain ambience loop. Repeated effects cycle through variations and use stereo positioning. Simultaneous voices are limited and their combined gain is bounded during large volleys.

Volume starts at 50%. Mute and volume are saved locally. Pausing suspends ambience and stops active effects; command confirmations remain available. Moving to another app silences audio until the game becomes active again. No microphone, network access, or external audio downloads are needed. An unavailable audio device does not prevent gameplay.

All sound assets are generated from the included `scripts/sounds.py`; there are no third-party audio recordings or sample-library dependencies.

## Build and package

Install Apple's Xcode Command Line Tools and Python 3, then run:

```sh
./scripts/build.sh
./scripts/package.sh
# Or rebuild, test, and stage a complete versioned release candidate:
./scripts/release.sh
```

The build generates the icon and original WAV assets, compiles an optimized arm64 binary, applies an ad-hoc signature, and runs the gameplay, structural physics, and audio checks. Packaging produces a compressed drag-to-Applications DMG and a portable ZIP.

```sh
"dist/Raining Hell.app/Contents/MacOS/RainingHell" --self-test
"dist/Raining Hell.app/Contents/MacOS/RainingHell" --preview
# Screenshot any part of the level: --camera x,y,zoom (world pixels; 2880,700,0.25 frames the whole front)
"dist/Raining Hell.app/Contents/MacOS/RainingHell" --camera 2880,700,0.25 --screenshot overview.png
```

`--preview` deploys a squad and gives it an attack order. Normal launches open the level-select menu (only the test level for now); choosing a level starts a fresh, empty landing zone. Escape in a level opens a pause menu to resume, restart, change settings, or exit; exiting pops up a choice between the main menu and quitting. The code separates the voxel simulation in `Sources/World.swift` and `Sources/Structure.swift`, audio in `Sources/Audio.swift`, from AppKit rendering/input in `Sources/GameView.swift` and app startup in `Sources/main.swift`.

## Release status and verification

See **RELEASE_NOTES.md** for this candidate's changes and limitations. `scripts/release.sh` builds and stages local artifacts only: it does not tag a commit, push code, upload files, or publish a release. The candidate folder contains versioned DMG and portable ZIP files, README, release notes, and SHA256SUMS.txt. From that folder, run `shasum -a 256 -c SHA256SUMS.txt` to verify the downloads.

These are development-signed packages. For a normal public macOS distribution, the remaining signing step is to sign with the project's Developer ID certificate, submit the app/DMG to Apple's notarization service, staple the ticket, then regenerate package checksums. No signing credentials are included in the repository. Wider release should also include listening/playtesting on the minimum supported macOS version.

No progress is saved; each launch starts a fresh map. Volume/mute preferences are stored in macOS defaults under `games.raininghell.prototype`.

## More from eptkod

More games and apps by eptkod, including free browser games, are at **[home.eptkod.com](https://home.eptkod.com/)**.

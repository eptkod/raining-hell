# Raining Hell 0.3.0-rc.2

**Early alpha / release candidate — work in progress. This is not a finished game.**

This candidate packages the first playable sandbox for feedback. UI, graphics, audio, physics, and gameplay are subject to change. No public release has been published by the build scripts.

## What's included

- One large test map (720 × 150 blocks, about seven times the original area) in six sectors: landing zone and outpost bunker, no-man's land with a trench and wrecked tank, a river gorge and bridge, a ruined town with a church tower, a factory with a chimney and fuel tanks, and a hilltop fortress over a tunnel depot. All of it is destructible.
- Zoomable, scrolling camera (25%–300%) with pinch, scroll wheel, keyboard, and middle-drag controls, a clickable minimap, parallax background layers, and sound that pans and fades with the camera.
- Deploy individual soldiers or squads, select units, give attack and movement orders.
- Deselecting: **A** and the dock button toggle between Select All and Deselect All, clicking the only selected soldier again deselects them, and Escape clears the selection before opening the pause menu.
- Ballistic explosive rounds, debris, rain, muzzle flashes, and impact effects.
- Support and load checks, falling masonry, collidable rubble, and rear walls that disappear with destroyed structures.
- Reinforced concrete: buildings carry rebar, so they shrug off more of each blast and leave bent bars standing in the holes that keep damaged slabs hanging. Undercut a building on one side and it creaks over, snaps at a weak storey and falls on its side; knock out a whole storey and the floors above pancake down through the ones below.
- New original synthesized audio: four gunfire variants, four explosions, three collapse rumbles, three rubble impacts, three glass breaks, four footsteps, six command/interface cues, and a seamless rain/wind loop.
- Stereo positioning, bounded sound overlap, automatic ambience suspension when paused or inactive, mute, and saved volume preferences.
- Universal macOS app, drag-to-Applications DMG, and portable ZIP with documentation.
- Main menu with level select (only the test level for now).
- Escape opens a pause menu: resume, return to the main menu, or quit. Cease fire is now on X only.
- Mission scoring: buildings outscore ground, high-value targets (bridge, bell tower, fuel depot, gun emplacement, tunnel depot, outpost bunker) pay triple plus a destruction bonus, and you can extract with **E** only after reaching the mission's point requirement.

- Requisition: troops now cost points. Open the Deploy Troops menu (**D**), pick a rifleman, grenadier, or rifle squad, and place it inside the landing-zone deployment area. Levels grant starting points, earned points can be spent, and purchases lock before spending would make the mission requirement unreachable.

- Decluttered HUD: a single POINTS readout with goal and progress bar; all point values read "N PTS"; impact popups merge instead of stacking; rounds counter, coordinates, grid letters, and cursor grid references removed; HVT damage shown as bars instead of percentages.

- Trajectory lines: soldiers with attack orders show a faded predicted arc to where their next round will hit, brighter for the current selection.

- RPG gunner (1,200): a hand-aimed troop. With only RPG gunners selected, an amber line previews each rocket's dropping flight toward the pointer; left-click fires. 7 rockets, a 7-second reload after each shot (listed in the requisition menu; clicking early reads RPG RELOADING), grenadier walking pace, half pace while reloading. In mixed selections the gunners hold fire and show no aim line.

- Limited ammo: riflemen carry 40 rounds and grenadiers 12. Ammo bars over each soldier turn amber with a LOW tag when running low and show a blinking red NO AMMO tag when empty. The status bar counts low and empty soldiers, and the minimap colours them to match.
- Support balance: air strikes hit much harder for the same price; no weapon's damage went down. Gun run: 120 rounds (was 80), 12 px blasts (was 8), 30-second cooldown (was 45). Firebombs: eight canisters (was six), each with a bigger burst charge and more napalm; burning gel heats what it clings to harder; concrete, brick, steel, and rubble give way to fire sooner; 90-second cooldown (was 120). Firebombs called near the map edge no longer burst uselessly off-map. Per credit, a gun run now scores about three times what it did and firebombs about six times, both well ahead of an RPG gunner's load.
- Support tab: the requisition menu now has TROOPS and SUPPORT tabs (**D** / **S**, or the new Support button). The first support option is a 750-point supply crate. A cargo plane flies overhead from the west and drops it by parachute onto the chosen spot, where it rearms every soldier within its ring for 45 seconds. All support shares a 20-second cooldown, so future air strikes can't be spammed.
- Gun run (1,000): a second support option. Click the ground and a twin-engine ground-attack jet dives in from the west, walks an 80-round 30 mm burst across a 480 px strip, then pulls up and leaves. Buildings in its line of fire shield what's behind them. It has new jet flyover and cannon-burst sounds and shares the support cooldown.
- Firebombs (2,000): a third support option. A C-130 drops a stick of six napalm canisters that punch into buildings and start fires. A new cell-by-cell fire simulation burns room contents, crates, and sandbags. Heat rises and spreads to nearby fuel, shatters glass, and slowly spalls concrete, brick, and steel. Smoke and embers rise from the fires, and they die out on their own once the fuel is gone. The result is slow, steady damage over a few minutes rather than one big blast. 120-second cooldown.

- Game speed: a speed switch in the top bar runs the battle at 1×, 2×, or 4× (**T** cycles, or click a setting). Faster speeds run extra fixed simulation steps, so shots and collapses play out the same, just quicker. The top bar shows FAST FWD while sped up.

- Simpler HUD: the command dock keeps only Deploy, Select All, Cease Fire, and Extract. Pause and speed sit together in the top right; menu (☰) and field guide (?) buttons sit in the top left. Sound and volume moved into the pause menu, which also opens the field guide and restarts the map. Support drops live in the Deploy menu, whose button counts down the support cooldown and prompts for a supply drop when ammo runs low. The SITREP bar became a status toast that fades after a few seconds. The HVT list collapses to a one-line tally (click it or press **O**). The field guide now lists every control, replacing the dock's mouse hints. Decorative captions were removed from the battlefield.

## Controls added

Scroll wheel, trackpad pinch, or **=** / **-** zoom around the pointer, and **0** returns to 100%. Two-finger scrolling, the arrow keys, or middle-drag pan the camera. Click or drag the minimap to jump there, and press **C** to centre on the selected soldiers.

**T** cycles game speed between 1×, 2×, and 4×.

**M** toggles all audio. **[** lowers volume and **]** raises it in 10% steps. The audio label in the upper-right corner is also clickable. Default volume is 50%; mute and volume are remembered between launches. If audio initialization fails, gameplay remains available and the HUD reports audio unavailable.

## Current limits

- One map and soldier type. Soldiers cannot climb stairs or pass interior columns, so reaching far sectors means blasting a route; no enemies, campaign, soldier damage, saves, music, or advanced pathfinding.
- Structural physics is a gameplay approximation. Moving masonry sections do not collide with each other; they collide with terrain and settled rubble.
- Audio is synthesized prototype sound design and will evolve with the game.
- macOS 12+; Apple Silicon and Intel binaries included. Windows is planned later.
- Local packages are ad-hoc signed, not Developer ID signed or Apple-notarized. Intel and the minimum macOS version have not been tested on dedicated hardware.

## Candidate validation

Build-time checks cover gameplay, structural stability and collapse, rear-panel cleanup, audio event routing, generated WAV integrity, and decoding every sound asset. Packaging verifies the app signature, DMG checksum, and ZIP integrity. Final listening and gameplay feedback on different Macs is still useful before wider distribution.

See README.md for setup, controls, build instructions, and distribution details.

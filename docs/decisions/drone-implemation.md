# Decision: FPV / kamikaze drone bomb

## Revised 2026-10-15 (implemented, by the owner's call)
The owner chose **mouse-follow piloting** over the fly-to-target v1 below. What shipped (`Sources/Drone.swift`):
- Still a support call-in (`SupportKind.drone`, SUPPORT row 4): **300 CR, 10 s cooldown, one drone at a time**, blast radius 36 (an RPG is 34).
- Placed like other support and flies in from the run-in edge (`World.approach`, Q/E) at `droneCruise` (skyline − 140) at 900 px/s. Near the placed point it hands over and the player pilots it.
- **Quadcopter physics:** thrust along the body axis, capped at 2.2 g; tilt limited to ±0.95 rad and turning at 6 rad/s; gravity; linear drag. A velocity controller with arrival braking steers it toward the pointer's world point. It leans into moves, overshoots slightly (~30 px) and settles into a hover.
- **Camera follows with a dead zone** (`GameView.followDrone`). Inside the middle box the pointer is a fixed map point, and holding the pointer near the view edge keeps the drone flying that way. This answers the original "swerves while panning" objection.
- **Detonation:** contact with any block or the bottom, a left-click on the field while piloting, the rebindable `KeyAction.detonate` (default B), or a 20 s battery. A flat battery cuts the motors; the drone then falls and goes off where it lands.
- Kept the map sides and the sky ceiling as walls. It can't be shot down. No new sounds.
- While a drone is piloted, a left-click on the field detonates it instead of selecting or attacking. Keys and right-click move still work.

The original decision follows for history.

## Decided
Implement the drone as a **support call-in**, not a troop. v1 is **fly-to-target**; steering comes later and stays cheap.

### v1 (ship first)
- New support kind `drone`, with its own cooldown and bank cost, in the support menu and ghost placement like the gun-run.
- Player places a target point. Launch side follows the existing rules (`World.supportSide`, Q/E, else nearer edge via `World.approach(toward:)`).
- Spawns via `World.entry`, cruises at `transportAltitude` (skyline-aware), dives onto the point and detonates.
- Also detonates on contact with a block or soldier along the way.
- **Separate `Drone` entity**, not a `Shot`: keeps the RPG rocket path and its tests untouched.
- Fixed lifetime. If it never hits (off-map, timeout), it is removed or detonates where it is; the cooldown is spent either way.
- No camera takeover, no input capture, no new input mode. The squad keeps acting.
- Blast reuses the existing explosion and voxel damage path, with a radius smaller than the firebomb's and a long cooldown.
- Drawing: sprite, trail, minimap blip, ghost. Reuse the blast sound.
- Hints that name a key use `k(.action)`. Any new key is a `KeyAction`.

### v1.5 (only if cheap)
- **Retarget by click** while the drone is alive, with a capped turn rate. This reuses placement logic and avoids pointer-to-world mapping while the camera pans.
- No detonate key and no battery rules.

### v2 (only if v1 is played and players want it)
- Camera follow / FPV view. Still no troop and no stuck-state input mode.
- Shop upgrades (cooldown, blast radius) through the single `World` accessor from `HANDOFF-shop.md`.

## Why
- All three of us converged on support. The support pipeline already provides placement, cooldown, heading, entry, departure, minimap and ghosts.
- A troop drone breaks the soldier assumptions (no ground position, dies on use) and adds a third manual-control mode on top of the RPG `manualAim` special-casing in `World.attack`, mixed selections and `GameView`. That is high regression risk in the most tested path.
- Manual piloting takes the player's attention off a real-time squad under fire, and invites stuck states (drone dies, timeout, pause menu while input is captured).
- Fly-to-target is a real drone bomb at about half the cost, and each later step is independently shippable.

## Options that lost
- **`TroopKind.drone` with manual FPV control:** rejected for the reasons above; revisit only after v1 if players ask.
- **Support plus camera-follow piloting (Chair's R1):** it brings back the input-mode cost under a support label.
- **Continuous pointer steering for v1 (Chair R2, Pragmatist):** the pointer is in screen space while the map scrolls and zooms, so the drone would swerve whenever the player pans. It needs a defined world mapping. Retarget-by-click is cheaper and clearer.
- **Lateral left/right steering keys:** needs new `KeyAction`s and rebinding UI, and gives neither FPV feel nor simplicity.
- **Detonate key, battery stats, "deselect and cancel":** extra rules with no v1 value; cut.
- **Reusing `Shot`:** ballistic with its own gravity, so a steered cruise-and-dive object doesn't fit and risks the RPG path.

## Still open
- **Balance numbers:** blast radius and cooldown must be set before coding and checked against level 1 and level 6 `World.reinforcement` and rebar, so the drone neither trivializes later levels nor outclasses the RPG and firebomb.
- **Shoot-down rule** (Chair): soldiers shooting the drone gives counterplay but adds a combat rule. Undecided; default is to leave it out of v1 and tune with cooldown and blast size.
- **Level scaling:** entry-edge distance differs on wide maps; may need per-level flight time or lifetime.
- **Skyline clearance:** whether detonating on the first wall during approach is a feature or should use `strafeFloor`-style raising.
- **Single drone vs. salvo per call-in:** single in v1.
- **Estimate:** "about a day" (~300 lines plus hooks) is optimistic once a separate entity, drawing, minimap and tests are counted.

## Definition of done
- Tests: impact damages blocks, off-map and timeout removal, intact map stays at zero collapses.
- `./scripts/build.sh` then `./scripts/package.sh`, per CLAUDE.md. Do not run `release.sh`.

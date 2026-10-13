# Handoff: weather that affects fire

Status (2026-10-13): **not started.** The fire simulation and the C-130 firebomb run are in. Weather is not part of either yet. This document covers what exists and where weather should plug in.

## Goal
Weather should change how fires behave, and the player should be able to see it:
- **Wind** pushes flames, heat, smoke, and embers downwind. Fires spread faster downwind and slower upwind, and embers start spot fires farther away.
- **Rain** damps fires that are open to the sky. It cools them faster, lowers how hard they burn, and makes fuel harder to light. Rooms with a roof over them are sheltered. Napalm gel should mostly ignore rain, as real napalm does, so firebombs still work in a storm.
- **Humidity / dryness** (optional) raises or lowers ignition points.

## What exists today
- **No weather state anywhere.** The rain is drawn in `GameView.drawBattlefield` (search "Fine rain is atmosphere only"): 120 fixed streaks with a constant slant and speed, purely cosmetic. The ambience audio is a fixed rain/wind loop. Don't change the audio playback path (see the user's audio memory note: AVAudioPlayer must stay).
- **Fire model:** `Sources/Fire.swift`. Read the `FireField` doc comment first. Summary:
  - Per-cell arrays sized `World.columns*World.rows`: `flame` (0–1), `fuel` (own fuel, lazily filled by `ownFuel`), `gel` (napalm), `heat` (toward ignition), `scorch` (damage to blocks that can't burn), `char` (soot level for drawing), `listed` + `burning` (active list), `warm` (cells holding heat).
  - `World.updateFire(dt)` runs every frame from `World.update`. It moves bombers, canisters, gel drops, and embers each frame, and runs `stepFire` every `World.fireStep` (0.1 s of game time). Game speed works by running more `update` steps, so anything driven from `update` and `stepFire` scales correctly.
  - `stepFire`, for each burning cell:
    1. gel drips if it has no support;
    2. `air` (oxygen) factor;
    3. `target = air*min(1,supply/3)`; `f` eases toward `target`;
    4. fuel is consumed;
    5. heat goes to neighbours through `World.heatSpread`, plus `gelContact` into blocks the gel touches;
    6. smoke (particle kind 14) and embers come off "vented" cells.
    
    Afterwards, heat in `warm` cells decays by `World.heatLoss`.
  - `heatCell(n, amount)` is the one entry point for heat. Fuel ignites at `ignitionPoint`. Non-combustible blocks fail at `heatToughness × toughnessSpread` (×2 on footings).
  - Embers: `updateEmbers` (gravity 90 px/s², horizontal drag). They light `selfBurnable` cells they enter.
  - Soot particles: kind 14, updated in `World.update`'s particle loop. They rise and billow and have no horizontal force.
- Drawing: `Sources/FireView.swift` (flames, glow, canisters, gel, embers, minimap, ghost) and the soot overlay in `GameView.drawCells`/`tile`.
- Tests: `Tests/PhysicsTests.swift`, the "Firebombs" block, run by `scripts/build.sh`. Fires at x=2750 currently burn out in about 100 s. Across the map the longest is about 490 s (x=4400). A small throwaway harness that buys a run and prints `fire.burning.count`, `destroyed`, and `score` each simulated second was the quickest way to tune.

## Where weather plugs in
Add a small deterministic weather state to `World`, for example `struct Weather { var wind: Double /* px/s, + = east */; var rain: Double /* 0…1 */ }`. Reset it in `World.reset()` (or per mission in `setupMission`), and optionally let it drift slowly in `update`. Then:

| Effect | Seam |
|---|---|
| Wind skews heat spread | `stepFire` loop over `World.heatSpread`: scale weights with `dx == sign(wind)` up and the upwind ones down. Also consider shifting the `(0,-2)` plume one column downwind in strong wind. Keep the static table as the calm baseline. |
| Wind carries embers | `updateEmbers`: add `(wind - e.velocity.x) * k * dt` to `e.velocity.x`. Ember spawn velocity is in `stepFire`. |
| Wind drifts smoke | `World.update` particle loop, the `kind == 14` branch (and kind 9 if wanted). |
| Rain damps exposed fire | `stepFire`, where `target` is computed: multiply by `1 - rain*k` for cells open to the sky. Don't reduce gel burning much. Add a sky-exposure test, e.g. no solid cell above it in the column, cached per column per step. `ground(at:)` scans a column, so don't call it per cell. |
| Rain cools | `stepFire` heat decay at the end: use a larger `heatLoss` for exposed `warm` cells while raining. |
| Rain / humidity resist ignition | `ignitionPoint(_:)`: raise it for exposed cells. |
| Visible rain matches the state | `GameView.drawBattlefield` rain loop: streak count from `rain`, slant from `wind`. |
| HUD | Optional small WIND/RAIN readout in the top bar (`drawHUD`). Keep it consistent with the existing Tac palette. |

## Constraints
- **Determinism:** use `world.random` (the seeded LCG), never `Double.random`. `Tests/AudioEvents.swift` checks that sound routing doesn't change `seed`, so don't consume randomness from audio callbacks.
- **Performance:** `World.maxFires` caps active cells (14,000). A large fortress fire is about 840 cells and costs about 100 ms per simulated second, including structure solves. Keep per-cell weather work O(1).
- **Balance:** fires are meant as slow, consistent damage, and every fire must still die out. Keep the existing tests passing ("the fires die out on their own", "fire keeps damaging infrastructure…"). Add weather tests, for example:
  - with wind east, more cells burn east of the target than west;
  - heavy rain shortens the burn of exposed fuel but not of gel or sheltered rooms;
  - a calm, dry weather state reproduces today's numbers.
- After any game change, follow `CLAUDE.md`: `./scripts/build.sh` then `./scripts/package.sh`. Other agents may be editing the same tree. If `swiftc` reports "modified during the build", re-run it.

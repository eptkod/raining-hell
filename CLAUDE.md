# Raining Hell — working notes

## After every game change
Rebuild and repackage so the playable app and DMG in `dist/` always match the source:

```sh
./scripts/build.sh     # updates dist/Raining Hell.app and runs all tests
./scripts/package.sh   # rebuilds dist/Raining Hell-macOS.dmg and the portable ZIP
```

Don't run `scripts/release.sh` unless asked; it overwrites the versioned candidate in `dist/releases/`.

## Feature notes (keep in mind when touching related code)

- **RPG gunner is manually aimed (implemented).** `TroopKind.rpg` has `manualAim`: it never takes `Soldier.target`. `World.attack` routes to `World.fireRockets` when `rocketsSelected` (every selected soldier is an RPG); in mixed selections RPGs are skipped and hold fire. The aim line is `World.rocketTrajectory(of:at:)` toward the pointer, drawn in `GameView.drawTrajectories` only while `aimingRockets`. Rockets are `Shot`s with `rocket: true` and their own weaker `gravity`. Reload is deliberately not shown on the map (only the menu text and an RPG RELOADING status line).
- **Fire simulation (`Sources/Fire.swift`, drawing in `Sources/FireView.swift`).** Firebomb runs start cell-by-cell fires; see the `FireField` doc comment. Weather affecting fire is planned and handed off in `HANDOFF-fire-weather.md`.
- **Support aircraft fly in from the nearer map edge.** Supply planes, gun-run jets and firebombers carry a `heading` (+1 east, -1 west) from `World.heading(toward:)`. Transports fly at `World.planeAltitude`, just above the top of the map, so they clear every structure; the jet cruises higher still, and `strafeFloor` raises its dive until no part of the pass clips a building. They spawn beyond that edge via `World.entry` and are removed once they've flown off the far side (`World.departed`). Anything they release (crate drift, canister velocity, gun muzzle, burst walk direction) and all their drawing, minimap arrows and call-in ghosts follow `heading`. Jet rounds fired from off-map start where their flight path crosses the map edge.

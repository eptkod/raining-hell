# Level construction

Status (2026-10-15): **implemented: six operations.** Level 1 (renamed **Kessel Crossing**) is the original map, unchanged voxel for voxel; levels 2–6 are built from the same sector builders. The table lives in `LevelSpec.all` (`Sources/Levels.swift`), and the map layouts are in `World.raise`. This document records how they are built so each one is larger and harder than the last, and how starting credits are set per level.

## Principles

1. **Later means larger and harder.** Each level is wider, has taller buildings, more objectives, tougher reinforcement and a higher extraction requirement than the one before.
2. **Harder never means starved.** Difficulty comes from the map, not from handing the player the bare minimum. Every level must open with enough credits to field a viable force and make at least one support call (see *Starting credits*).
3. **Funds vary on purpose.** Starting credits are set by the level's difficulty profile. Some levels are generous, some are deliberately tight, but a tight level is still playable from its opening grant alone.
4. **Keep the intact map stable.** Every level must start at zero collapses (the first physics test) and must be solvable without the bank.

## Levels

Six operations. Numbers below are what's in `LevelSpec.all` and should be tuned in play. Width is in design units (8 px each; `World.columns` = width × `scale`). Lift is the number of design rows added above level 1's map. The ground sits that much lower, and towers and blocks rise that much taller.

| # | Name | Operation | Width | Lift (height) | `reinforcement` | Objectives | Requirement | Funds | Grant |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Kessel Crossing | Ashfall | 720 (1×) | 0 | 1.0 | 6 | 150,000 | standard | 2,000 |
| 2 | Marrow Ferry | Cinder | 864 (1.2×) | 9 (+16%) | 1.15 | 7 | 295,000 | generous | 4,000 |
| 3 | Irongate Pass | Flint | 1008 (1.4×) | 18 (+31%) | 1.35 | 8 | 305,000 | tight | 3,000 |
| 4 | Vestra Works | Furnace | 1152 (1.6×) | 27 (+47%) | 1.6 | 9 | 550,000 | standard | 4,500 |
| 5 | Saint Odile | Bellwether | 1336 (1.86×) | 36 (+62%) | 1.85 | 10 | 1,015,000 | generous | 8,000 |
| 6 | The Citadel | Last Light | 1584 (2.2×) | 45 (+78%) | 2.1 | 11 | 1,075,000 | tight | 6,000 |

Operations unlock in order: extracting from level n opens level n+1 (`World.cleared`, saved under `cleared` with the bank, erased by DELETE SAVE). Dev mode opens all of them. Lobby cards show each level's front length, goal, grant and funds profile, plus READY, LOCKED or CLEARED. Enter starts the first operation not yet cleared.

### How a front is built

**Every front is its own country with its own landmarks.** Only Kessel Crossing uses the original sector builders (`outpost`, `noMansLand`, `town`, `crossing`, `works`, `fortress` in `Sources/Levels.swift`). Each later front has its own terrain profile (`World.terrain(for:)`) and its own structures in `Sources/Fronts.swift`, built from the shared pieces in `Sources/Landmarks.swift` (`house`, `gable`, `taper`, `disc`, `dome`, `lattice`, `colonnade`, `tank`, `footTo`). Don't reuse one front's landmark on another.

| # | Country | Landmarks, west to east (objectives in bold) |
|---|---|---|
| 1 | River valley | **Outpost bunker**, no-man's land, **Kessel bridge**, Holloway town and **bell tower**, **fuel depot & stack**, ridge fortress with **gun emplacement** and **tunnel depot** |
| 2 | Coastal port | **Coastguard station**, beach tank traps, steel truss **swing bridge**, **customs house**, warehouse row, freighter **SS Alderney** in the basin, **harbour cranes**, **oil terminal**, **Marrow Light** on the breakwater |
| 3 | Mountain pass | **Border checkpoint**, **Kurhaus sanatorium**, **Irongate tunnel** through the summit under the **summit radar**, arched **Schwarz viaduct**, the **Stausee dam** and reservoir, **alpine casemates**, the **Irongate** fortress gate |
| 4 | Steel town | **Water tower**, rail yard and **locomotive shed** with an engine inside, **gasholder**, canal **lift bridge**, **blast furnace** and stoves, **cooling towers**, **power house**, coke ovens and **coal tower**, **works directorate** |
| 5 | River city | **TV tower**, townhouse terraces, **Stade Odile**, steel arch **Pont Saint-Odile**, gothic **cathedral**, domed **Opéra**, glass towers (**Trade Tower**), **Hôtel de Ville**, underground **Métro** with a train, **Gare Centrale**, **Grand Hôtel** |
| 6 | Capital | **Flak tower**, ruined outskirts, dragon's teeth and pillboxes (**outer defence line**), pylon-guarded **Kaiser bridge**, **victory arch**, ministry, **parliament dome**, **state radio** mast, star-fort **citadel bastions**, **missile silos**, **palace of state**, ziggurat **high command** and the deep **command bunker** |

Each front also has its own sky and distant country (`GameView.backdrops`). The HUD names the operation, and a title card (`drawBriefing`) shows it for four seconds at the start.

**Rules the structure solver imposes (learned building these):**

- Rows may only narrow going up. A sloped shell (hollow roof, dome, arch) builds up overhang row by row, so it needs posts or ribs inside (`gable(attic:)` adds attic posts).
- Anything standing on a beam supported from one side only inherits that beam's overhang. Stand masts, chimneys and towers over a wall or column, or run them down to the ground.
- A wide span dumps all its load onto the edge column of its support. Keep heavy spans short, or add a column in the middle (the flak tower, the victory arch).
- Glass carries nothing and can't slope. It must sit on a floor or hang under concrete, and must never cut through a wall, column or rib.
- Brick has little tension. Tall openings under heavy brick topple, so use reinforced concrete.
- A horizontal `lattice` (two legs and rungs) tips over. Use a solid beam with truss posts.
- Bridge decks over gaps wider than 20 columns leave cells cantilevered from one side. Keep piers 20–22 apart.

**Rules for troops** (they collide only with soil, rock and bridge material 12):

- Don't replace ground with anything else. Footings, sandbags and facings must sit on top of the terrain, or troops sink into pits they can't climb (a step taller than 6 voxels stops them). New fronts have no concrete footings; buildings stand on the ground.
- Never draw with rock (2) above ground: troops treat it as a wall.
- Anything troops must cross that cuts into the ground (metro roof, silo hatches) is roofed in bridge material 12. Tunnels open out to the foot of the slope.
- Every front is tested: troops walk from the landing zone to its last objective.

### What "larger" means

- **Width.** `World.columns` grows per level. The landing zone (`deployZone`) stays about the same size, so the distance troops must cover grows with the map. Support aircraft already enter from the nearer edge and fly at skyline height, so they need no changes for wider maps; check that `skyHeight` still leaves room above the tallest building.
- **Height.** Taller structures raise `World.skyline` and make collapses bigger. Check `flightCeiling` and that the camera can still reach the planes.
- **Count.** More objectives, spread across the width, with the highest-bonus ones furthest from the landing zone.

### What "harder" means

- **Reinforcement.** Raise `World.reinforcement` per level (table above). It scales rebar concrete's blast resistance, capacity, span and tension, so later buildings need more ordnance to bring down.
- **Requirement.** `World.requirement` rises with the map's available points (`World.availablePoints`: structure worth plus objective bonuses, terrain left out), so it stays roughly the same share of what the map holds. Level 1's 150,000 is 33.7% of its 445,440. Later levels run from 34% to 39%. The new fronts hold far more points (Saint Odile about 2.8M), so their goals climb steeply, from 295K to 1,075K (a test keeps every level between 95% and 120% of level 1's share). Do not raise it faster than the map's worth grows, or the level becomes impossible rather than hard.
- **Distance and cover.** Place objectives behind terrain, gorges and fortified sections so troops must advance and support must be timed.
- **Not harder by starvation.** Do not make a level harder by cutting the opening grant below what the map needs.

## Starting credits

`World.startingCredits` is the selected level's `LevelSpec.grant`, plus `credits(for:)` of the last round's points. The grant is set by the level's funds profile (`FundsProfile`), whose `kit` lists the troops and support it must buy outright:

| Profile | Meaning | Opening grant covers |
|---|---|---|
| **generous** | Room to experiment | Rifle squad, grenadier, RPG gunner, a supply crate and a gun run (4,000) |
| **standard** | Normal pacing | Rifle squad, grenadier and a supply crate (1,800) |
| **tight** | Spend carefully | Rifle squad and a gun run (1,900), nothing spare |

Rules:

- **Floor.** No level opens with less than the cost of a viable opening: one rifle squad (900) plus one gun run (`World.openingFloor`, priced from `World.offers` and `World.support`, not a copied number).
- **Scale with the map.** A bigger map needs a bigger force, so a tight level 5 still opens with more credits than a generous level 1. Roughly: grant ≈ level opening cost × profile factor, where the factor is about 1.5 for generous, 1.0 for standard and 0.8 for tight, and never under the floor.
- **Carry-over stays.** The 4% payout of last round's points and the bank withdrawal (with its 25% loss) are on top of the grant, not part of it.
- **Anti-farming stays.** Restarted or abandoned rounds still bank nothing, so a generous grant cannot be farmed.

## Where it plugs in

- `Sources/Levels.swift`: `LevelSpec.all`, `FundsProfile`, `World.terrain(for:)`, `World.raise`, and Kessel Crossing's sector builders.
- `Sources/Fronts.swift`: the five later fronts' layouts and landmarks. `Sources/Landmarks.swift`: the shared building pieces.
- `Sources/World.swift`: `World.select(_:)` sets `World.level` and resizes `columns` and `rows`. Every World must be `reset` after a select (`GameView.startLevel` does it, and clears the tile caches). `reset` takes `reinforcement` from the spec.
- `Sources/Mission.swift`: `requirement` and `startingCredits` read the spec. `target` adds objectives, which are listed west to east. A span records its riverbed (`Objective.bed`). `extract` clears the level; `unlocked` gates the lobby.
- `Sources/GameView.swift`: lobby rows (`levelCard`), the radar title, the debrief line, and `resetCamera` (which drops with the lift). `--level n` and `--cleared n` in `main.swift` set up previews.
- The build compiles with `-wmo`. Without it, the now-mutable map size costs a cross-file accessor call in every hot loop.
- `HANDOFF-shop.md`: upgrades must stack with per-level grants, not replace them.

## Verification checklist

All of these are physics tests, run on every level:

- Intact map has zero collapses.
- Each level opens with at least the floor and its profile's kit, priced from `offers` and `support`.
- Each level is wider, taller, better reinforced and asks more than the one before.
- Each level's requirement is about level 1's share of its available points.
- Aircraft clear the tallest building on every level, and the camera can reach them.
- Every bridge is cut through when blown (end bays may stay resting on the banks), and troops can walk from the LZ to the last objective.
- Clearing a level unlocks the next.
- Run `./scripts/build.sh` then `./scripts/package.sh` after any change.

## Open items

- Final numbers for width, height, grants and requirement need playtesting.
- A structure solve on level 6 takes about 34 ms, against 15 ms on level 1. It runs at most every 0.12 s while something is moving, but watch frame time during big collapses.

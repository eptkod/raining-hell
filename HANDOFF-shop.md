# Handoff: upgrade shop in the lobby

Status (2026-10-14): **not started.** The bank exists. Nothing spends from it yet except withdrawals into a level. This document covers what the shop should do, what exists today, and where each upgrade plugs in.

## Goal
Add a **SHOP** that is reached from the level-select menu (the lobby). In it, the player spends **banked credits** on permanent upgrades that make later operations stronger:
- **Shorter cooldowns** for support calls (gun run, firebombs).
- **More damage** from troops: a bigger blast radius per round, so each hit removes more blocks.
- **More ammo**: larger magazines, and optionally bigger supply crates.
- Room for later items the user has mentioned: **cheaper troops**, and possibly faster reload.

Upgrades are bought with credits that are already in the bank. **They do not pay the 25% withdrawal loss.** That loss only applies to credits carried into a level. This gives the bank two uses: bring credits into the next fight at a loss, or invest them at full value.

## What exists today
- **Currencies** (`Sources/Mission.swift`, `Sources/World.swift`):
  - **Points (PTS)** are `World.score`, earned by destruction. The player needs `World.requirement` (150,000) to extract.
  - **Credits (CR)** are `World.credits`, spent on troops and support. A round starts with `startingCredits` (2,000) plus `credits(for:)` of the last round's points (4%, kept in `carriedCredits`).
  - **Bank** is `World.bank`. `extract()` deposits unspent credits once per round (`banked`). Abandoned or restarted rounds bank nothing, on purpose, so the 2,000 grant can't be farmed. `withdraw(_:)` moves credits into a round at `withdrawalLoss` (25%). `World.bank` has a `didSet` that calls `onBankChange`.
- **Persistence:** `GameView.persistBank()` loads and saves the bank under the UserDefaults key `"bank"`. `main.swift` only calls it when no `--` flags are passed, so preview and screenshot runs never touch the player's real save. Save the upgrades the same way, behind the same guard.
- **Lobby UI** (`GameView.drawMenu`):
  - Level cards: `levelCard(i)`, at 96,292, 584×124, one level today.
  - Bank panel: `bankFrame`, at 96,470, 584×206. It has −/+/MAX controls (`BankControl`, `adjustWithdrawal`) and ← → keys.
  - A radar on the right half (`drawRadar`, centred at 1046,470).
  - Clicks are handled in `mouseDown` under `if inMenu`, and keys in `keyDown` under `if inMenu`. Digits start levels.
  - The overlay pattern to copy for a full-screen panel is `drawEscMenu` / `drawDebrief`: a dimmed backdrop, then a `panel` with `brackets`, rows as buttons, and the Tac palette (`Tac.amber` for credits, `Tac.green` for ready/OK, `Tac.red` for refused).
  - Use `cr(_:)` and `pts(_:)` to format amounts.
- **Numbers the upgrades will change:**

| Stat | Where | Today |
|---|---|---|
| Blast radius per round | `TroopKind.blastRadius` (`World.swift`) | rifleman `bulletBlastRadius` 3.8, grenadier 22, RPG 34 |
| Magazine | `TroopKind.magazine` | rifleman 40, grenadier 12, RPG 7 |
| Reload | `TroopKind.reload` | 1.2 / 3.6 / 7 s |
| Gun run cooldown | `World.gunRunCooldown` (static, `Support.swift`), set on call-in at the `purchase` switch | 30 s |
| Firebomb cooldown | `World.firebombCooldown` (static, `Fire.swift`), set the same way | 90 s |
| Supply crate stock | `World.crateStock` = `crateLoads × rifleman magazine` (`Support.swift`) | 10 rifle loads; crates have no cooldown |
| Troop and support prices | `World.offers`, `World.support` | rifleman 250 … firebombs 2,000 |

`TroopKind` properties are read straight from the enum in several places, including drawing. For example, `GameView` reads `s.kind.magazine` for the ammo bars and `s.kind.blastRadius` for the trajectory end ring. **An upgrade must change the value every reader sees**, not just the firing code. Otherwise the ammo bar will show 40/40 for a 50-round magazine.

## Suggested design

### Data
Add a small value type, kept separate from round state so `reset()` never clears it:

```swift
enum Upgrade: String, CaseIterable { case supportCooldown, troopDamage, magazine /* later: cheaperTroops, reload, crateStock */ }
struct Loadout { var levels: [Upgrade: Int] = [:] }   // 0 = not bought
```

- Each `Upgrade` has a name, a description line, `maxLevel` (3 is a good start), `cost(level:)` (rising per tier), and the effect per level.
- `World` holds `var loadout = Loadout()` with an `onLoadoutChange` hook that mirrors `bank`.
- Put a `buy(_ upgrade:) -> Bool` on `World`. It checks the level cap and the bank, takes the bank, and bumps the level. The rules and the tests then stay in the test-compiled sources (`World`/`Mission`/`Support`). Note that `GameView` is not compiled into the tests.
- Persist the levels as a dictionary under a new UserDefaults key, for example `"upgrades"`, in `persistBank()` (consider renaming it to `persistProgress()`).

### Applying effects
Funnel each effect through **one accessor on `World`** so every reader stays consistent:
- `func magazine(_ k: TroopKind) -> Int`, `func blastRadius(_ k: TroopKind) -> Double`, and `func reload(_ k: TroopKind) -> Double`. They return the base value scaled by the loadout. Then replace the `kind.magazine` / `kind.blastRadius` / `kind.reload` reads in `World.swift`, `Support.swift`, and `GameView.swift`. Grep for `.magazine`, `.blastRadius`, `.reload`, and also `lowAmmo`/`outOfAmmo` on `Soldier`. Those are computed on the soldier and don't know the world, so give them the magazine as a parameter or store `capacity` on `Soldier` at spawn.
- **Cooldowns:** where `purchase(_ SupportOffer)` sets `gunRunCooldown = Self.gunRunCooldown` and `firebombCooldown = Self.firebombCooldown`, multiply by the loadout factor. The HUD cooldown bars divide by the static constant (`GameView`, search `Cooldown`). Switch those to the effective value too, or the bar will start partly filled.
- **Cheaper troops (later):** make prices go through a single `price(_ offer:)` that both `refusal` and `purchase` call. The requisition menu (`drawDeployMenu`) must show the discounted price.

### Suggested starting numbers (tune in play)

| Upgrade | Per level | Max | Cost per tier (CR) |
|---|---|---|---|
| Support cooldowns | −15% gun run and firebomb cooldown | 3 (−45%) | 1,500 / 3,000 / 6,000 |
| Troop damage | +12% blast radius, all troop kinds | 3 (+36%) | 2,000 / 4,000 / 8,000 |
| Ammo | +25% magazine, rounded up, all kinds | 3 (+75%) | 1,000 / 2,000 / 4,000 |

A typical extraction banks somewhere from a few hundred to a couple of thousand credits, so a full tier should take a few runs. Be careful with the damage upgrade:
- Blast radius scales destroyed area roughly with r², so +36% radius is about 1.85× the blocks per hit.
- The tests pin some damage behaviour, e.g. "a rifle round clears three to six voxels" (`rubbleReach` comment) and the blast score checks.
- **The base values must not change.** Upgrades only scale them when a level is above 0, so the existing tests keep passing with an empty loadout.

### Lobby UI
- Add a **SHOP** entry to the level-select screen: a button or card under the bank panel (there's free space at about y 690–830), plus a key such as **U** or **S**. Digits are already taken by levels, and ← → by the withdrawal.
- Opening it shows an overlay in the style of the escape menu. Show one row per upgrade with:
  - the name and description;
  - pips for the current level, e.g. ■■□;
  - the next effect, e.g. "GUN RUN 30 S → 25.5 S";
  - the cost in `cr()`;
  - the state: READY, NEED X CR, or MAXED.
- Show the bank balance at the top. Esc or a click outside closes it.
- After a purchase, clamp `withdrawal` to the new bank balance. `drawBank` already clamps when drawing, but do it explicitly too.
- Add a `--shop-preview` flag (with `--bank N`, which already exists) so the shop can be screenshotted headlessly. Example: `dist/Raining Hell.app/Contents/MacOS/RainingHell --bank 20000 --shop-preview --screenshot out.png`.
- Optionally list the active upgrades somewhere in the field. The requisition menu's info row is a good spot.

## Open questions for the user
1. **Permanent or per-run?** This doc assumes permanent tiers bought once. The alternative is consumable boosts bought for a single operation.
2. **Refunds or respec?** The doc assumes none.
3. **Should "damage" also cover support** (gun-run rounds, napalm heat), or only troops? Troops only is simpler and was what was asked.

## Tests to add (`Tests/PhysicsTests.swift`)
- Buying takes the right amount from the bank, refuses when short, and refuses at max level. A refused buy leaves the bank and level unchanged.
- `reset()` does not clear the loadout. A fresh `World` has an empty loadout and today's numbers.
- With the magazine upgrade, new soldiers spawn full at the bigger size, `lowAmmo` uses the new capacity, and crates refill to it.
- With the cooldown upgrade, `refusal(gunRun)` clears sooner. Assert the exact seconds.
- With the damage upgrade, one grenadier blast on a known building destroys strictly more blocks than without it.
- Purchases do not pay `withdrawalLoss`.

## Constraints
- **Determinism:** use `world.random`, never `Double.random`. `Tests/AudioEvents.swift` checks that the seed is not consumed by audio.
- Don't change the audio playback path (AVAudioPlayer must stay; see the user's memory note).
- After any game change, follow `CLAUDE.md`: run `./scripts/build.sh`, then `./scripts/package.sh`. Other agents may be editing the same tree. If `swiftc` reports "modified during the build", re-run it.
- Don't launch the app in a way that steals focus. Use the `--screenshot` path to check the UI.

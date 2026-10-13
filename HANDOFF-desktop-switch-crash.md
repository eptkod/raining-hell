# Handoff: crash after switching macOS desktops (Spaces)

Status (2026-10-13): **probably fixed. No crash since the Oct 12 fix, but only about 6 minutes of play have been logged since then.** Waiting on more real play that includes swiping between desktops.

## Symptom
On the user's MacBook (macOS 26.6.2), swiping to another desktop and back to the game's desktop crashed Raining Hell.

## Evidence
Crash reports: `~/Library/Logs/DiagnosticReports/RainingHell-*.ips`

| Report | Build | Crash site | Type |
|---|---|---|---|
| 2026-10-08 21:50 | original | `GameView.drawBattlefield` → `NSString.draw` → CoreText | `NSInvalidArgumentException`: "attempt to insert nil object" |
| 2026-10-08 21:51 | original | `AppDelegate.applicationDidFinishLaunching` → `cacheDisplay` | `EXC_BREAKPOINT`. Came from the `--screenshot` path; probably unrelated |
| 2026-10-09 07:37 | original | `GameView.drawHUD` → CoreText | the same nil-insert exception |
| 2026-10-09 07:59 | original | `GameAudio.sync` → `objc_retain` on a garbage pointer | `EXC_BAD_ACCESS` |
| 2026-10-09 10:45 | original | `GameView.drawBattlefield` → CoreText | the same nil-insert exception |
| 2026-10-11 20:42 | original | `GameView.drawBattlefield` → CoreText (`TAttributes::ApplyFont`) | the same nil-insert exception |

Every crash came from the **original** audio code, which created a new player per shot and paused the ambient loop on focus loss. There have been none since the Oct 12 fix.

Each crash happened in a different place, and one involved a garbage object pointer. That suggests **memory corruption**, with the crash site being wherever the game next touched the damaged memory. Everything in the game runs on the main thread, and there is no unsafe pointer code.

The unified log (`log show --predicate 'process == "RainingHell"'`) shows the same sequence before the crashes:
1. The app deactivates when the user swipes away (`NSPersistentUIManager flushAllChanges` is the marker).
2. About 4–5 s later, on a background thread: `AQME Default-Output: client stopping ... running count now 0`. CoreAudio has idle-stopped the output because the paused ambient loop was the last queue running.
3. The user returns and the ambient player resumes.
4. The game crashes between 0.6 s and about 30 s later.

### Since the fix (log checked 2026-10-13)
| Session | Switches away and back | `running count now 0` | Crash |
|---|---|---|---|
| 2026-10-12 08:03–08:05 | 3 | 0 | no |
| 2026-10-12 11:07–11:09 | 2 | 0 | no |
| 2026-10-13 09:27–09:29 (ended with Cmd-Q) | 3 | 0 | no |

Before the fix, crashes came within 30 s of returning. These 8 returns were clean, but the sample is small.

**Correction to the earlier handoff:** pooling `AVAudioPlayer`s does **not** stop audio-queue churn. `AVAudioPlayer` builds a new AudioQueue for every `play()` and deletes it when playback ends or `stop()` is called (log: `AudioQueueObject: New output` / `~AudioQueueObject: Deleting`). The Oct 13 session created and deleted 146 queues in 2 minutes. That churn can't be avoided while staying on `AVAudioPlayer`, and the user requires `AVAudioPlayer` (see below). What the fix does remove is the device idle-stop/restart, which only happened because the paused ambient loop was the last running queue.

To count queues per session: `grep -c "LoudnessManager enabled"` (one line per queue created) in that process's log.

## What was changed (Sources/Audio.swift)
1. **(Oct 12) The ambient loop is never paused.** It keeps playing, with its volume set to 0 when the game is unfocused, paused, muted or in a menu, so the output device never idles.
2. **(Oct 12) Effect players are pooled** (up to `GameAudio.copies` = 4 per sound file) instead of one `AVAudioPlayer(data:)` per shot. This removes object churn, not queue churn (see above).
3. **(Oct 13) Losing focus or pausing no longer stops effects.** `sync` calls the new `silenceEffects()`, which sets the in-flight voices' volume to 0 and lets them finish. It used to call `stopEffects()`. Leaving the game's Space now changes volumes only. Nothing is stopped, started or torn down. `stopEffects()` is still used for user actions (mute, volume change, restart, main menu).

Gains, panning, minimum gaps between repeats, the 16-voice cap and mute/volume behaviour are unchanged. Change 3 doesn't alter what you hear: the voices went silent at that moment before, and still do.

### Verification of change 3 (headless, silent)
A soak harness ran the real `GameAudio` in a bare `.app` bundle with `LSUIElement`, `.prohibited` activation, no window and every player's volume forced to 0. It played combat-rate cues and alternated 3 s in focus with 4.5 s away, for 40 s:

| | Queues stopped within 150 ms of each switch away | `running count now 0` |
|---|---|---|
| Before change 3 | 9, 5, 5, 2, 4 | 0 |
| After change 3 | 2, 0, 1, 2, 1 (background rate of sounds finishing on their own, about 4.5/s) | 0 |

A 90 s soak of the new code under Guard Malloc + MallocScribble (12 switches away and back) passed with no memory errors.

## Ground rules from the user
- **Don't swap the playback engine.** An AVAudioEngine/AVAudioPlayerNode rewrite was tried, and the user said it "sounds horrible and is inconsistent". It was reverted. Keep `AVAudioPlayer`, and keep sound output identical. If a playback change is unavoidable, say it may change the sound and ask the user to listen.
- **Never launch the game window, switch app focus or script Space switches on the user's Mac.** They work on the same machine. Debug from crash reports, the unified log and headless harnesses, or ask the user to run something. A headless audio harness must keep its output silent (volume 0).
- Rebuild and repackage after every game change (see CLAUDE.md).
- Other agents edit the same working tree (check `list_workers`). `build.sh` fails with "input file was modified during the build" while someone is editing. Wait and rerun it.

## Next steps
1. Ask the user to play normally and swipe between desktops a few times. Get any new `.ips` file and check the log for that session using the commands above.
2. If it crashes **in drawing** (CoreText nil-insert) with the new audio, audio was not the corruption source. Look at `GameView.tile()` and `GameView.chunkImage()`. Both swap `NSGraphicsContext.current` in the middle of `draw(_:)`, and on return many tiles get re-rendered at once. Use `NSGraphicsContext.saveGraphicsState()`/`restoreGraphicsState()` around the swap, or pre-render tiles outside `draw`.
3. Option for the user to run later: a diagnostic build with zombies enabled (`NSZombieEnabled=YES`) plus main-thread assertions in `draw(_:)` and `GameAudio.sync`, so the next crash names the culprit.

## Tooling notes
- `-sanitize=address` hangs at startup on this macOS (ASan shadow-memory init deadlock). Use `DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib` instead.
- Audio only loads when the binary runs from inside an `.app` bundle with `Contents/Resources/Sounds`.
- Soak harness recipe: compile `Sources/{World,Structure,Mission,Support}.swift`, a copy of `Audio.swift` patched with `sed` to set `player.volume = 0` before play and `ambient?.volume = 0` in `sync`, and a `main.swift`. The `main.swift` calls `NSApplication.shared.setActivationPolicy(.prohibited)`, creates `GameAudio()`, loops `sync(paused:false, active:)` and `play(...)` at 60 Hz with `RunLoop.main.run(until:)`, and flips `active` on a timer. Put it in a bundle whose Info.plist has its own `CFBundleIdentifier` (so it doesn't touch the game's saved volume or mute settings) and `LSUIElement`. Then count `client stopping` lines in `log show --predicate 'process == "<name>"'`.

# Notch code + performance audit (Phase 1, read-only)

Jim, 2026-11-07. No source, Info.plist or build.sh changed. Binary measured: build/Notch.app, CDHash 6f3787b9 (identical to the installed /Applications copy).

## Measurements

| State | CPU | Memory (RSS) | Idle wakeups | How |
|---|---|---|---|---|
| Closed, music playing (equalizer in the notch, real audio tap) | **1.2%** (30 s average, steady 1.0–1.3) | 57 MB | ~1.5/s | `top -pid` on the running app |
| Closed, nothing playing | **0.0%** | 21 MB | 0 | test copy (real views, no audio tap, no AppleScript) |
| Open, nothing playing (Office card polling) | **0.9%** | 42 MB | 0 | test copy |
| Open, equalizer animating (simulated signal) | **3.8–6.5%** | 22–51 MB | 0 | test copy; noisy because a video was playing on the machine |
| Closed, equalizer animating (simulated signal) | **0.6–4.3%** | 12–21 MB | 0 | test copy; same noise |
| Launch to notch on screen | **163–226 ms** (5 runs: 226, 163, 163, 176, 166) | | | launched the build/ binary, polled the window list |
| Clean `swift build -c release` | **0 warnings**, 0 errors, 65 s | | | separate scratch build folder |

The test copies are the real sources with two lines removed (no audio tap, no AppleScript), so they show the cost of the views, not of the tap. `sample` on the running app: the audio tap thread is about 0.3% of samples. Most of the per-frame cost is in `BarsView.tick`, and inside it `CGColorCreateSRGB` is the largest part.

## Already fine
- **Office card:** polls the hive only while the panel is open. It reads only files whose modification time or size changed, works off the main thread, reads at most 256 KB of log.jsonl, and treats a missing hive or bad JSON as "offline" with no crash (`try?` everywhere).
- **Audio tap:** runs only while `isPlaying` is true. It falls back to the simulated signal if permission is denied (the tap then delivers only silence).
- **Animations:**
  - The equalizer display link stops once the bars have settled after a pause.
  - The pulsing dot is a Core Animation layer (0% CPU).
  - The progress timeline exists only while the panel is open.
- **Battery:** event-driven (IOKit run loop source), no polling.
- **Removed features:**
  - No calendar leftovers: no EventKit and no calendar Info.plist key.
  - The Settings live preview is fully gone (no references left).
- **Info.plist keys:** both privacy keys are used (audio capture by the equalizer, Apple Events by now playing).
- **Force unwraps:** only in the FFT setup and Accelerate buffer pointers (they can't fail with fixed sizes) and in the self-check.

## Findings (ranked by value)

### 1. The equalizer reacts to all system audio, not just the music app
- **What:** `AudioTap.swift:37` uses `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`.
- **Why it matters:** the human saw the bars move to a Stremio video. The bars belong to the Spotify or Music track, so any other sound (video, calls, notification sounds) shows as music.
- **Evidence:** reported by the human today. The code taps the whole system mix by design.
- **Fix idea:** tap only the playing source's process. Translate the player's process ID to a Core Audio process object with `kAudioHardwarePropertyTranslatePIDToProcessObject`, then use `CATapDescription(stereoMixdownOfProcesses: [obj])`. Re-tap when the source changes. It needs no new permission: it's the same audio-capture permission.
- **Size and risk:** M (45 min). Medium risk: Spotify plays audio from a helper process, so we may need to tap the helper and not the main app. Check this first.

### 2. Play state can go stale, keeping the tap and bars running
- **What:** `NowPlaying.swift:65-100`. Play state comes only from distributed notifications. Nothing resets it when the player app quits or relaunches, and there is no reconciliation.
- **Why it matters:** a stale "playing" keeps the audio tap and the 30 fps bars running forever (1.2% CPU, plus coreaudiod work, plus a sleep-prevention assertion).
- **Evidence (unconfirmed):** at 12:30 Notch showed "Creep" with a pause button (meaning it thought Spotify was playing) while every Spotify process was at 0.0% CPU. I couldn't check Spotify's real state without AppleScript.
- **Fix idea:**
  - Observe `NSWorkspace.didTerminateApplicationNotification` for the two bundle IDs, and `clear()` when the current source quits.
  - Optionally re-run `refresh(source)` when the panel opens.
- **Size and risk:** S (15 min). Low risk.

### 3. Equalizer rebuilds 4 CGColors on every frame
- **What:** `Equalizer.swift:171-178`. `render` calls `CGColor(srgbRed:…)` and sets `cornerRadius` and `backgroundColor` on each of the 4 bars every frame, even though the colour only changes during a 0.4 s fade.
- **Why it matters:** this is the largest part of the per-frame cost in the closed-and-playing state. The equalizer is the only thing that runs for hours.
- **Evidence:** `sample` shows `CGColorCreateSRGB` and its ColorSync work as the biggest piece under `BarsView.tick`.
- **Fix idea:** cache the CGColor and set colour and corner radius only when they change (on a fade or a config update). Each frame then only updates the bar frames.
- **Size and risk:** S (10 min). Low risk.

### 4. AppleScript can launch a player that has quit
- **What:** `NowPlaying.swift:52-56` (seek), `:135-140` (fetchPosition) and `:142-160` (fetchArtwork) send `tell application "Spotify/Music"` without the `isRunning` guard that `command()` has.
- **Why it matters:** if the source app has quit but Notch still holds it (finding 2), dragging the progress bar or a track-change notification relaunches Spotify or Music.
- **Evidence:** code reading. The guard exists only in `command()`.
- **Fix idea:** put the `isRunning` guard inside `run()`, or in each caller. One guard in a shared place is the smaller diff.
- **Size and risk:** S (10 min). Low risk.

### 5. `build.sh` quits the installed app on every build
- **What:** `build.sh:7` runs `pkill -x Notch`, which kills /Applications/Notch.app too, not just the build/ copy.
- **Why it matters:** every test build silently quits the human's daily app. Then they have no notch until they relaunch it.
- **Evidence:** code reading. The process name is the same for both copies.
- **Fix idea:** kill only the build/ copy: `pkill -f "$PWD/build/Notch.app"`.
- **Size and risk:** S (5 min). Low risk. (Needs Pam's OK, because build.sh is outside the code boundary.)

### 6. Audio tap setup and teardown run on the main thread
- **What:** `NotchModel.swift:38` calls `audio.setActive` from a Combine sink on the main thread. `AudioTap.setUp()` creates the tap and the aggregate device and starts IO synchronously (`AudioTap.swift:36-74`).
- **Why it matters:** creating an aggregate device can block for tens of milliseconds. It happens right when play is pressed, which can make the panel's play/pause animation hitch.
- **Evidence:** code reading. Not timed.
- **Fix idea:** run start and stop on the tap's own serial `queue` (it already exists).
- **Size and risk:** S (15 min). Low risk, but keep `procID` access on that one queue.

### 7. Audio tap doesn't recover when the output device changes or after sleep and wake
- **What:** `AudioTap.swift:51-61` binds the aggregate device to the output device that was the default when playback started. Nothing listens for `kAudioHardwarePropertyDefaultSystemOutputDevice` changes or for wake.
- **Why it matters:** after switching to AirPods or an HDMI display, the bars may freeze or go silent until the next pause and play.
- **Evidence:** code reading. Not reproduced (that needs the human's headphones).
- **Fix idea:** add a property listener on the default output device, plus `NSWorkspace.didWakeNotification`, that stops and restarts the tap while it's active.
- **Size and risk:** M (30 min). Medium risk: test with AirPods.

### 8. `gotSignal` never resets
- **What:** `AudioTap.swift:13`, `:109`. Once real audio has arrived, the app trusts the tap for the rest of the process's life.
- **Why it matters:** if audio permission is revoked later, or the tap breaks (finding 7), the bars sit flat with no fallback to the simulated signal.
- **Evidence:** code reading.
- **Fix idea:** reset it in `stop()`.
- **Size and risk:** S (2 min). Low risk.

### 9. Dead or unused code
- **`NowPlaying.album`** (`NowPlaying.swift:16`) is `@Published` but never shown. It is used only in the track key. Make it a plain local.
- **`Appearance.symbol`** (`Settings.swift:9-15`) and the `Label(..., systemImage:)` in the Appearance picker: spec v1.1 says text only, because macOS segmented pickers drop the image. Replace the Label with `Text`.
- **Settings and now-playing app lookups:**
  - `Settings.swift` `musicRow` calls `Shortcut.url()` (a LaunchServices lookup) on every body render.
  - `@AppStorage("musicApp")` re-evaluates `Shortcut.defaultMusicApp` on every `NowPlayingCard` init. Cheap, but avoidable.
- **The `NOTCH_SELFCHECK` and `NOTCH_HIVE_ROOT` env hooks** are deliberate test hooks: keep them.
- **Size and risk:** S (15 min total). Low risk.

### 10. Progress timeline ticks while paused
- **What:** `NotchViews.swift:242`. `TimelineView(.periodic(by: 0.5))` redraws twice a second while the panel is open, even when paused.
- **Why it matters:** small. It only runs while the panel is open.
- **Evidence:** part of the 0.9% open-panel figure. Not separated out.
- **Fix idea:** `.periodic` when playing, `.explicit([])` when paused.
- **Size and risk:** S (5 min). Low risk.

## Not measured
- Open panel with **real** music on the running app: that needs the human's cursor over the notch. The test copy's simulated equalizer stands in for it.
- Whether finding 2 really happened: it needs a second look at Spotify while the notch shows "playing".

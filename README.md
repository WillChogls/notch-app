# Notch

A native SwiftUI "Dynamic Island" for the MacBook notch, inspired by Alcove and Notchy.
Works on Macs without a notch too (draws a pill at the top of the screen).

## Build & run

```bash
./build.sh run       # builds build/Notch.app (ad-hoc signed) and launches it
./build.sh install   # same, then installs to /Applications/Notch.app and launches that
```

Settings (menu bar capsule › Settings…, or launch Notch again from Spotlight): panel opacity,
light/dark/system appearance, open at login (on by default after first launch).

Requires macOS 14+ and the Swift toolchain (Command Line Tools is enough; Xcode not required).
Quit from the capsule icon in the menu bar.

## What works (v0.1)

- Notch-shaped black panel that matches the hardware notch, springs open on hover, closes on exit
- **Live activities** in the closed notch: album art + equalizer bars while music plays; charging pill on plug-in
- **Now Playing** (Music & Spotify): artwork, title/artist, scrubbable progress, play/pause/next/previous,
  accent color pulled from the artwork
- **Calendar widget**: date, time and week strip
- **File shelf**: drag files onto the notch to stash them, drag them back out, double-click to open,
  AirDrop all, persists across relaunches
- Battery level in the header

The first time you use playback controls, macOS asks for Automation permission for Music/Spotify.
Because builds are ad-hoc signed, macOS may ask again after a rebuild.

## Roadmap (from Alcove / Notchy feature lists)

- [ ] Volume / brightness HUD replacing the system HUD (needs a CGEventTap + Accessibility)
- [ ] Swipe gestures between tabs, settings window, launch at login
- [ ] EventKit calendar events and reminders
- [ ] Timers / Pomodoro, Focus mode indicator, camera/mic privacy indicator
- [ ] Clipboard history, quick notes, download alerts, AirPods battery
- [ ] Real audio visualizer (ScreenCaptureKit audio tap), synced lyrics (LRCLIB)
- [ ] Lock screen widgets
- Excluded: Face Unlock

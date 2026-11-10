<img src="Resources/readme/banner-dark.png" alt="Notch: your MacBook notch, made useful. The open panel shows now playing and the Office widget.">

<p align="center">
  <img src="Resources/readme/badge-macos.svg" alt="macOS 14+">
  <img src="Resources/readme/badge-swift.svg" alt="Swift 5.10">
  <img src="Resources/readme/badge-ui.svg" alt="SwiftUI">
  <img src="Resources/readme/badge-deps.svg" alt="No dependencies">
</p>

<p align="center">
  Music, live widgets and a file shelf in a liquid glass panel that grows out of the notch.<br>
  Native SwiftUI, no dependencies.
</p>

<p align="center">
  <a href="#features"><b>Features</b></a> ·
  <a href="#install"><b>Install</b></a> ·
  <a href="#permissions"><b>Permissions</b></a> ·
  <a href="#settings"><b>Settings</b></a>
</p>

<img src="Resources/readme/closed-open-dark.png" alt="Side by side: the closed notch with album art and equalizer bars, and the same notch opened into the full panel">

## Features

<h3 align="center">🎵 Now playing, with bars that hear the music</h3>
<p align="center">
  Spotify and Apple Music. Artwork, a scrubbable timeline, and shuffle and repeat that light up in your accent colour when on.<br>
  If macOS blocks access to the player, a lock button takes you to the right Privacy setting.<br>
  The bars follow the real audio, in the album's colour, and cost nothing while paused.<br>
  Plug in, and the closed notch shows a charging pill too.
</p>

<img src="Resources/readme/live-dark.gif" alt="The closed notch with album art on the left and four equalizer bars moving to the music on the right">

<h3 align="center">🧩 One widget, your pick</h3>
<p align="center">
  <b>Office</b> shows your agents live in Munder Difflin, an agent management app. More in the <a href="#office-tab">Office tab</a>.<br>
  Or choose <b>Calendar</b>, <b>Clock</b> or <b>Weather</b> for your city. Only the one you pick runs.
</p>

<img src="Resources/readme/feature-widgets-dark.png" alt="The four widgets side by side: Office, Calendar, Clock and Weather">

<a id="office-tab"></a>
<h3 align="center">🏢 The Office tab</h3>
<p align="center">
  A third tab for the whole floor: <b>Agents</b> and what each is doing, your Claude <b>Session (5 h)</b> and <b>Weekly</b> limits, and <b>Ask me</b> for questions waiting on you.<br>
  The limit bars turn red-orange from 80%, and old numbers are marked stale in amber.<br>
  The refresh arrow re-reads them and checks the setup, then says what it found: updated, up to date, or what to fix.<br>
  An orange badge on the tab counts those questions. A pixel pet beside the tabs shows the mood:<br>
  a <b>!</b> when something needs you, tired at 90% of a limit, hopping while agents work, idle when all is quiet, asleep when Munder Difflin is closed.
</p>

<img src="Resources/readme/feature-office-dark.png" alt="The Office tab: agents and what each is doing, Session and Weekly usage limits with the refresh arrow, an Ask me question, the orange question badge and the pixel pet">

<h3 align="center">📥 A shelf for files in transit</h3>
<p align="center">
  Drop files on the notch, drag them out where you need them, or AirDrop them all at once.<br>
  Hover a file for its X, or Clear the lot.<br>
  The shelf survives relaunches.
</p>

<img src="Resources/readme/feature-shelf-dark.png" alt="The shelf tab holding three files, one hovered with its remove X, plus AirDrop and Clear buttons">

<h3 align="center">↗️ One click to your apps</h3>
<p align="center">
  Buttons open your music app or Munder Difflin, using their real icons. They hide when an app isn't installed.
</p>

## Install

```bash
git clone https://github.com/WillChogls/notch-app.git
cd notch-app && ./build.sh install
```

Notch builds, copies itself to `/Applications` and launches. It lives in the menu bar: click its capsule for **Settings…** and **Quit**.

<details>
<summary><b>Requirements</b></summary>
<br>

- macOS 14 Sonoma or later. macOS 26 gives the full Liquid Glass look; 14–15 use a frosted fallback.
- The real-audio equalizer needs macOS 14.2+; older systems show a simulated beat.
- The Swift toolchain. Command Line Tools is enough (`xcode-select --install`); Xcode is not needed.
- Any Mac works. Without a notch, Notch draws a pill at the top of the screen.

</details>

<details>
<summary><b>Build commands</b></summary>
<br>

| Command | What it does |
|---|---|
| `./build.sh` | Builds `build/Notch.app` (ad-hoc signed) |
| `./build.sh run` | Builds and launches it from `build/` |
| `./build.sh install` | Builds, installs to `/Applications` and launches |

</details>

<details>
<summary><b>Office tab limits: setup and repair</b></summary>
<br>

The Limits card reads `hive/usage-limits.json`. Munder Difflin's status line saves it on every agent reply once the patch in `scripts/` is applied to its hook. From this folder (the hive lives in `~/office`):

```bash
patch -d ~/office -p1 -R -s -f --dry-run < scripts/cth-hook-limits.patch >/dev/null 2>&1 || patch -d ~/office -p1 -N < scripts/cth-hook-limits.patch
```

It applies the patch only when it is missing, so running it again changes nothing. A Munder Difflin restart or update can replace the hook and drop the patch. The card then turns **stale** (an amber "2 d ago · /usage") instead of updating, and the card's refresh arrow says "Hook patch missing"; run the command again.

Without the live file, Notch falls back to the last `/usage` numbers in `~/.claude.json`, always marked stale. It reads only the `cachedUsageUtilization` key, and never touches the Keychain or the network.

</details>

<details>
<summary><b>Limits card: keeping the hook patch alive</b></summary>
<br>

Munder Difflin rewrites its hook when it starts, spawns an agent or saves tasks, which drops the patch. A small LaunchAgent (a background job run by macOS) puts it back each time the hook changes. It doesn't poll, and it doesn't use the network or `sudo`.

1. Install, from this folder:
   ```bash
   scripts/install-limits-watcher.sh install
   ```
2. Check `~/Library/Logs/notch-limits-patch.log`. Each rewrite adds one `APPLIED` line. A `REFUSED` line means the hook no longer looks as expected, so it was left alone and the card goes stale. A single `REFUSED: no hook` just before an `APPLIED` line is harmless: the hook was briefly deleted while being rewritten.
3. Uninstall:
   ```bash
   scripts/install-limits-watcher.sh uninstall
   ```

The watcher runs the script from this folder, so uninstall it before you move or delete the folder. Remove the watcher once Munder Difflin saves the limits itself.

</details>

## Permissions

Notch asks for each permission only when a feature first needs it, and records nothing.

<details>
<summary><b>What it asks for, and why</b></summary>
<br>

| Permission | Asked when | Why |
|---|---|---|
| **Automation** (Music / Spotify) | Notch first sees Spotify or Music playing | To read the track and artwork, and to play, skip, shuffle and repeat |
| **Audio capture** | Music first plays while Notch runs | To listen to the music app only, so the bars move with it. Nothing is recorded or saved. |
| **Location** | You first pick the Weather widget | City-level, for the forecast (weather from [Open-Meteo](https://open-meteo.com)) |

Builds are ad-hoc signed, so macOS may ask again after you rebuild.

</details>

## Settings

<img src="Resources/readme/feature-settings-dark.png" alt="The Notch Settings window with Panel and General cards">

<p align="center">
  Panel opacity and size · Music app · Widget · Open at login
</p>

<br>

<p align="center">
  <sub>Swift and SwiftUI, no third-party packages: Liquid Glass via <code>glassEffect</code>, Core Audio process taps for the equalizer, Core Location with Open-Meteo for weather.<br>
  Design specs for every part of the app live in <a href="Resources/design"><code>Resources/design/</code></a>.</sub>
</p>

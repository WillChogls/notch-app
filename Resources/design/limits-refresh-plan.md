# OFF-21 plan: Limits card refresh button

Next action: god approves option (a)+diagnosis (2 min), then sends the Oscar brief.

## 1. What "refresh" can honestly do
The numbers change only when Claude Code sends a statusline payload (after an agent replies) or when /usage is opened (`~/.claude.json` cache). Notch already re-reads `usage-limits.json` every 5 s while the tab is visible, so a plain re-read would nearly always show the same numbers. (Today the live file has only a `seven_day` window: the payload includes only the windows Claude Code reports.)
- **(a) re-read now + clear feedback:** cheap, honest, but alone it feels broken when nothing changes.
- **(b) check the chain and repair:** useful part = DIAGNOSE (hook patched? watcher loaded? file age). The REPAIR part (running `apply-limits-patch.sh` from Notch) makes Notch write into the hive and spawn processes; the watcher already self-heals. Not recommended.
- **(c) fresh numbers without Keychain, OAuth or network: none exists.** The only way to force a payload is to make an agent reply (costs tokens, not Notch's job). Running `claude` headless to refresh the /usage cache would use the human's login and the network: out of scope, human's call if ever wanted.

## 2. Recommendation: (a) + read-only diagnosis (about 1 h in total)
On click: re-read both sources now (usage-limits.json and the `~/.claude.json` key), run 3 read-only checks, and show ONE honest result line for 3 s:
| Result | When | Text |
|---|---|---|
| Updated | numbers or timestamp changed | "Updated just now" |
| Up to date | same data, file fresh (under 30 min) | "Up to date. Last agent update 4 m ago" |
| Waiting | file older than 30 min, chain OK | "No new data: limits update when an agent replies" |
| Hook missing | cth-hook.cjs lacks the marker `Notch (OFF-18)` | "Hook patch missing. Run scripts/apply-limits-patch.sh" |
| Watcher off | LaunchAgent `dev.notch.limits-patch` not loaded (launchctl print, read-only) | "Watcher not loaded. Run scripts/install-limits-watcher.sh install" |
| Failed | file unreadable / bad JSON | "Can't read limits file" |
No repair, no writes, no network, no Keychain. Checks run only on click (one `launchctl` spawn, one 3 KB file read).

## 3. Brief for Oscar (about 10 min)
- **Where:** the Limits card's header, trailing slot (16pt button slot in WidgetHeader), next to the title.
- **Look:** SF Symbol `arrow.clockwise`, 11pt, plain style, 24pt hit area, same hover/press as the other small buttons (idle 0.5, hover 1.0 + faint circle, press 0.92). Tooltip "Refresh limits"; VoiceOver "Refresh limits".
- **States:** idle; spinning (one full rotation or continuous until done, minimum 0.6 s so it is visible; Core Animation; Reduce Motion: no spin, button dims instead); result line replacing the "Updated Xm ago" footer for 3 s then returning: success (check mark, orange-neutral), up to date (grey), warning (orange triangle + the reason from the table), failed (red-orange). The reason must fit 150pt: two lines max, copy-friendly command in the tooltip.
- Colour: Claude orange accent only for the spinner/active; no new hues. Dark only.

## 4. Build steps for Jim (about 45 min)
1. `UsageLimits.diagnose()` (pure, testable): inputs = file age/parse result, hook-has-marker (read `hive/bin/cth-hook.cjs`, search marker), watcher-loaded (run `/bin/launchctl print gui/<uid>/dev.notch.limits-patch`, exit code 0 = loaded; off the main thread; 2 s timeout); output = the enum above.
2. Refresh action: re-read both sources, compare with the previous value, run diagnose, publish a transient result for 3 s.
3. Button + result line in LimitsCard per Oscar's spec; Reduce Motion handled.
4. Self-check for the decision table (each row) with fake inputs.
5. No writes anywhere, no network. Build to build/ only; send to Dwight.

## 5. Test items for Dwight
1. Click with fresh data unchanged: spins at least 0.6 s, then "Up to date. Last agent update Xm ago", returns to the footer after about 3 s.
2. Change usage-limits.json in a test hive copy: click: "Updated just now", bars change.
3. File 2 h old (touch -t): "No new data: limits update when an agent replies".
4. Remove the marker from a COPY of the hook: "Hook patch missing" with the command; restore: gone.
5. `launchctl bootout` the watcher (re-install after): "Watcher not loaded" with the install command.
6. Bad JSON in the file: "Can't read limits file", no crash.
7. Reduce Motion on: no spin, still clear feedback.
8. Hammer-click 10 times: one check at a time, no queued spawns, no leftover `launchctl` processes.
9. No file in the hive modified (mtimes), no network (no connections from the app), no Keychain access.
10. Idle CPU about 0 with the tab closed; music uninterrupted.

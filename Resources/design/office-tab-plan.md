# OFF-17 plan: third tab "Office" (Munder Difflin overview)

Next action: god approves scope (2 min), then sends section 4 to Oscar.

## 1. Scope
**In (read-only, dark only, Liquid Glass):**
1. Agents: every agent in fleet.json: state (working / idle / blocked / paused / breaker), what it is doing now, last active ("2m ago").
2. Workload: tasks.json cards grouped by status (doing, blocked, todo; last 3 done) with id, title, assignee.
3. ASK ME: open humanQA questions (entries with no `a`): task id, who asked, question text, age.
4. Three small extras (cheap, already in fleet.json): cost and tokens per agent plus a floor total; inbox backlog badge per agent; header line "N need you / N working".

**Out:** answering ASK ME from the notch (it would WRITE tasks.json; the hive stays read-only); log.jsonl event feed; inbox/outbox browsing; token charts; context % (not in fleet.json, I checked); done-task history beyond 3; any change to music.

**Home card:** keep it. Home's widget slot stays (default Office). The tab is the full view, the card is the glance. Both share one data layer.

## 2. Data sources
| Section | File | Fields |
|---|---|---|
| Agents | fleet.json | name, role, breaker, onHold, lastTool, lastActiveSecAgo, inboxBacklog, tokens, usd; floor total = sum |
| Agent state | log.jsonl tail (existing rule in Office.swift: turn start newer than turn end = working) | already built |
| Doing text | tasks.json | doing/blocked card per assignee, else "Active - <lastTool>", else Idle |
| Workload | tasks.json | id, title, status, assignee; statuses seen: todo, doing, blocked, done |
| ASK ME | tasks.json | humanQA[] where `a` is missing: q, from, askedAt |
Rules reused from Office.swift: offline if fleet.json missing or ts older than 2 min; bad tasks.json keeps fleet rows.

## 3. Data layer and performance
- Extend the existing Office store (Office.swift); no second poller. Add: all tasks (not only doing), open humanQA, usd/tokens.
- Refresh once when the Office tab is shown, then every 5 s ONLY while the tab is visible and the panel is open; skip parse when file mtimes are unchanged; parse off the main thread. Switching to Home or Shelf, or closing the panel, stops it. CPU about 0 closed.
- Pulses via Core Animation (existing PulseDot). No timers per row. Never touches the audio tap or NowPlaying.

## 4. Layout brief for Oscar
Open panel, new third tab (icon e.g. person.3 or building.2; tooltip "Office"). Dark only, same glass cards (radius 16, padding 10) as Home.
- Header: "Office", summary ("2 need you . 3 working"), floor cost total.
- Three columns or stacked cards (your call, panel width about 480pt): Agents | Workload | ASK ME.
- Agents: one 18-20pt row each (mark + name + doing, truncated; cost on hover or right-aligned small), backlog badge, red/orange for breaker/blocked; sort as in office-overview-spec.
- Workload: status groups with counts (Doing 1, Blocked 0, Todo n, Done 3 collapsed to last 3); card row = id, title (1 line), assignee initial.
- ASK ME: question list, newest first, each 2 lines + who + age; orange count badge on the tab icon when open questions exist; empty state "Nothing waiting on you" (calm).
- States: offline ("Office offline"), empty, loading after 0.5 s, overflow ("+N more", no scroll unless you decide otherwise).
- Hover tooltip with full text; VoiceOver labels; Reduce Motion; no light variants.

## 5. Build steps for Jim (about 2 h)
1. Add `.office` to NotchModel.Tab and the tab bar button (icon, tooltip, VoiceOver, badge hook).
2. Extend Office.swift store: tasks list, open humanQA, usd/tokens/backlog; keep existing state rules; refresh only while the Office tab is visible.
3. New OfficeTab.swift: header, Agents, Workload, ASK ME views per Oscar's spec; reuse row/dot views from OfficeCard.swift.
4. Orange badge on the tab icon = open ASK ME count.
5. Self-check for the new parsing (open humanQA = no `a`; grouping by status; missing/bad file).
6. Build to build/ only; send to Dwight (no install, no commit).

## 6. Test checklist for Dwight
1. Third tab appears; Home and Shelf unchanged; panel size unchanged.
2. Agents section matches fleet.json (names, states, doing text); an idle agent reads Idle after its turn ends.
3. Workload counts match tasks.json by status; assignees right; last 3 done only.
4. ASK ME shows exactly the humanQA entries with no `a`; adding one in a copy of tasks.json shows within 5 s; badge count matches; empty state when none.
5. Hive folder renamed: "Office offline", no crash; garbage tasks.json: fleet rows still show.
6. Panel closed or on another tab: CPU about 0 (Activity Monitor), no file reads (check with fs_usage or logging).
7. Music playing during all of it: no stutter, equalizer and controls unaffected.
8. Dark only with macOS in Light; text readable; Reduce Motion on.
9. The notch never writes to the hive (check mtimes of tasks.json and fleet.json unchanged by the app).

# OFF-18 addendum: session + weekly limit card (replaces the token chart)

Next action: god decides 2 questions (2 min). Without them the card ships in "unavailable" mode, and nothing else is blocked.

## 1. Finding: no exact, FRESH source is on disk today
| Candidate | Result |
|---|---|
| `~/.claude.json` key `cachedUsageUtilization` | Has exactly /usage's data: `utilization.five_hour` and `utilization.seven_day`, each `{utilization: %, resets_at: ISO time}`, plus `fetchedAtMs`. **But stale:** fetched Nov 7 12:50, five_hour reset Nov 7 17:29, seven_day reset Nov 9 10:59; both already passed. Claude Code refreshes it only when /usage is opened. |
| Statusline input (`rate_limits.five_hour / seven_day` with `used_percentage` and `resets_at`, added in Claude Code and fixed after-reset in later versions; seen in the changelog) | **Exact and fresh** (updated on every turn of any running Claude Code session), but it is only passed to a statusline command on stdin; nothing saves it. The hive's statusline command is `bin/cth-hook.cjs --status` (Munder Difflin's); it does not store `rate_limits` (grep: none). |
| `cost-ledger.jsonl` (hive) | Cannot give a percent: the plan limit is unknown. Only honest as raw token counts. Rejected for this card. |
| Anthropic usage endpoint with the OAuth token | **NOT used.** Forbidden by your rule; flagging only so it is a visible option. Not recommended. |
| `stats-cache.json`, telemetry, sessions | No limit data (stats-cache stops at 2026-09-21). |

## 2. Recommended source (two parts)
**A. Primary (exact, fresh): capture the statusline's `rate_limits` to a file.** Extend the statusline command (the hive hook `cth-hook.cjs --status`, or a one-line wrapper that tees stdin to the file and then runs the original command) to write `{ts, rate_limits}` atomically to `/Users/willwhite/office/hive/usage-limits.json` when it changes. The office agents run all day, so it stays fresh. Notch only reads that file (read-only, no credentials). **Needs god / the human:** it is a change to the Munder Difflin hook (or to settings.json, which I cannot edit). I have NOT verified the exact payload shape (percent as 0-100 or 0-1; `resets_at` ISO or epoch): the first step is to dump one real payload; Notch must accept both.
**B. Fallback (already on disk, may be stale): `~/.claude.json` `cachedUsageUtilization`.** Read ONLY that one key (not the file's other contents, no logging). Staleness rule: if `fetchedAtMs` is older than 1 h show "Updated 2 d ago" in grey; if `resets_at` is already past, show "Resets passed - open /usage to refresh" instead of the old percent. This is a personal config file (it also holds account details, not the OAuth token), so it needs the human's OK.
**C. Else:** the card says "Usage unavailable" with a calm hint.

## 3. Fields and refresh rule
Fields: `five_hour.used_percentage` (session, 5 h window), `five_hour.resets_at`, `seven_day.used_percentage` (weekly), `seven_day.resets_at`, plus the file's own timestamp.
Refresh: while the Office tab is visible, stat the file on the existing 5 s tick (mtime gate); re-parse only on change. Remaining time ("resets in 2 h 10 m") is computed locally once a minute (`TimelineView(.everyMinute)`, no file read). If now is past `resets_at`, show 0% "resetting" rather than the old percent. Label every value "Updated Xm ago". Never writes anywhere; no network.

## 4. Brief for Oscar (about 15 min)
Middle card of the Office tab: two meters, Claude look (orange accent, warm neutrals, dark glass).
- Two rows: "Session (5 h)" and "Weekly", each a rounded bar (orange fill, thin track), big percent, "resets in 2 h 10 m" (weekly: "resets Mon 11:00").
- Colour steps: below 70% orange, 70-90% deeper orange, over 90% red-orange; not colour-only (percent is always shown).
- States: live; stale ("Updated 2 d ago", dimmed); past reset ("Resetting..."); unavailable ("Usage unavailable" + one-line hint); loading after 0.5 s. VoiceOver reads "Session 25 percent used, resets in 2 hours".
- Pet tie-in (optional): critter gets sleepy above 90%.
- Same card frame, radius 16, padding 10; no animation except a 0.2 s bar fill; Reduce Motion = none.

## 5. Build steps for Jim (about 1 h, after the rest of v2)
1. `UsageLimits` store: read `usage-limits.json` (A), else the one key from `~/.claude.json` (B, only if approved), else unavailable. Accept percent as 0-100 or 0-1 and `resets_at` as ISO or epoch. Mtime-gated, off-main, only while the tab is visible.
2. Card view per Oscar; remaining time from a once-a-minute timeline.
3. Self-check: parse both shapes, past-reset rule, stale rule, missing/bad file = unavailable.
4. Does not read the Keychain or `~/.claude/.credentials*`; no network. Build to build/ only; send to Dwight.
5. (Separate, god/hive owner) the statusline capture in A, with an atomic write.

## 6. Test items for Dwight
1. Write a sample `usage-limits.json` (25% / 15%, resets in 2 h / 3 d): bars, percents and "resets in" match; edit the file, the card updates within 5 s.
2. Percent given as 0.25 and as 25: both show 25%.
3. `resets_at` in the past: shows "Resetting", not the old percent.
4. File missing and fallback off: "Usage unavailable", no crash; garbage JSON: same.
5. Stale file (timestamp 2 days old): dimmed with "Updated 2 d ago".
6. `grep` the source: no Keychain, no `.credentials`, no `URLSession` to Anthropic; check with `lsof`/Little Snitch-style check that the app makes no network call for this card.
7. CPU about 0 with the tab hidden or the panel closed; music uninterrupted.
8. Dark only; contrast OK on orange; Reduce Motion works.

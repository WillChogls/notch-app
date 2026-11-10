# OFF-18 plan: token graph + Claude look (Office tab v2)

Next action: god approves 3 choices below (2 min), then sends section 4 to Oscar.

## 1. Data source for tokens per day: `cost-ledger.jsonl` (hive root)
I checked all candidates.
| Source | Verdict |
|---|---|
| `cost-ledger.jsonl` | **PICK.** Append-only, one row per usage snapshot: `agent_id, session_id, ts, input, output, cache_read, cache_creation, usd, model`. Rows are CUMULATIVE per session (last Jim row: usd 55.03 and 121.8M tokens = exactly fleet.json). Covers 2026-11-05 to now, 756 rows, 166 KB. |
| `token-usage.json` | Rejected. 15-minute buckets, but only about 1-3M tokens per agent vs 11-122M in fleet.json (counts a different, smaller thing). |
| `fleet.json` | Running totals only. |
| `log.jsonl` | No token fields. |
| `~/.claude/projects/*/*.jsonl` transcripts | Rejected. Not the office's (mixed with every other project), huge, needs a rescan and a path guess per agent. |

**Per-day rule:** per `session_id`, sort by `ts`; each row adds `total(row) - total(previous row of that session)` to the local calendar day of that row. `total = input + output + cache_read + cache_creation` (same definition as fleet.json `tokens`). If the total drops (1 case in the file), count the row's total as new. I tested: the sum is 255.0M vs 248.6M in fleet (the gap is the one reset, and sessions that ended). Per day: Nov 5 37.1M, Nov 6 30.6M, Nov 7 24.9M, Nov 8 95.2M, Nov 9 67.3M so far.
Note: about 97% of tokens are cache reads. The bar shows total tokens (matches the per-agent column on the tab); the tooltip splits out in+out vs cache and shows the day's USD.

## 2. Decisions for the human (my pick first)
1. **Stacked per agent** (my pick), not one office total: 7 bars, each split by agent, so you see who burns tokens. Tooltip gives the exact numbers. Total-only is simpler if you prefer.
2. **Days with no data:** before the first ledger row (Nov 3-4 today) draw a faint dashed stub labelled "no data", not an empty bar. A day after logging began with 0 tokens draws a thin solid baseline. Today's bar is lighter with "so far".
3. **Workload card goes.** The blocked count moves into the header summary ("2 need you . 1 blocked . 3 working"). Doing/blocked card titles still feed each agent's "doing" line. The ASK ME card stays.

## 3. Performance
- Parse the ledger incrementally: keep the byte offset, per-session last total, and per-day-per-agent sums in memory. Only new bytes are read. If the file is smaller than the offset (rotated), rebuild once.
- Read only while the Office tab is visible and the panel open, on the 5 s tick, gated on file size; off the main thread. First read of today's file is about 1 ms.
- Per-day sums cached in memory; nothing is rescanned every 5 s. No transcripts touched. Never writes to the hive.

## 4. Brief for Oscar (about 25 min)
Redesign the Office tab (dark only, glass cards as before) to feel like Claude: warm, calm, a little playful.
- **Colour:** Claude orange as the accent (about #D97757, tune for contrast on dark glass), warm off-white text, warm greys. Keep semantic state colours (green working, orange-red blocked, red breaker) readable next to the orange.
- **Graph card (replaces Workload):** 7-day bar chart, day labels (Mon..Sun), stacked per agent (palette of orange tints plus warm neutrals, not 5 clashing hues), thin baseline, today lighter ("so far"), no-data stub, Y max label, tooltip on hover (day, total, per agent, USD). Cheap to draw (Canvas or plain shapes), no per-frame work.
- **Pet:** an ORIGINAL pixel critter mascot, in the spirit of a friendly terminal mascot, drawn on a pixel grid (about 12x12 to 16x16 cells), flat orange with two eyes. Do NOT copy or trace Anthropic's mascot, logo or wordmark; this repo is public. Idle: slow blink or breathing (Core Animation, a few frames, near-zero CPU). States: working = small bounce, idle = sleepy eyes, blocked on human = a small "!" bubble. Where: header corner of the tab. Reduce Motion = static.
- **Rest of tab:** Agents card and ASK ME card restyled to match (type, spacing, radius 16); header: pet + "Office" + summary + floor cost; keep all states (offline, empty, loading, overflow) and VoiceOver labels.
- Deliver a spec file and the pet as a drawn pixel grid (data in code, no image asset needed) so Jim can render it with Canvas.

## 5. Build steps for Jim (about 2 h)
1. Remove the Workload card (view and its data).
2. Add `TokenUsage` store in Office.swift: incremental ledger parser per section 1 and 3; output `[Day: [agent: tokens]]` for the last 7 local days plus USD per day; unit self-check (cumulative to delta, reset case, day boundary, missing file, bad lines skipped).
3. New `TokenChart` view per Oscar (stacked bars, no-data stub, today lighter, tooltip).
4. `PixelPet` view (grid as data, Canvas or CALayer, states and Reduce Motion per spec); drive its state from the Office summary (working / idle / blocked).
5. Restyle Office tab (orange accent, header with pet, summary incl. blocked count).
6. Build to build/ only; send to Dwight (no install, no commit).

## 6. Test checklist for Dwight
1. Tab shows graph (7 bars), Agents and ASK ME cards; Workload gone; Home and Shelf unchanged.
2. Numbers: compute per-day tokens from cost-ledger.jsonl with a script (delta rule above); each bar equals it within 1%; the 5 daily totals above match.
3. Nov 3-4 (before logging) show the "no data" stub, not 0; today is lighter.
4. Stack colours = right agents; tooltip total, per-agent and USD correct.
5. Append a fake row to a COPY of the ledger (hive path override env): today's bar grows within 5 s without a full rescan (log or timing).
6. Header: blocked count matches tasks.json; "N need you" still counts blocked + open ASK ME.
7. Pet: draws crisp (no blur) at 1x and 2x, changes with agent state, still under Reduce Motion, is not any Anthropic asset (eyeball against Oscar's spec and confirm no image files added).
8. Ledger missing or garbage: tab shows "No usage data", no crash; fleet rows still show.
9. CPU about 0 with the panel closed or on another tab; music uninterrupted; app never writes to the hive.
10. Dark only with macOS in Light; text contrast on orange passes.

# Office tab v2, design spec v1.1 (OFF-18)

> **v1.1 (2026-11-09):** the token chart is cancelled. The middle card is now the Limits card (section 4). Ignore the stack palette (section 2) and the Agents row swatch (section 6); both are cut.

Mockup: `office-tab-v2-mockup.png`. Plan: `office-tab-v2-plan.md`. This file replaces `office-tab-spec.md` (OFF-17) wherever the two differ. The app is dark only and the panel size is unchanged (content area 534×138pt). Mockup source: Oscar's `mock/officetab2.swift`, which contains every value below as code.

## 1. Layout
```
[tabs 🏠 📥 🏢(badge)] [pet]        (notch)              [82% 🔋]   ← tab bar, 32pt
Office   2 need you · 1 blocked · 2 working          $55.03 spent  ← summary row, 16pt
┌ Agents 180 ┐ ┌ Limits 188 ┐ ┌ Ask me 150 ┐              ← cards, 116pt high
```
- The content area is a `VStack(spacing: 6)`: the summary row, then `HStack(spacing: 8)` with the cards Agents, Limits and Ask me. The Workload card is removed.
- Cards keep the same container: `.padding(10)`, radius 16 continuous, glass. The pre-26 fallback is tinted warm: fill `ink` at 0.07, stroke `ink` at 0.12, 0.5pt.
- Inside each card: a 14pt header, then content in `VStack(spacing: 2)`. Inner height is 96pt, so the Agents card shows **4 rows** (3 plus "+N more" when there are more).
- The panel scale setting scales the three card widths proportionally.

## 2. Colour tokens (new, Office tab only)
| Token | Hex | Use |
|---|---|---|
| `clay` | #D97757 | Accent: "need you", the tab badge, "N open", today's label and outline, the pet body. On #1A1A1A glass it measures about 5.6:1, so it is fine for 10pt+ text. |
| `ink` | #F4EFE6 | Warm off-white primary text |
| `ink2` | ink at 0.62 | Secondary text, card titles |
| `ink3` | ink at 0.42 | Tertiary: meta lines, day labels, "+N more", idle marks |
| `amber` | #F0B54A | Blocked or needs you (agent rows, the "N blocked" count, the pet's bubble) |
| `green` | system green | Working |
| `red` | system red | Breaker |

- **Amber, not orange, for blocked:** blocked moves from `.orange` to amber because `.orange` sits too close to clay to tell them apart.
- ~~**Stack palette:**~~ (cut in v1.1) ranked by each agent's 7-day total, highest first. Each agent keeps its colour across all 7 bars and in its Agents row swatch.
  - #D97757, #E8A27F, #B5583A, #CDBFAE, #8E8378.
  - Agent 6 and beyond: "Other" #5C554F, merged into one segment.

## 3. Tab bar and summary row
- **Badge:** same geometry as OFF-17. The fill is now `clay` and the text is #1A1410, system 9 bold.
- **Pet:** sits in the left wing, 8pt after the last tab, 28×24pt (2pt cells). The wing has about 80pt free before the notch. It shows on the Office tab only. `.help` reads "Office: 2 need you", matching the summary.
- **Summary row (16pt):**
  - "Office" in system 12 semibold `ink`, then 3 spaces.
  - Then the parts, joined by "  ·  " in `ink3`, system 11 medium `.monospacedDigit()`. Parts at 0 are left out; when all are 0 it reads "All quiet" in `ink2`.
    1. "N need you" in `clay`, semibold. N = blocked agents + breakers + open ASK ME.
    2. "N blocked" in `amber`. N = tasks.json cards with status blocked.
    3. "N working" in `ink2`.
  - Right side: the floor cost, e.g. "$55.03" in `ink2`, plus " spent" in `ink3`.
- The tab bar no longer carries a summary. The battery stays where it is.

## 4. Limits card (v1.1; replaces the token chart, which is CANCELLED)
Mockup: `office-tab-v2-limits-mockup.png`. Data rules: `office-tab-v2-limits.md` (Pam).
- **Frame:** same position and width as before (188pt), radius 16, padding 10, inner height 96pt.
- **Header:**
  - "Limits" on the left.
  - On the right, "Updated Xm ago" in system 10 medium `ink3`.
  - Age format: "now" under 1 minute, then "Xm ago", "Xh ago", "X d ago".
- **Meter**, from top to bottom, 35pt in total. There is a 2pt gap under the header and 4pt between the two meters.
  1. Row (14pt), `firstTextBaseline`:
     - The name, "Session" or "Weekly", in system 11 semibold `ink`.
     - 4pt gap, then the window, "5 h" or "7 d", in system 10 `ink3`.
     - Spacer, then the percent in system 13 bold `.monospacedDigit()`, in the tint.
  2. Bar (5pt, 3pt top gap):
     - Track: `Capsule` in `ink` at 0.12.
     - Fill: `Capsule` in the tint, minimum width 5pt.
     - Tick at 80%: 1pt wide, `ink` at 0.28.
  3. Reset line (11pt, 2pt top gap): system 10 `ink3`, 1 line.
     - Session: "resets in 2 h 10 m". Weekly: "resets Mon 11:00" in the local 24h or 12h format.
     - Compute it from a `TimelineView(.everyMinute)` (no file read).
- **Tint steps:** the percent is always shown, so the state never relies on colour alone.
| Used | Tint | Extra |
|---|---|---|
| under 80% | `clay` #D97757 | none |
| 80–99% | `ember` #E8613C (new token) | none |
| 100% | `ember`, bar full | The reset line reads "Maxed · resets …" in `ember`, system 10 medium |
- **Resetting:** shown when now is past `resets_at` and the data is fresh.
  - The percent shows "–" in `ink3` and the bar has no fill (track only).
  - The reset line reads "Resetting…" in `clay`, system 10 medium.
  - This applies to each meter separately.
- **Stale:** the data came from the `~/.claude.json` fallback, or the timestamp is more than 1 h old.
  - Header right: `clock.arrow.circlepath` plus "2 d ago · /usage", in `amber`. This is the label that marks the data as old.
  - Both meters are at 0.7 opacity, and their tint is `ink3` instead of the orange steps.
  - A stale meter whose reset time has passed shows "–" and "Reset passed · open /usage" in `ink3`. Never show an old percent after its reset.
- **Unavailable:** shown when there is no file, the JSON is bad, or the fallback is not approved.
  - The header shows "Limits" only.
  - Centred below: `gauge.with.dots.needle.0percent` (16pt `ink3`), "Usage unavailable" (system 11 `ink2`), and "Open /usage in Claude Code" (system 10 `ink3`).
- **Loading** (more than 0.5s): the tracks show with no fill and the percent shows "–". There is no spinner.
- **Motion:** the bar width animates over 0.2s with ease-in-out when the value changes. Under Reduce Motion there is no animation.
- **VoiceOver:**
  - Each meter is one element, e.g. "Session, 25 percent used, resets in 2 hours 10 minutes" or "Weekly, 100 percent used, maxed, resets Monday 11 AM".
  - Stale adds ", from 2 days ago". Resetting reads "Session, resetting".
- **Tooltip:** "Session (5-hour window): 25% used · resets 01:30 · source: Office statusline file, updated 1 min ago". The source reads "~/.claude.json (/usage cache)" for the fallback.

### Pet tie-in: new Tired state
- **When:** either meter is at 90% or more, the data is fresh (not stale), and it has not reset.
- **Look:** sleepy eyes (as in Idle) plus a 4-cell sweat drop in #8FC7FF at cells (13,5), (13,6), (12,6), (13,7). There is no hop. The antenna tip is dim and static.
- **Priority:** Blocked, then Tired, then Working, then Idle; offline is Asleep.
- **Motion and accessibility:** no motion in any setting, and Reduce Motion is the same. The pet's `.help` reads "Weekly limit at 92%".

## 5. Pet (original design: a round clay sprout with an antenna)
This is an original critter: a round body, a single antenna with a glowing tip, and stubby feet. It does not trace or copy any Anthropic mascot or logo, and no image asset is added.

**Grid:** 14 columns × 12 rows. Draw it in a 16×14-cell box, with the body offset 2 rows down so the bubble fits. The cell is 2pt; at 2x it is 4px, so it stays crisp. Use integer cell sizes only.

```swift
static let body = [
    "......A.......",
    "......O.......",
    "....OOOOOO....",
    "...OLLOOOOO...",
    "..OLOOOOOOOO..",
    "..OOEOOOOEOO..",   // eye row 1: becomes "..OOOOOOOOOO.." when idle or asleep (sleepy)
    "..OOEOOOOEOO..",   // eye row 2
    "..OOOOOOOOOO..",
    "..OOOOOOOOOO..",
    "...DOOOOOOD...",
    "....DDDDDD....",
    "....D....D....",
]
static let bubble = [   // drawn at column 11, row 0 (top right); blocked only
    ".BBB.",
    "BBKBB",
    "BBKBB",
    "BBBBB",
    "BBKBB",
    ".BBB.",
    "B....",
]
```
**Colours:**
- O #D97757 body
- L #F0A985 highlight
- D #B5583A shade and feet
- E #1A1410 eyes
- A (antenna tip): #FFD9C2 lit, #B5583A dim, amber when blocked
- B amber bubble
- K #1A1410 the "!" mark

**States:** first match wins. The pet's state is driven by the summary.
| State | When | Frames | Motion (Core Animation only, no SwiftUI timers) |
|---|---|---|---|
| Blocked | need you > 0 | eyes open, bubble shown, amber tip | Bubble opacity 1 ↔ 0.6, 1.2s, autoreverse |
| Working | any agent working | eyes open, lit tip | Hop: whole sprite y −1 cell, discrete keyframes [0, −2pt, 0], 0.6s cycle, repeats |
| Idle | otherwise | sleepy eyes (row 1 blank) | Tip lit ↔ dim, discrete, 2.4s cycle |
| Asleep | office offline | sleepy eyes, dim tip, two grey "z" pixel pairs at (12,1)(13,1)(12,3)(13,2) in `ink3` | none |

- **Reduce Motion:** draw frame A of the state with no animation. The bubble stays at full opacity.
- **Implementation:**
  - Render each state's static frame once to a `CGImage` (or a Canvas), with `interpolation(.none)`.
  - Animate the whole layer: `position.y` for the hop, opacity on a separate tip or bubble sublayer.
  - When the tab is hidden or the panel is closed, remove the animations so they cost no CPU.
- **VoiceOver:** hidden (`.accessibilityHidden(true)`). The summary already carries the state.

## 6. Agents card (restyled)
- **Header:** "Agents" on the left; the agent count on the right in `ink3`. The cost moved to the summary row.
- **Rows:** same as OFF-17, with these changes:
  - Text is `ink` and `ink2`.
  - Blocked uses `amber`.
  - Dimmed rows are at 0.6.
  - The backlog capsule is `ink` at 0.12 with `ink2` text.
  - ~~**New:**~~ (cut in v1.1) a 6×6 swatch (radius 1.5) at the far right, in the agent's stack colour. It acts as the chart legend.
- **Tooltip:** adds "7 days: 121.8M tokens · $55.03".

## 7. Ask me card (restyled)
- **Header right:** "N open" in `clay`.
- **One question:** up to 3 lines, then the meta line.
- **Two or more questions:** the first 2, 1 line each, each with a meta line, 4pt apart. With 3 or more, "+N more" follows. Text is `ink`; the meta line is `ink3`. Tooltips are as in OFF-17.
- **Empty:** `checkmark.circle` + "Nothing waiting on you".

## 8. States (see mockup)
1. **Live.**
2. **Many agents:** 4 rows, "+N more", stack ranks 6+ merged as Other, a 0-token day.
3. **Ledger began today:** 6 stubs, one "so far" bar, "All quiet".
4. **No usage data.**
5. **Offline:** the summary row and cards are hidden, the OFF-17 offline block is centred, the pet is asleep, and there is no badge.
6. **Loading:** as in OFF-17. The pet shows idle frame A, with no animation until the data lands.

## 9. Not in this spec
Answering questions, scrolling, per-agent chart filtering, charts longer than 7 days, and any light-mode values.

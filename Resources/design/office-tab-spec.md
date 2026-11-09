# Office tab, design spec v1.0 (OFF-17)

Mockup: `office-tab-mockup.png`. Plan: `office-tab-plan.md`. The app is dark only. Row, mark, colour and tooltip rules are the same as `office-overview-spec.md` (the Home card) unless this file says otherwise.

## 1. Tab bar
- **Tab:** add `.office` as the third tab, after Home and Shelf. Its symbol is `building.2.fill`, matching the other filled symbols. Size and colours are the same as the existing tab buttons: 28×22, 12pt, `SelectedGlass`.
  - Tooltip: `.help("Office")`.
  - VoiceOver label: "Office, N questions waiting".
- **Badge:** shows the open ASK ME count; it is hidden at 0, offline and while loading.
  - Size: `Capsule` in `.orange`, minimum 13×13, horizontal padding 3.5.
  - Text: system 9 bold, `.monospacedDigit()`, white. Above 9 it reads "9+".
  - Position: `.overlay(alignment: .topTrailing)` on the tab button, `.offset(x: 5, y: -4)`. It shows on every tab, not only on Office.
- **Summary:** on the Office tab only, placed before the battery with 6pt between them. Text is system 11 medium, `.monospacedDigit()`. Use one phrase only, the first that applies:
  - "N need you" in `.orange`, when an agent is blocked or its breaker has tripped.
  - Otherwise "N working" at `.white.opacity(0.6)`.
  - Otherwise "All idle" at `.white.opacity(0.6)`.

  It is one phrase because the right wing is only about 176pt wide beside the notch. "2 need you · 3 working" pushed under the notch in the mockup. The floor cost moved to the Agents header.

## 2. Content layout
- The content area keeps the existing padding (14 at the sides, 6 at the top, 14 at the bottom). At 100% that is **534×138pt**. Panel size is unchanged.
- Three glass cards sit in `HStack(spacing: 8)`. Widths at 100%: **Agents 172, Workload 194, Ask me 152**. If the panel scale setting changes the content width, scale these three widths with it.
- Every card uses the same container as Home: `.padding(10)`, `.glass(RoundedRectangle(cornerRadius: 16, style: .continuous))`, full height, content top-aligned.
- **Inside a card:** a 14pt header, then a 4pt gap, then rows in `VStack(spacing: 2)`. Each row is 18pt.
  - **maxRows = 5** at 100%: floor((inner height 118 − 18 + 2) / 20).
- **Card header:** the title on the left is system 11 semibold at `.primary.opacity(0.6)`. The right side is system 11 `.monospacedDigit()`. This is the same as `WidgetHeader`, so reuse it.

## 3. Agents card
- **Header right:** the floor total cost, e.g. "$4.12", at `.primary.opacity(0.5)`.
- **Rows:** reuse the OfficeCard row exactly: mark, name (maximum 56pt), doing text, colours, 0.55 dimming, sort order and the PulseDot.
- **Backlog badge:** right-aligned. Shown only when the inbox backlog is above 0, and above 99 it reads "99+".
  - Text: system 9 semibold, `.monospacedDigit()`, `.primary.opacity(0.7)`.
  - Shape: horizontal padding 4, height 13, `Capsule` filled with `.white.opacity(0.12)`.
- **Tooltip:** the existing row tooltip, plus a third line: "$1.20 · 340k tokens · 2 unread".

## 4. Workload card
- **Header right:**
  - When anything is blocked: "N blocked" in `.orange`, then " · M" at 0.5 opacity, where M = doing + todo.
  - Otherwise: "N doing · M todo" at 0.5 opacity.
- **Order:** blocked, then doing, then todo, then the last 3 done. Done cards only appear if there is room left.
- **Row:** `HStack(spacing: 6)`:
  - **Mark:** 8pt in a 10pt frame.
    - Blocked: `exclamationmark.circle.fill` in `.orange`.
    - Doing: `circle.fill` in `.green` (static, no pulse).
    - Todo: `circle` in `.secondary`.
    - Done: `checkmark.circle` in `.secondary`, and the whole row at 0.55.
  - **Id:** system 10 medium, `.monospacedDigit()`, 0.5 opacity, `fixedSize()`.
  - **Title:** system 11, 1 line, truncated at the tail.
  - **Assignee:** a 14pt circle filled with `.white.opacity(0.14)`, holding the first letter of the assignee in system 8 bold at 0.8 opacity. When there is no assignee, the circle is left out.
- **Tooltip:** "OFF-17 · Office tab design", then "Doing · Oscar". The Done count's tooltip lists the last 3 done cards.

## 5. Ask me card
- **Header:** "Ask me". On the right, "N open" in `.orange`; it is hidden at 0.
- **Order:** newest first.
- **Item:**
  - The question in system 11 `.primary`, `lineLimit(2)`, truncated at the tail.
  - Under it, 1pt below, a meta line in system 10 at 0.5 opacity: "Pam · OFF-17 · 4m".
  - Each item has a fixed height of 42pt, with 4pt between items.
- **Fit:** 2 items fit. With 3 or more, show 1 item and then "+N more". Its tooltip lists each hidden question as "who: first 60 characters".
- **Read-only:** no tap action. Tooltip on an item: the full question, then "Asked by Pam on OFF-17, 4m ago".
- **Age format:** "now" under 1 minute, then "4m", "2h", "3d".

## 6. States
| State | What shows |
|---|---|
| **Live** | The three cards (mockup 1). |
| **Many / long** | "+N more" in the last row of any card that overflows (system 11, 0.5 opacity, 16pt indent). Its tooltip lists what is hidden. No scrolling. All text truncates at the tail and the full text is in the tooltip. Long names truncate at 56pt (mockup 2). |
| **Empty card** | Centred in the card: icon 18pt at 0.4 opacity, 5pt gap, text system 11 at 0.5 opacity. Workload: `checklist` + "No cards". Ask me: `checkmark.circle` + "Nothing waiting on you". The header right is hidden. No agents: `person.2` + "No one in the office". |
| **Offline** | Cards hidden. Centred in the content area: `moon.zzz` 22pt, "Office offline" system 12, then "Munder Difflin isn't running" system 10. These are the same as the Home card's offline state. The summary and the badge are hidden. |
| **Loading** | Only when the first read takes more than 0.5s. Centred: 3 dots, 5pt each with 4pt gaps, at 0.6/0.25 opacity, plus "Opening the office…" in system 12 at 0.5 opacity. Under Reduce Motion the dots stay static. Otherwise one dot steps every 0.4s through Core Animation (no SwiftUI timer). Faster reads skip this state. |
| **Bad tasks.json** | The Agents card still shows. Workload and Ask me each show `exclamationmark.triangle` + "Can't read tasks", in the same calm empty style (no red). |

## 7. Motion and accessibility
- **Refresh:** crossfade with `.animation(.easeInOut(duration: 0.2), value: rows)`. Nothing slides.
- **Reduce Motion:** the PulseDot is static and so are the loading dots.
- **VoiceOver:**
  - Each card: header "Agents, 5", "Workload, 1 blocked", "Ask me, 2 open".
  - Rows: combined elements, e.g. "OFF-17, Office tab design, doing, Oscar" and "Pam asks: …, 4 minutes ago".
- **Colour:** semantic colours only (`.primary` with opacity, `.orange`, `.green`, `.red`). No light-mode values.

## 8. Not in this spec
Answering questions from the notch, scrolling, a "show all" link and per-row animation. All are out of scope in the plan.

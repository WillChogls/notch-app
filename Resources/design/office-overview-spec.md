# Office overview card, design spec v1.1

v1.1 (as built): the Working pulse is a Core Animation layer, not .symbolEffect.

This card replaces `CalendarWidget` in `HomeView`. It keeps the same container: 170pt wide, 10pt padding (150pt usable), `.glass(RoundedRectangle(cornerRadius: 16, style: .continuous))`, and the same height as the now-playing card. Fonts follow the existing panel: system 11–12, with `.primary` at 1.0, 0.6 and 0.5 opacity.

```
┌──────────────────────────────┐
│ Office           3 working   │  header
│ ● Jim   Notch app: repl…     │  row (18pt)
│ ● Pam   Needs you · Rev…     │  amber
│ ● Oscar Equalizer spec       │
│ ‖ Dwight On hold             │  dimmed
│ ○ Kevin Idle                 │  dimmed
└──────────────────────────────┘
```

## 1. Layout
- `VStack(alignment: .leading, spacing: 2)`: the header, 6pt of space, then the rows. Top-aligned, with a `Spacer` at the bottom.
- **Row:** a single line 18pt high. `HStack(spacing: 6)` containing:
  - **State mark:** a 10pt-wide frame with the mark centred in it (see section 2).
  - **Name:** system 11 semibold, `.primary`, `lineLimit(1)`, `fixedSize()`, maximum width 56pt (it truncates at the tail beyond that).
  - **Doing:** system 11 regular, `.primary.opacity(0.6)`, `lineLimit(1)`, `.truncationMode(.tail)`, takes the remaining width (about 78pt, roughly 14 characters).
- The role is **not** shown in the row; it only appears in the tooltip (section 7). Two-line rows would fit only 3 agents, so they were rejected.

## 2. State marks and colours
The state is shown three ways: colour, shape and words. So it never relies on colour alone, which matters for colour-blind users.

| State | Mark (7pt) | Colour | Doing text | Row opacity |
|---|---|---|---|---|
| Breaker tripped | `circle.fill` | `.red` | "Breaker tripped" in red | 1.0 |
| Blocked on the human | `circle.fill` | `.orange` | "Needs you · " + task, in orange | 1.0 |
| Working | `circle.fill` + pulse | `.green` | task title, or "Active · Bash" | 1.0 |
| Paused / on hold | `pause.fill` | `.secondary` | "On hold" | 0.55 |
| Idle | `circle` (outline) | `.secondary` | "Idle" | 0.55 |

- **Pulse for Working (as built):** a 7pt circle `CALayer` in system green with a Core Animation opacity animation from 1 to 0.35, 0.9s, ease-in-out, autoreverse, repeating. It runs in the render server, so the app does 0% per-frame work. `.symbolEffect(.pulse)` was tried first and cost about 7.5% CPU, because it redrew the whole glass panel every frame. Other states use static symbols.
- **Sort order:** breaker first, then blocked, then working, then paused, then idle. Within a group, sort by name. Keep the order stable so rows don't jump around.

## 3. Fitting 4 or more agents
- No scrolling: a scroll view inside a hover panel is fiddly and easy to trigger by accident.
- `maxRows = floor((cardInnerHeight - 20) / 20)`. That's the header plus gap (20pt), then 18pt per row plus 2pt spacing. At 100% open size this gives about 5 rows.
- **More agents than `maxRows`:** show the first `maxRows - 1` agents in sort order, then a last row reading "+N more" (system 11, `.primary.opacity(0.5)`, indented 16pt to line up with the names). Sorting puts the agents that need attention first, so hidden ones are always idle or quiet.

## 4. Empty and offline states
Centred in the card, styled like "Nothing playing": icon 22pt at `.primary.opacity(0.4)`, 6pt gap, then text system 12 at `.primary.opacity(0.5)`. The tone is calm, never an error red.
- **No agents** (office running, nobody on it): icon `person.2`, text "No one in the office".
- **Office offline:** the hive files are missing, or the newest state file is older than 2 minutes. Icon `moon.zzz`, text "Office offline". Under it, a second line in system 10 at `.primary.opacity(0.4)`: "Munder Difflin isn't running".
- **The header is hidden in both states.**

## 5. Header
- `HStack`: on the left, "Office" (system 11 semibold, `.primary.opacity(0.6)`); a `Spacer`; on the right, a summary (system 11, `.monospacedDigit()`, `.primary.opacity(0.6)`).
- **Summary text**, using the first rule that applies:
  - "N need you" in orange if any agent is blocked or its breaker has tripped.
  - Otherwise "N working".
  - Otherwise "All idle".

## 6. Legibility on light and dark wallpaper
- **Text:** use only semantic colours (`.primary` with opacity, and system `.red`, `.orange`, `.green`), so they adapt automatically on both the dark and light glass tint.
- **Dimmed rows:** never go below 0.55 opacity, so idle rows stay readable on light wallpaper.
- **Amber:** use `.orange`, not a custom yellow, because yellow fails contrast on light glass.
- **No extra background:** add no extra fill or shadow behind the rows; the card's glass already provides the contrast.

## 7. Truncation and tooltip
- **Name:** never wraps. Beyond 56pt it truncates at the tail.
- **Doing text:** truncates at the tail and is shown as given; don't strip prefixes like "Notch app:".
- **Tooltip** on each row, using native `.help(...)` (no custom view):
  - First line: "Jim · Senior software engineer".
  - Second line: the state plus the full, untruncated doing text, e.g. "Working: Notch app: replace calendar widget with office overview".
- **"+N more" row:** its `.help` lists the hidden agents' names with their states, one per line.
- **Accessibility:** combine each row (`.accessibilityElement(children: .combine)`) with the label "Jim, Working, Notch app: replace…".

## 8. Data refresh
- Read the files when the panel opens, then every 5 seconds while it stays open. Stop reading when it closes, so there is no cost while closed.
- **Animation:** use no animation on refresh, except `.animation(.easeInOut(duration: 0.2), value: rows)` so a state change crossfades instead of popping.

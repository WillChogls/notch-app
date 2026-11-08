# Notch Settings window, design spec v1.3

v1.3: the app is dark only (human, 2026-11-08). Appearance row removed from General; General = Music app, Widget, Open at login. Window **483pt** as built (measured 966px at 2x). Every "light" value below is obsolete.

v1.2: Live preview removed (human: no help, wastes space). Music app row added to General (see shortcut-buttons-spec.md). New height and spacing under Window.

v1.1: Appearance segments text only, accent highlight (as built). Slider values snap to 5% steps on read.

Mockups: `settings-mockup-dark.png` (Auto, 70% opacity, 100% size, login on) and
`settings-mockup-light.png` (Light, 45%, 115%, login waiting for approval). Both are 2x.
Mockup source (shapes only, not production code): `/Users/willwhite/office/hive/agents/oscar-mw3mmhy9/mock/mock.swift`.
Behaviour of all four controls is unchanged. Only layout, wording and visuals change.

## Window
- Width 440pt, height fits content (`.fixedSize()`), not resizable.
- Title bar hidden: `.titlebarAppearsTransparent = true`, `.titleVisibility = .hidden`, style mask adds `.fullSizeContentView`. Keep `window.title = "Notch Settings"` for the Window menu and VoiceOver.
- Background: system window background, plus a header wash: horizontal gradient blue → lavender → pink (colours below), opacity 0.22 dark / 0.18 light, 160pt tall (was 240; keeps the wash on the header only), masked by a top-to-bottom black→clear gradient so it fades out.
- Content starts 52pt below the window top (clears the traffic lights). Side margins 20pt everywhere. Bottom padding 20pt.
- Height (content-driven, `.fixedSize()`), **483pt** as built (v1.3): 52 top + 56 header + 24 gap + "Panel" title 19 + Panel card 141 + 20 gap + "General" title 19 + General card 136 (Music app 44, Widget 44, Open at login 46, two 1pt dividers) + 20 bottom. About 505pt while the login or music hint line shows. The two cards stay within 5pt of each other, so the balance holds.
- Vertical rhythm: header → "Panel" title 24pt; card → next section title 20pt; title → its card 6pt. Same 20pt side and bottom margins, so the window reads as header + two equal-weight cards.

## Colours (from Pam's icon)
- Blue `#6B8CFF` (0.42, 0.55, 1.0)
- Lavender `#A98CFF` (0.66, 0.55, 1.0)
- Pink `#FF99D6` (1.0, 0.60, 0.84)
- Everything else is system: `.primary`, `.secondary`, `.tint` (accent), `.green` toggle default.

## 1. Header
HStack, spacing 14, vertically centred.
- App icon (`NSApp.applicationIconImage`), 56x56, shadow lavender 45%, radius 10, y 4.
- VStack leading, spacing 2:
  - "Notch": system 22 bold.
  - "Your notch, made useful.": system 13, `.secondary`.
- Spacer, then version capsule: "v" + `CFBundleShortVersionString`, system 11 medium, `.secondary`, padding 8h/3v, `Capsule().fill(.primary.opacity(0.08))`. (Mockup shows v1.0 as a placeholder.)

## 2. Section "Panel"
Section title: system 11 semibold `.secondary`, leading inset 34 (14 inside the card), 6 below; 24 above "Panel" (first section), 20 above "General".
Card: radius 12 continuous, fill white 6% (dark) / white 70% (light), 1pt stroke `.primary.opacity(0.07–0.08)`, inner horizontal padding 14. Rows separated by a 1pt divider in the stroke colour.

Slider rows (12 top/bottom padding, 8 between label line and slider):
| Row | Label | Value (right, 13 monospaced digits, `.secondary`) | Slider | Min/max icons (12pt, `.secondary`) |
|---|---|---|---|---|
| 1 | Opacity | "70%" | 0.2…1, step 0.05 | `circle.dotted` / `circle.fill` |
| 2 | Size | "100%" | 0.8…1.15, step 0.05 | `minus.magnifyingglass` / `plus.magnifyingglass` |

Use the native `Slider` full width (no tick marks: drop `step` from the Slider and round in the binding, or keep step and accept ticks; prefer no ticks). Accessibility labels: "Panel opacity", "Open panel size".

## 3. Section "General"
Same section title and card style.
- ~~Row "Appearance"~~ removed in v1.3 (dark only). Old spec, for reference: (44pt high): label left; native segmented `Picker` right, `.pickerStyle(.segmented)`, `.labelsHidden()`, text only: "Auto" (= system), "Light", "Dark". Selected segment uses the system accent (native macOS 26). The mockup's icons and neutral highlight were dropped: SwiftUI's segmented Picker can't show them on macOS.
- Row "Music app" (44pt): first row, then Widget (widget-slot-spec.md 6A), then Open at login; spec in shortcut-buttons-spec.md section 4.
- Row "Open at login" (12 top/bottom): label left, native `Toggle` `.toggleStyle(.switch)` right.
  - When status is `.requiresApproval`: a second line, spacing 4, system 11: `exclamationmark.circle.fill` (orange) + "Waiting for your OK in Login Items." (`.secondary`), Spacer, link button "Open System Settings…" (`.buttonStyle(.link)`) that calls `SMAppService.openSystemSettingsLoginItems()`.
  - On error: same line style, `xmark.octagon.fill` red + the error text.

## Copy (complete)
Notch · Your notch, made useful. · v<version> · Panel · Opacity · Size · General · Music app · Spotify · Apple Music · Widget · Office · Calendar · Clock · Weather · Open at login · Waiting for your OK in Login Items. · Open System Settings…

## Not in scope
No sidebar or tabs: four controls don't need them. Add tabs when a third section appears.

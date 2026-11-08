# Widget slot, design spec v1.1

**v1.1 (the human's answers):**
- **Calendar:** date-only; the events variant is dropped.
- **Weather:** uses automatic location (CoreLocation, city-level); the typed-city field is dropped.
- **Settings:** only the Widget picker row.

The open panel's right-hand card (170pt glass, the same height as now-playing) shows **one** widget, picked in Settings: Office (the default), Calendar, Clock, or Weather. Only the chosen widget is built and runs; the others don't exist, so they have no timers and do no polling.

- **Phase A, build first:** sections 1–4 and 6A.
- **Phase B, later:** section 5 (Weather), plus its segment in the picker.

Inner size: 150pt wide (170 minus 2 × 10 padding) by about **115pt** tall at 100% (panel 190 minus the tab bar, 6 top and 14 bottom, minus 2 × 10 padding). `scaleEffect` scales everything, so these numbers hold at 80–115%.

---

## 1. Common frame (`WidgetCard`)
- **Container**, exactly what Office has today: `.padding(10)`, `.frame(width: 170)`, `.glass(RoundedRectangle(cornerRadius: 16, style: .continuous))`, and the full slot height.
- **Switching:** `switch widget { … }` inside the card, with `.transition(.opacity)` and `.animation(.easeInOut(duration: 0.2), value: widget)`. It is a crossfade only, so it's already Reduce Motion safe; no change is needed for it.

### Shared header (`WidgetHeader(title:, summary:, trailing:)`)
Use this only in widgets that have a header. Office's current header is the reference:
- **Title:** system 11 semibold, `.primary.opacity(0.6)`.
- **Summary** (optional, right-aligned): system 11, `.monospacedDigit()`, `.primary.opacity(0.6)`.
- **Trailing control** (optional): a 16pt `ShortcutButton` in a `.overlay(alignment: .topTrailing)` on the card content. The summary gets `.padding(.trailing, 22)` while the control shows.
- **Height:** at least 16pt (it centres on the button), with 6pt below.

### Four shared states (`WidgetPlaceholder(symbol:, text:, detail:, action:)`)
The same tone as "Nothing playing" and "Office offline": calm, never red.

| State | What shows |
|---|---|
| **Content** | The widget's own layout. |
| **Empty** | Icon 22pt at `.primary.opacity(0.4)`; 6pt gap; text system 12 at `.primary.opacity(0.5)`; optional detail system 10 at `.primary.opacity(0.4)`. All centred. |
| **Loading** | `ProgressView().controlSize(.small)`, then the text (system 12, 0.5), e.g. "Loading weather". Show it only if loading takes more than **0.5s**; before that, show nothing, so it doesn't flicker. |
| **Error / offline** | The same layout as Empty. If old data exists, show the content instead, with an orange footer (section 5). |

**Optional action button** (under the detail, 8pt gap):
- Text system 11 medium.
- `.padding(.horizontal, 10).padding(.vertical, 4)`.
- `.glass(Capsule(), interactive: true)`.
- A 24pt hit area at minimum.

## 2. Office (unchanged, only wrapped)
The frame **must not**:
1. Add padding, a header or a background inside the card. `OfficeCard` keeps its own header and its `GeometryReader` row maths, which depends on the full inner height.
2. Move the Munder Difflin button. It stays in Office's own `.overlay(alignment: .topTrailing)`.
3. Change the polling lifecycle. Polling still starts `onAppear` and stops `onDisappear`, so it now also stops when another widget is chosen.
4. Change the 170pt width, the radius-16 glass, or the 0.2s row crossfade.

## 3. Clock / Date (no header: the time is the title)
```
10:42 PM          ← time
Sunday            ← weekday
8 November        ← date
```
- **Layout:** `VStack(alignment: .leading, spacing: 2)`, vertically centred in the card and aligned left.
- **Time:** `Text(date, format: .dateTime.hour().minute())`. This follows the system 12/24-hour setting and the locale; don't hard-code a format.
  - Font: system 32 semibold, `design: .rounded`, `.monospacedDigit()`, `.primary`.
  - `.minimumScaleFactor(0.7)` and `lineLimit(1)`, so "12:45 PM" fits within 150pt.
  - 4pt below it.
- **Weekday:** `.dateTime.weekday(.wide)`, system 13 semibold, `.primary`.
- **Date:** `.dateTime.day().month(.wide)` (locale order), system 12, `.primary.opacity(0.6)`.
- **Updates:** `TimelineView(.everyMinute)`. No seconds and no per-frame work.
- **VoiceOver:** one element, with the label "10:42 PM, Sunday, 8 November".

## 4. Calendar
### Date only (phase A, final)
```
November 2026                 ← header (shared style)
8  Sunday                     ← day number + weekday
M  T  W  T  F  S  S           ← week strip letters
2  3  4  5  6  7 (8)          ← numbers, today in an accent circle
```
- **Header:** `WidgetHeader(title: "November 2026")`, from `.dateTime.month(.wide).year()`.
- **Day row:** `HStack(alignment: .firstTextBaseline, spacing: 6)`. The day number is system 28 bold `.primary`; the weekday is system 13 semibold `.primary.opacity(0.6)`. 8pt below.
- **Week strip:** the current week, starting on `Calendar.current.firstWeekday`. Seven equal columns: `HStack(spacing: 0)`, each column with `.frame(maxWidth: .infinity)`.
  - **Letter:** `veryShortWeekdaySymbols`, system 9 medium, `.primary.opacity(0.5)`. 2pt gap below.
  - **Number:** system 11, in a 20 × 20 frame.
  - **Today:** `Circle().fill(Color.accentColor)` behind it, number in white and bold. Use the accent colour, never a hard-coded red.
  - **Other days:** `.primary.opacity(0.85)`. Days from another month: 0.4.
- **Height check:** 16 header + 6 + 34 day row + 8 + 34 strip = 98pt, which fits inside 115.
- **Updates:** `TimelineView(.everyMinute)`, re-rendering only when the date changes (midnight).
- **VoiceOver:** the header and day row form one element, "Sunday, 8 November 2026". The strip is one element, "Week of 2 to 8 November", with its children hidden.

## 5. Weather (phase B)
```
London                         ← header (city)
18°  ⛅                         ← temperature + symbol
Partly cloudy
H 21°  L 12°
Updated 10 min ago             ← footer
```
- **Header:** `WidgetHeader(title: city)`. The city comes from reverse-geocoding the location (`CLGeocoder`, `locality`). If no city name is found, use "Current location".
- **Temperature row:** `HStack(spacing: 8)`.
  - Temperature: system 32 semibold, `design: .rounded`.
  - Condition: an SF Symbol at 24pt.
    - Rendering: `.symbolRenderingMode(.multicolor)` in dark mode and `.hierarchical` in light mode, because a multicolour yellow sun fails contrast on white glass.
- **Condition text:** system 12, `.primary.opacity(0.6)`, 1 line.
- **High/low:** "H 21°  L 12°", system 11 medium, `.monospacedDigit()`, 0.6. 4pt above.
- **Footer:** `Text(updated, style: .relative)` with the label "Updated … ago", system 10, `.primary.opacity(0.4)`, pinned to the bottom.
- **Units:** follow the system. Use `Measurement<UnitTemperature>` formatted with `.measurement(width: .narrow)`; it picks °C or °F from the locale.
- **Location** (CoreLocation, `kCLLocationAccuracyKilometer`, city-level):
  - Ask **once**, at the moment the human first picks Weather in Settings. Never ask at launch.
  - Needs `NSLocationUsageDescription` in Info.plist: "Notch shows the weather for your city."
  - Use one-shot `requestLocation()`, refreshed with the weather. No continuous tracking.
- **States:**
  - Locating (first fetch, no location yet): shared loading state, "Locating…". Like loading, it only shows after 0.5s.
  - Loading (location known, weather not yet loaded): shared loading state, "Loading weather".
  - Location off (denied or restricted): icon `location.slash`, text "Location off", detail "Weather needs your location", action button **"Open System Settings"**, which opens Privacy & Security → Location Services (`x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices`).
  - Offline, with old data: show the content, but the footer reads "Offline · updated 1 hr ago" in `.orange`.
  - Offline, no data: icon `wifi.slash`, text "Weather unavailable", detail "Check your connection".
- **Refresh:** when the panel opens, if the data is more than 15 minutes old, and every 30 minutes while Weather is the chosen widget. Each refresh re-reads the location once. Never refresh when another widget is chosen.
- **VoiceOver:** one element, "London, 18 degrees, partly cloudy, high 21, low 12, updated 10 minutes ago".

## 6. Settings
### 6A. The "Widget" row (phase A)
- **Where:** the General card, as a new row after "Music app" and before "Open at login". Same row style: 44pt high, label left (system 13), with a 1pt divider.
- **Label:** "Widget".
- **Control:** a native segmented `Picker`, `.labelsHidden()`, text only, with the segments **Office**, **Calendar** and **Clock**.
  - Phase B adds **Weather** as a fourth segment. Don't show it before Weather works.
  - Width check: 4 segments at about 72pt each is about 290pt, which fits the roughly 300pt to the right of the label.
- **Stored as:** `@AppStorage("widget")`: `"office"`, `"calendar"`, `"clock"` or `"weather"`. The default is `"office"`.
- **Window height:** v1.2 was 488pt. Adding this row (+45) makes it **about 533pt**.

### 6B. Weather segment (phase B)
- Add **Weather** as the fourth segment. No other rows; the window stays at about **533pt**.
- **The first time Weather is picked:** request location permission right then. The widget shows "Locating…" until the request is answered, or "Location off" if it is denied.

## 7. Across all widgets
- **Light and dark glass:** use only semantic colours (`.primary` with opacity, `Color.accentColor`, `.orange`). The one exception is the today circle: accent fill with a white number, which reads on both.
  - Nothing goes below 0.4 opacity except decoration.
  - Weather symbols follow the light/dark rule in section 5.
- **Reduce Motion:**
  - Switching widgets is a crossfade, so it stays as it is.
  - The loading spinner is the system control, so it stays as it is.
  - No widget has any looping animation.
- **VoiceOver:** each widget is `.accessibilityElement(children: .contain)` with the label "Clock widget", "Calendar widget" and so on. The labels inside it are as given in each section.
- **CPU:**
  - Clock and Calendar redraw once a minute.
  - Weather refreshes every 30 minutes.
  - Office polls every 5s only while it is shown.
  - A widget that isn't chosen does no work at all.

## Acceptance checks (phase A)
1. Switch Office → Clock → Calendar in Settings, then open the panel: it shows only the chosen widget, and Office's polling has stopped (Activity Monitor shows idle CPU).
2. In Office, the Munder Difflin button and the rows are pixel-identical to before (compare with `office-build-live.png`).
3. With the system set to 24-hour time, the clock shows "22:42"; set to 12-hour, "10:42 PM", fitting on one line.
4. With the accent set to Pink, today's circle in the week strip is pink.
5. The Settings window is about 533pt tall, and the Widget row lines up with the Appearance and Music app rows.

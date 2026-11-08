# Notch visual audit (phase 1, polish only)

**Next:** Jim fixes items 1–3 first. They are about 30 minutes in total and are the most visible.

**Method:**
- Read every view file: `NotchViews.swift`, `OfficeCard.swift`, `Shortcut.swift`, `Equalizer.swift`, `Settings.swift` and `Glass.swift`.
- Checked the build screenshots in `Resources/design/`: `office-build-live/offline`, `shortcut-build-*` and `settings-build-*`.
- Looked at `AppIcon.iconset`.

**Not checked:** I could not run the app myself, because the sandbox blocks launching apps. Two things are therefore unverified: the open panel on a *light* wallpaper in Light appearance (no screenshot of it exists; see item 10), and the motion itself, since I only had still images.

## Already good: keep
1. **Closed notch:** it is pure black and merges with the hardware. The live-activity wings grow from the centre with a spring of 0.22s and damping 0.9, which feels quick without bouncing.
2. **Equalizer and office pulse:** both run on Core Animation and cost almost no CPU. The colour floor works: the near-black album gave grey bars that were still visible.
3. **Office card:** state is shown by colour, mark and words together. Rows sort by urgency, and the "+N more" and offline states are calm and clear. Rows have tooltips and combined accessibility labels.
4. **Settings:** clean two-card layout; the 5% snapping is fixed; it only uses native controls.
5. **Consistency:** semantic colours (`.primary` with opacity) are used throughout, the open panel only uses one card radius (16), and the shortcut buttons have tooltips and labels.

## Fixes, ranked by visible impact

### 1. Paused equalizer looks like a "…" menu button (now-playing card, title row): S, 5 min
- **Why it matters:** in the open panel, paused bars sit at their 4pt minimum height. That gives four grey dots at the right of the title (see `office-build-live.png`), which reads as a "more" menu the user will try to click.
- **Fix:** for the open-panel instance only, set `.opacity(player.isPlaying ? 1 : 0)` with `.animation(.easeOut(duration: 0.3), value: player.isPlaying)`. The play button already shows that it's paused. The closed notch needs no change, because its wings only show while playing.

### 2. Buttons with no name for VoiceOver and no tooltip (transport controls, tabs, shelf remove): S, 10 min
- **Why it matters:** VoiceOver reads SF Symbol names like "backward.fill" or nothing at all, and hovering shows no hint. These are the most-used controls in the app.
- **Fix:** add `.help(x)` and `.accessibilityLabel(x)` to each:
  - "Previous track", "Play" or "Pause" (following the state), "Next track".
  - Tabs: "Home" and "Shelf".
  - Shelf ✕ button: "Remove from shelf".
  - The scrubber: `.accessibilityValue("0:11 of 5:05")` and the label "Playback position".

### 3. Reduce Motion is ignored outside the equalizer (panel open/close, office pulse): S, 15 min
- **Why it matters:** the panel scales up from 0.6 and springs. That is exactly the motion the setting exists to remove, and the pulsing dot keeps moving.
- **Fix:** read `@Environment(\.accessibilityReduceMotion)`. When it is on:
  - Panel: use the transition `.opacity` only (no `.scale`), with the animation `.easeInOut(duration: 0.15)` for `isOpen` and `activity`.
  - `PulseDot`: don't add the animation, so the dot stays solid at opacity 1.
  - Shortcut hover: no scale; change opacity only.

### 4. Now-playing and office card tops don't line up (open panel, Home): M, 15 min
- **Why it matters:** the office card starts right under the tab bar, but the artwork is vertically centred, about 17pt lower. Two neighbouring cards with different top edges is the most noticeable alignment issue in the panel.
- **Fix:** put `.frame(maxHeight: .infinity, alignment: .top)` on `NowPlayingCard`'s `HStack`, so the artwork top sits flush with the office card's top edge. The existing `Spacer` in the text column keeps the controls at the bottom. Check that the bottom of the controls row then sits 0–4pt from the bottom of the card.

### 5. Missing hover feedback (tab buttons, progress bar): S, 15 min
- **Why it matters:** the transport and shelf buttons respond to hover through interactive glass, but the tabs and the scrubber don't, so they feel inert.
- **Fix:**
  - Unselected tab: opacity 0.5 at rest, 0.8 on hover, `.easeOut(duration: 0.15)`.
  - Scrubber on hover: track height 5 → 7pt with `.spring(duration: 0.2)`, plus `NSCursor.pointingHand`.

### 6. Shelf ✕ button is too small to hit (ShelfItem, top-right): S, 5 min
- **Why it matters:** its hit area is 14pt, below the 24pt minimum used everywhere else, and it sits on the edge of the item.
- **Fix:** keep the 14pt symbol, but give it `.frame(width: 24, height: 24).contentShape(Rectangle())` and `.offset(x: 6, y: -6)`, so the circle stays where it is now and the hit area grows outward.

### 7. Empty states don't match each other (Home with nothing playing, empty Shelf): S, 5 min
- **Why it matters:** the "Nothing playing" icon is 26pt, but the other empty states use 22pt. The shelf's dashed box uses radius 14 with plain (not continuous) corners, while every card uses 16 continuous.
- **Fix:**
  - "Nothing playing" icon: 26 → 22pt.
  - Shelf box: `RoundedRectangle(cornerRadius: 16, style: .continuous)`.

### 8. App icon is unreadable at 16pt (Finder list view, Spotlight, menus): M, 30 min, for Pam
- **Why it matters:** at 16pt the notch shape shrinks to a 2px smudge on a pale squircle. On a light Finder window the icon nearly disappears. At 32pt it is fine.
- **Fix:** hand-draw `icon_16x16.png` and `icon_16x16@2x.png`:
  - Notch shape widened to about 50% of the icon width (currently about 30%) and 25% of its height.
  - Squircle colours saturated about 15% more.
  - A 1px edge at 20% darker.
  - Leave 32pt and up as they are.

### 9. Hover and press timings vary slightly (shortcut, office, panel): S, 5 min
- **Why it matters:** hover uses a 0.2s spring, press a 0.15s spring, office row changes a 0.2s ease-in-out, and the tint crossfade 0.4s. These are close but not one system.
- **Fix:** one set of values, kept as named constants in `Glass.swift`:
  - Hover: `.easeOut(duration: 0.15)`.
  - Press: `.spring(duration: 0.15)`.
  - Content changes: `.easeInOut(duration: 0.2)`.
  - Panel: keep `.spring(response: 0.22, dampingFraction: 0.9)`.

### 10. Light mode is unverified (open panel on a light wallpaper): S, 10 min
- **Why it matters:** every panel screenshot so far is in dark mode. In Light appearance the glass tint is white and the top band fades to it; the tabs and battery are hard-coded white, which works only while they stay inside the black band.
- **Fix:** Jim takes two screenshots: Light appearance on a white wallpaper, and Auto on a bright photo wallpaper. Then I review them. If the battery text falls outside the band at 115% size, change `.white.opacity(0.8)` to `.primary.opacity(0.8)`.

## Totals
- **S items** (1, 2, 3, 5, 6, 7, 9, 10): about 70 minutes.
- **M items** (4, 8): about 45 minutes.
- **All ten:** about 2 hours.

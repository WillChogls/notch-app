# Shortcut buttons + "Music app" setting, design spec v1.1

v1.1: the buttons show each app's real icon instead of the arrow symbol (human). Placement, layout and the hide rule are unchanged.

Three additions:
- An "open Munder Difflin" button on the office card.
- An "open music app" button on the now-playing card.
- A "Music app" row in Settings.

They build on `office-overview-spec.md` (v1.1) and `settings-spec.md` (v1.1).

## 1. The shared button (`ShortcutButton`)
Both card buttons are the same view. Only the icon size, target app and tooltip differ.

| Part | Value |
|---|---|
| **Icon** | The app's own icon: `NSWorkspace.shared.icon(forFile: appURL.path)`, using the URL from the install check. No bundled assets. Office card: Munder Difflin. Now-playing: Spotify or Music, following the "Music app" setting and swapping as soon as it changes. Load it once per panel open together with the install check, and keep it in `@State`. |
| **Visual size** | `Image(nsImage:).resizable().interpolation(.high)`. Office card: 16 × 16 frame. Now-playing: 20 × 20 frame. macOS icons carry about 10% transparent margin, so the visible squircle is about 14 and 18pt, matching the line heights. |
| **Shape** | No clip and no corner radius. The icon already has its own macOS squircle mask; clipping would cut its edges and drop shadow. |
| **Shadow** | None added. The baked-in icon shadow is enough; an extra one blurs at this size. |
| **Hit area** | At least 24 × 24, without changing layout: `.padding(p).contentShape(Rectangle()).padding(-p)`, with p = 4 on the office card and p = 2 on now-playing. |
| **Style** | `.buttonStyle(.plain)` with a custom look. No `.glass`: a glass bubble inside a glass card looks heavy and would compete with the play/pause controls. |

### States
| State | Look |
|---|---|
| **Idle** | Icon at opacity 0.85: quiet but clearly the real app. At 0.5 a colour icon looks ghosted, like a disabled control. |
| **Hover** | Opacity 1.0, scale 1.12 (from the centre; the overlay means no layout change). `.spring(duration: 0.2)`. No ring or circle behind it: the icon's own shape is the target. |
| **Pressed** | Scale 0.92, opacity 0.7. `.spring(duration: 0.15)`. |
| **Keyboard focus** | The native focus ring: keep the button focusable and draw no custom ring. |
| **After click** | Open the app. The panel then closes on its own as the pointer leaves; don't force it closed. |

**Light and dark wallpaper:** app icons are full colour with their own background shape, so they read on both light and dark glass without any tint or backing. Don't apply `.foregroundStyle`, `.saturation` or template rendering. If the system renders tinted or dark-mode app icons (Settings > Appearance on macOS 26), `icon(forFile:)` returns that variant; accept it as is.

### Not-installed rule (Pam's rule: hide)
- **Check:** `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`. If it returns nil, hide the button.
- **When to check:** each time the panel opens. It's cheap, needs no permission prompt, and does no polling.
- **Why nothing shifts:** both buttons sit in an `.overlay` (see below), so hiding one never moves anything else.
- **How to open:** `NSWorkspace.shared.openApplication(at:configuration:)`. It needs no permissions.

## 2. Office card button
- **Placement:** `.overlay(alignment: .topTrailing)` on the card's content (inside the 10pt padding), so it sits on the header line: right edge flush with the content edge, centred on the header text's line.
- **Header:** the summary text ("N working" and so on) gets `.padding(.trailing, 22)` while the button is shown, and 0 when it's hidden. With the button hidden, the summary sits at the right edge, the same as today.
- **Empty and offline states:** show the button there too, at the same spot. In the "Office offline" state it is the most useful thing on the card.
- **Labels:** tooltip `.help("Open Munder Difflin")`, and accessibility label "Open Munder Difflin".
- **Target:** Munder Difflin's bundle id. Jim, read it from `/Applications/Munder Difflin.app/Contents/Info.plist`; don't hard-code a guess.

## 3. Now-playing card button
- **Placement:** on the transport-controls row (previous/play/next). Use `.overlay(alignment: .trailing)` on that row's full-width `HStack`, so the three controls stay exactly centred and nothing moves when the button hides.
  - It is vertically centred on the play button.
  - Its right edge is flush with the card content.
- **Spacing:** with the 26pt control spacing, the gap between the next button and the shortcut is about 50pt or more at 80% open size, so it never crowds the controls.
- **Not in the title row:** the equalizer lives there, so the title row stays as it is.
- **Target:** the *chosen* music app from Settings, never the one that is currently playing.

| Choice | Bundle id | Tooltip and accessibility label |
|---|---|---|
| Spotify | `com.spotify.client` | "Open Spotify" |
| Apple Music | `com.apple.Music` | "Open Apple Music" |

## 4. Settings: the "Music app" row
See settings-spec.md v1.2: the Live preview is removed and the window is now about 488pt tall including this row.
- **Where:** in the General card, between "Appearance" and "Open at login", separated by the same 1pt dividers.
- **Row:** same as "Appearance": 44pt high, label "Music app" on the left (system 13), and on the right a native segmented `Picker` (`.pickerStyle(.segmented)`, `.labelsHidden()`).
  - The segments are "Spotify" and "Apple Music".
  - Text only, no app icons: the macOS segmented picker drops images, as found in settings v1.1.
- **Stored as:** `@AppStorage("musicApp")`, with the values `"spotify"` or `"music"`.
- **Default** (Pam's rule): `"spotify"` if Spotify is installed, otherwise `"music"`. Work this out once, when no value has been saved yet.
- **If the chosen app isn't installed:**
  - Keep both segments.
  - Under the row, add a caption line: system 11, `.secondary`, with `exclamationmark.circle.fill` in orange and the text "Spotify isn't installed." (or "Apple Music isn't installed.").
  - The now-playing button is hidden by the rule in section 1.
  - No alerts.

## Copy
Open Munder Difflin · Open Spotify · Open Apple Music · Music app · Spotify · Apple Music · Spotify isn't installed. · Apple Music isn't installed.

## Acceptance checks
1. Hover each button: the icon grows slightly to full brightness; clicking it opens the app. Change Music app in Settings: the now-playing icon swaps at once.
2. Rename Spotify.app away and reopen the panel. The now-playing button is gone, the controls haven't moved, and Settings shows "Spotify isn't installed."
3. The office card header looks the same as before when Munder Difflin isn't installed.
4. With Full Keyboard Access on, Tab reaches both buttons and shows the system focus ring.
5. Check both buttons on a light wallpaper and on a dark wallpaper: the icon edges are not clipped and it looks the same as in the Dock, just smaller.

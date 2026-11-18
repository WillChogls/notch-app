# OFF-24 spec: clipboard history in the Shelf tab (v1.1)

v1.1: content width is 534 (Dwight measured), so the card gap and strip spacing are 6 (Jim's fix, adopted).

Next action: Jim builds per this spec after the plan's pasteboard spike (clipboard-plan.md, section 5, step 1).

Mockup: `clipboard-mockup.png` (9 panels). Dark only. Uses only existing tokens: white at opacities, system green, the link blue, and the current glass helpers (`.glass`, `.glassGroup`). Panel stays 600×190; the Shelf content area is 534×138 (measured).

## 1. Files | Clipboard switch (tab row)
- Where: `TabBar` HStack, right after the tab group, only when `model.tab == .shelf`, with `.padding(.leading, 2)` (8pt after the last tab), same pattern as `OfficePet`. The badge overlay stays on the tab group.
- Look: two icon segments in a track. Track: `Capsule().fill(.white.opacity(0.07))`, padding 2. Segment: 26×18, SF Symbol 10.5 medium. Files = `doc.on.doc`, Clipboard = `list.clipboard`. Selected: `.glass(Capsule())`, `.white`; not selected: `.white.opacity(0.45)`. Total 56×22: fits the ~90pt left wing.
- Why icons: text ("Files | Clipboard", ~110pt) runs under the notch.
- `.help("Files")` / `.help("Clipboard")`. VoiceOver: one `Picker`-style element "Shelf view, Files" / "Shelf view, Clipboard" (use `.accessibilityRepresentation { Picker }` or a segmented `Picker` with `.labelsHidden()` styled as above).
- Choice remembered for the session only (`@State` in the model, not AppStorage). A file drop on the panel switches to Files.

## 2. Clipboard strip
`HStack(spacing: 6)`: cards `HStack(spacing: 6)` (5 × 84 + 4 × 6 = 444; + 6 + 84 = 534), `Spacer(minLength: 0)`, then the action column: one Clear button, the same `shelfButton("trash", label: "Clear")` (84×28 glass capsule), vertically centred. No AirDrop. Clear hidden when the list is empty, off or blocked. Newest card first (leading). No scroll view needed (max 5).

## 3. Card (84×100, radius 12 continuous)
- Padding 8. Content top-leading; footer at the bottom.
- Rest: `fill(.white.opacity(0.06))`, no stroke (text needs a shape; shelf files don't).
- Hover: the fallback glass look `.glass(RoundedRectangle(12))` (0.10 fill + 0.14 stroke on pre-26), fades 0.15 s. X: `xmark.circle.fill` 14pt, palette `.white, .gray`, 24×24 hit frame at top-trailing, offset (7, −7) so it sits on the corner. Copy the ShelfItem logic: opacity fades only (no insert/remove), 300 ms unhover grace, gestures under the X.
- Pressed: `scaleEffect(0.97)`.
- Copied (click): overlay `fill(.black.opacity(0.75))` in the card shape, centred `checkmark.circle.fill` 20pt green + "Copied" 10 semibold white, spacing 4. Holds 0.8 s, fades out 0.15 s, then the card moves to first with `.spring(duration: 0.3)`. Reduce Motion: no move animation (list reorders instantly), overlay still shows. VoiceOver: announce "Copied".
- Footer (11pt high): SF Symbol 8 semibold + label 8.5 medium, `white 0.45`, spacing 3, one line.

| Kind | Content | Footer |
|---|---|---|
| Text | string, 10pt, white 0.88, `lineLimit(4)`, lineSpacing 1, tail truncation | `text.alignleft` Text |
| Rich text | plain string, same as text, no styling | `textformat` Rich text |
| Image | thumbnail aspect-fill in 68×44, radius 6, centred, 6pt from top | `photo` Image |
| File | file icon 40×40 centred + name 10pt, 1 line, middle truncation. Several: icon of the first + "3 files" | `doc` File / Files |
| URL | `link` 11 semibold in a 24pt circle (white 0.10), host 10.5 semibold 1 line middle truncation ("www." dropped), path 9pt white 0.45 1 line middle truncation | `globe` Link |

- Source app icon: skipped in v1 (no room in 84pt with the footer; add if asked).

## 4. Drag out
`.onDrag` on the card; the preview is the card itself at rest look (SwiftUI default snapshot), the card stays in place (it's a copy). Files: drag preview = the file icon only (`preview:` with a 48pt icon), matching the shelf. Image: the thumbnail. Text and URL: the card.

## 5. Empty, off, blocked (full content area, centred, VStack spacing 6)
- Empty: dashed frame exactly like the shelf's empty state (radius 14, white 0.25, 1.5pt, dash 6). `list.clipboard` 22pt + "Copy something and it shows up here." 12pt, white 0.5.
- Off: no frame (not a drop target). `list.clipboard` 22 + "Clipboard history is off" 12pt, white 0.5, + link button "Turn it on in Settings…" 11 medium, `.buttonStyle(.link)`: opens Settings (same action as the app's Settings item).
- Blocked: no frame. `lock` 22 + "Notch can't read the clipboard." 12pt white 0.5 + "Allow it in System Settings → Privacy & Security." 11pt white 0.4 (Dwight confirms the path wording).

## 6. Settings row
General card, a new row under "Open at login", same HStack and `.toggleStyle(.switch).tint(.green)`, divider between. Title "Clipboard history" (13pt), below it the subtext "Kept in memory only. Password manager copies are skipped." 11pt `.secondary`. Row min height 44. `@AppStorage("clipboardHistory")` default true.

## 7. VoiceOver
- Card: "Clipboard entry 1 of 5, text, Meeting moved to Thursday…" (first ~8 words; image: "image"; file: name; URL: host). Action: default = copy; custom action "Remove". X: "Remove entry 1".
- Clear: "Clear clipboard history".

## 8. Check against the mockup
Panels 1–6: hover, Files, Copied, empty, off, blocked. Panel 7: card states at 2x. Panel 8: Settings row. Panel 9: the switch.

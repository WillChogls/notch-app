# Shuffle and Repeat toggles, design spec v2

**v2 (the human's request):**
- **Colour:** grey when off, system blue when on. No album tint.
- **Position:** moved from the artist line into the transport row, to the left of Previous, in the order Shuffle, Repeat, Previous, Play, Next.
- **Scope:** open panel only. The closed notch and the toggle logic in `NowPlaying` are unchanged.

## 1. Width budget (text column ≈ 238pt at 100%; `scaleEffect` scales everything, so this holds at 80–115%)
| | Left of transport | Transport (Prev, Play, Next) | Right of transport |
|---|---|---|---|
| **Before (v1)** | 42 empty | 154 = 3×34 + 2×**26** | 42 = 22 gap + 20 app icon |
| **After (v2)** | 52 = 40 toggles + 12 gap | 134 = 3×34 + 2×**16** | 52 = 32 gap + 20 app icon |

- **Transport:** stays exactly centred in the column, with 52pt on each side.
- **Gap change:** prev/play/next go from 26pt apart to 16pt. That is still more than 10pt of clear glass between the 34pt circles. Set `.glassGroup(spacing: 16)` to match the new gap, as it matches 26 now.
- **Toggle group:** 16 + 8 + 16 = 40pt of visual width. Each 24pt hit area reaches 4pt past its 16pt frame, so across the 8pt gap the two hit areas meet exactly, without overlapping.
- **App icon:** keeps 32pt of air from Next, so it is less crowded than before (22pt).

## 2. Layout
```
|[⇄][↻]   ( ⏮ )  (  ⏯  )  ( ⏭ )            [icon]|
 0   40 52 ─────── 134 centred ────── 186   218 238
```
- **Transport:** `HStack(spacing: 16) { prev; play; next }.frame(maxWidth: .infinity)`, with no other change.
- **Toggles:** `.overlay(alignment: .leading) { HStack(spacing: 8) { shuffle; repeat } }` on that row.
  - Leading edge flush with the column, which is where the artist text starts.
  - Vertically centred on the play button.
- **App icon:** the existing `.overlay(alignment: .trailing)` is unchanged.
- **Artist line:** remove the v1 overlay and its `.padding(.trailing, 52)`, so the artist name gets its full width back.

## 3. Size
| Part | Value |
|---|---|
| **Symbol** | `shuffle` and `repeat`, system **13 medium**. (16pt would be wider than its frame, because these glyphs are wider than they are tall.) |
| **Visual frame** | 16 × 16 |
| **Hit area** | 24 × 24, without changing layout: `.padding(4).contentShape(Rectangle()).padding(-4)` |
| **Style** | `.buttonStyle(.plain)`, no glass circle, so they read as secondary to the transport buttons |

## 4. Colour (exact values)
| State | Symbol | "On" dot |
|---|---|---|
| **Off** | `.primary.opacity(0.5)`, the same grey as the other secondary icons in the panel | none |
| **On** | `Color.accentColor` (system accent, blue by default) | a 3pt circle in the same colour, centred 3pt below the 16pt frame, as an overlay |

- **Graphite accent fallback:** if the user's system accent is Graphite (grey), "on" would look like "off". So when the accent's saturation is under 0.15, use `Color(nsColor: .systemBlue)` instead.
- **Keep the dot.** It is the "on" signal that doesn't depend on colour, for colour-blind users and Graphite users.
- **Contrast** (approximate; glass with opacity ≥ 50% reads close to black or white):

| | Dark glass (≈ black) | Light glass (≈ white) |
|---|---|---|
| On: systemBlue | #0A84FF ≈ 5.6:1 | #007AFF ≈ 3.8:1 |
| Off: primary at 50% | ≈ 5.3:1 | ≈ 3.6:1 |

All four pass WCAG's 3:1 minimum for UI graphics.

## 5. States (unchanged from v1 apart from the colours)
| State | Look |
|---|---|
| **Hover** | Off: opacity 0.5 → 0.8. On: stays blue. Both: a 20pt `Circle` behind the symbol, `.primary.opacity(0.10)`. `.easeOut(duration: 0.15)`. |
| **Pressed** | Scale 0.92, opacity 0.7, `.spring(duration: 0.15)`. |
| **Toggle change** | Colour crossfade `.easeOut(duration: 0.15)`; dot scales from 0 to 1 with `.spring(duration: 0.2)`. |
| **Keyboard focus** | Native focus ring. |

**Reduce Motion:** no scale on press or on the dot. The dot fades in over 0.15s instead.

## 6. Hiding (no layout shift)
- **Nothing playing:** the whole card is replaced by "Nothing playing", as before.
- **One state unknown** (`isShuffle` or `isRepeat` is nil): keep that toggle's slot but apply `.hidden()`. This stops Repeat jumping left when only Shuffle is missing.
- **Both unknown:** hide the whole overlay. The transport doesn't move, because it is centred on its own.

## 7. Tooltips and VoiceOver (unchanged)
- **Tooltips:** "Shuffle on" / "Shuffle off", "Repeat on" / "Repeat off" (the current state).
- **VoiceOver:** labels "Shuffle" and "Repeat", value "On" / "Off", and `.accessibilityAddTraits(.isToggle)`.

## Acceptance checks
1. Measure in a screenshot: the gap from the column's left edge to the left edge of Previous equals the gap from the right edge of Next to the column's right edge (52pt at 100%, within 1pt).
2. Turning shuffle on makes it blue and shows the dot. Set System Settings → Appearance → Accent to Graphite: "on" is still blue.
3. The long artist name now runs the full width and is no longer cut short at the right.
4. Check at 80% and 115% open size: no overlap between Repeat and Previous, or between Next and the app icon.
5. With VoiceOver, it reads "Shuffle, on, toggle button".

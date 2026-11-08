# Notch equalizer (struct Bars), design spec v1.1

v1.1 (as built): rendering is 4 Core Animation layers on a display link (Canvas cost ~4% CPU); acceptance check 2 corrected to 0.75s for the 180 ms decay.

Goal: four small bars on the right of the closed notch that clearly move with the music: they jump up on hits and fall back more slowly. Minimal, readable at 18 x 14pt, cheap on CPU. This replaces the current random heights that change every 0.28s.

## 1. Geometry (closed notch)
- **Bars:** 4. Width 3pt, gap 2pt, so 4×3 + 3×2 = **18pt** wide total. Frame height 14pt; bars are bottom-aligned, which is the usual equalizer look.
- **Shape:** rounded rectangle, corner radius 1.5pt (fully round ends, the same as a capsule).
- **Height:** `h = 3 + 11 * level`, so 3pt when the level is 0 and 14pt when it is 1. Round to 0.5pt so edges stay crisp.
- **Rest state** (paused or no signal): every bar at 3pt, which reads as a row of four dots.

## 2. Colour
- **Fill:** the album tint (`player.tint`), solid. No gradient and no glow: at 3pt wide both just blur into a smear, and a glow costs a shadow pass every frame.
- **Contrast floor:** the bars sit on pure black. If the tint's relative luminance is below 0.35, mix it toward white until it reaches 0.35 (e.g. `tint.blended(withFraction: x, of: .white)`). Without this, dark album covers give invisible bars. White stays white.
- **Paused:** bars use the same tint at 50% opacity, so a paused song reads as quieter, not broken.
- **Tint change** when the track changes: crossfade the colour over 0.4s, ease-in-out.

## 3. Bands: what makes each bar different
Left to right, from low to high pitch:

| Bar | Band | Real audio range | Gain | Character |
|---|---|---|---|---|
| 0 | Bass | 40–150 Hz | 1.0 | Big, beat-driven |
| 1 | Low-mid | 150–600 Hz | 1.1 | Body, vocals |
| 2 | High-mid | 600–2.5 kHz | 1.4 | Melody |
| 3 | Treble | 2.5–10 kHz | 1.8 | Hi-hats, quick flicks |

The gain column compensates for higher bands carrying less energy, so the treble bar isn't always low. Clamp each band to 0...1 after applying the gain.

## 4. Data input: one function, two sources
The view only ever reads `levels: [Double]` (4 values, 0...1) for the current time. Behind it sits either of these:

**A. Real audio** (if approved). Per band, compute RMS (root mean square, the average loudness), then convert it with:
`level = clamp((dB + 50) / 44, 0, 1)`, then `level = pow(level, 0.8)` so mid-level sounds are easier to see. Apply the gain from the table.

**B. Simulated** (default, deterministic, no allocation):
```
t = seconds since playback started
beat = exp(-fmod(t, 0.5) / 0.12)              // 120 BPM pulse, sharp decay
f1 = [0.9, 1.3, 1.7, 2.3]   f2 = [3.1, 4.3, 5.9, 7.7]   phase = [0, 1.7, 3.1, 4.4]
beatWeight = [0.55, 0.35, 0.15, 0.10]
noise_i = hash(i, floor(t / 0.09)) in 0...1   // new random value every 90 ms
level_i = clamp(0.30
              + 0.18 * sin(2π f1_i t + phase_i)
              + 0.10 * sin(2π f2_i t)
              + beatWeight_i * beat
              + 0.22 * (noise_i - 0.5), 0, 1)
```
The result: the bass bar pumps on the beat and the treble bar flickers, and the four bars never move in lockstep. If the app ever has a real BPM, replace 0.5 with 60/BPM.

## 5. Motion: fast attack, slower decay
Run both sources through the same smoothing, one value per bar, frame-rate independent:
```
dt = frameDate - lastDate (clamp to 0...0.1 s)
tau = target > current ? 0.035 : 0.180        // attack 35 ms, decay 180 ms
current += (target - current) * (1 - exp(-dt / tau))
```
- **Attack (rising):** 35ms time constant, so a bar reaches about 95% of a hit in roughly 100ms. It feels like it's on the beat.
- **Decay (falling):** 180ms time constant, so it falls in about 0.5s. This is what makes it read as music rather than noise.
- No spring and no overshoot: at 14pt tall, overshoot looks like jitter.
- Do **not** use SwiftUI `.animation` on the heights. The smoothing above *is* the animation.

## 6. Pause, idle and resume
- **Pause:** set every target to 0. The decay brings the bars down to 3pt in about 0.5s. Once all bars are within 0.01 of 0, stop the timeline (`paused: true`), which costs zero frames while paused.
- **Resume:** restart the timeline. Bars rise from rest at the attack speed.
- **No track:** hide the bars, as today.
- **Reduce Motion** (accessibility setting on): no timeline. While playing, show static heights of 6 / 11 / 8 / 5pt; while paused, all at 3pt.

## 7. Rendering (CPU)
- As built: 4 `CALayer`s (one per bar, corner radius = width/2) driven by a display link; each tick updates the envelope and sets layer heights with implicit actions disabled. Measured 0.5–1.2% CPU. (TimelineView + Canvas was tried first and cost ~4%.)
- The smoothing state (4 doubles plus the last timestamp) lives with the display-link driver; nothing in SwiftUI re-renders per frame.
- 30fps is enough at this size. Use 60fps only for the open-panel version below.
- `.accessibilityHidden(true)`. The play state is already announced elsewhere.

## 8. Larger version in the open panel (optional, recommended)
It's worth doing because it reuses the same view: only the parameters change, so there is no new logic.
- **Where:** in the now-playing row, after the track title, aligned to the title's first-line baseline.
- **Geometry:** 4 bars, width 4pt, gap 3pt (25pt wide total), height 4 to 20pt, corner radius 2.
- **Speed:** 60fps. Same bands, timing and colour rules.
- **When to skip it:** if the row is crowded at 80% open size.

Parameters for the shared view: `Bars(levels:, barWidth:, gap:, minHeight:, maxHeight:, fps:)`. The closed notch uses 3 / 2 / 3 / 14 / 30; the open panel uses 4 / 3 / 4 / 20 / 60.

## Acceptance checks
1. On a song with a clear kick drum (simulated or real), the left bar visibly peaks about twice a second and the right bar flickers faster.
2. When paused, the bars drop to dots in under 0.75s from full height (about 0.6s from typical playing levels), and Activity Monitor shows the app's CPU going back to idle.
3. A near-black album cover still gives clearly visible bars.
4. While playing, CPU in Activity Monitor stays under about 2% on Apple silicon.

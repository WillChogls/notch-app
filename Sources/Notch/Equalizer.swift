import AppKit
import SwiftUI

/// Four band levels (bass, low-mid, high-mid, treble), each 0...1, for a given time.
/// Phase 1 uses `SimulatedLevels.at`; a real audio tap can be swapped in with the same signature.
typealias LevelSource = (TimeInterval) -> SIMD4<Double>

/// Deterministic stand-in signal: 120 BPM bass pulse + per-band sines + 90 ms noise
/// (equalizer-spec.md §4B). Allocation free.
enum SimulatedLevels {
    private static let f1 = SIMD4<Double>(0.9, 1.3, 1.7, 2.3)
    private static let f2 = SIMD4<Double>(3.1, 4.3, 5.9, 7.7)
    private static let phase = SIMD4<Double>(0, 1.7, 3.1, 4.4)
    private static let beatWeight = SIMD4<Double>(0.55, 0.35, 0.15, 0.10)

    static func at(_ t: TimeInterval) -> SIMD4<Double> {
        let beat = exp(-fmod(t, 0.5) / 0.12)
        let slot = UInt64(max(0, (t / 0.09).rounded(.down)))
        var out = SIMD4<Double>()
        for i in 0..<4 {
            let v = 0.30
                + 0.18 * sin(2 * .pi * f1[i] * t + phase[i])
                + 0.10 * sin(2 * .pi * f2[i] * t)
                + beatWeight[i] * beat
                + 0.22 * (noise(UInt64(i), slot) - 0.5)
            out[i] = min(max(v, 0), 1)
        }
        return out
    }

    /// Hash of (band, time slot) to 0...1 (splitmix64 finaliser).
    private static func noise(_ i: UInt64, _ slot: UInt64) -> Double {
        var x = slot &* 0x9E37_79B9_7F4A_7C15 &+ i &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53)
    }
}

/// Smoothing + colour state. Not observable: mutated while drawing, so no view rebuilds.
final class Meter {
    var current = SIMD4<Double>()
    private var lastDate: Date?
    private var fromColor = SIMD4<Double>(1, 1, 1, 1)
    private var toColor = SIMD4<Double>(1, 1, 1, 1)
    private var fadeStart: Date?

    /// One-pole envelope: attack 35 ms, decay 180 ms, frame-rate independent (spec §5).
    func step(to target: SIMD4<Double>, at date: Date) {
        let dt = min(max(date.timeIntervalSince(lastDate ?? date), 0), 0.1)
        lastDate = date
        for i in 0..<4 {
            let tau = target[i] > current[i] ? 0.035 : 0.180
            current[i] += (target[i] - current[i]) * (1 - exp(-dt / tau))
        }
    }

    var atRest: Bool { current.max() < 0.01 }

    func fade(to color: SIMD4<Double>, at date: Date) {
        fromColor = self.color(at: date)
        toColor = color
        fadeStart = date
    }

    func setColor(_ color: SIMD4<Double>) { fromColor = color; toColor = color; fadeStart = nil }

    /// 0.4 s ease-in-out crossfade between tints (spec §2).
    func color(at date: Date) -> SIMD4<Double> {
        guard let fadeStart else { return toColor }
        let p = min(max(date.timeIntervalSince(fadeStart) / 0.4, 0), 1)
        if p >= 1 { self.fadeStart = nil; return toColor }
        let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        return fromColor + (toColor - fromColor) * e
    }

    var fading: Bool { fadeStart != nil }
}

/// Equalizer driven by `levels`. Closed notch: 3/2/3/14/30. Open panel: 4/3/4/20/60.
/// Drawn as four Core Animation layers on a display link rather than TimelineView + Canvas:
/// a SwiftUI update at 30 fps cost ~4% CPU, layers cost a fraction of that (spec §7 budget).
struct Bars: NSViewRepresentable {
    let levels: LevelSource
    let playing: Bool
    let tint: NSColor
    var barWidth: CGFloat = 3
    var gap: CGFloat = 2
    var minHeight: CGFloat = 3
    var maxHeight: CGFloat = 14
    var fps: Float = 30

    func makeNSView(context: Context) -> BarsView { BarsView() }

    func updateNSView(_ view: BarsView, context: Context) {
        view.update(self, reduceMotion: context.environment.accessibilityReduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BarsView, context: Context) -> CGSize? {
        CGSize(width: barWidth * 4 + gap * 3, height: maxHeight)
    }
}

final class BarsView: NSView {
    private let meter = Meter()
    private var bars: [CALayer] = []
    private var link: CADisplayLink?
    private var config: Bars?
    private var reduceMotion = false
    private var tint: NSColor?

    /// Reduce Motion heights 6/11/8/5 pt of the 3...14 pt closed range, as levels.
    private static let staticLevels = SIMD4<Double>(3, 8, 5, 2) / 11

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let bar = CALayer()
            bar.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ config: Bars, reduceMotion: Bool) {
        let wasPlaying = self.config?.playing
        self.config = config
        self.reduceMotion = reduceMotion
        if tint == nil { meter.setColor(Self.rgba(config.tint.readableOnBlack)) }
        else if tint != config.tint { meter.fade(to: Self.rgba(config.tint.readableOnBlack), at: .now) }
        tint = config.tint
        layer?.opacity = config.playing ? 1 : 0.5
        if wasPlaying != config.playing || meter.fading { wake() }
        render(at: .now)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { link?.invalidate(); link = nil } else { wake() }
    }

    private func wake() {
        guard window != nil, let config else { return }
        if reduceMotion { link?.isPaused = true; render(at: .now); return }
        if link == nil {
            let l = displayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: config.fps / 2, maximum: config.fps, preferred: config.fps)
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let config else { return }
        let now = Date()
        meter.step(to: config.playing ? config.levels(now.timeIntervalSinceReferenceDate) : .zero, at: now)
        render(at: now)
        // Paused and settled: stop the link so it costs zero frames.
        if !config.playing, meter.atRest, !meter.fading { link.isPaused = true }
    }

    private func render(at now: Date) {
        guard let config else { return }
        let levels = reduceMotion ? (config.playing ? Self.staticLevels : .zero) : meter.current
        let c = meter.color(at: now)
        let color = CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
        for (i, bar) in bars.enumerated() {
            let raw = config.minHeight + (config.maxHeight - config.minHeight) * CGFloat(levels[i])
            let h = (raw * 2).rounded() / 2
            bar.frame = CGRect(x: CGFloat(i) * (config.barWidth + config.gap), y: 0, width: config.barWidth, height: h)
            bar.cornerRadius = config.barWidth / 2
            bar.backgroundColor = color
        }
    }

    private static func rgba(_ c: NSColor) -> SIMD4<Double> {
        let s = c.usingColorSpace(.sRGB) ?? .white
        return SIMD4(Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent), 1)
    }
}

extension NSColor {
    /// WCAG relative luminance (sRGB).
    var relativeLuminance: Double {
        guard let c = usingColorSpace(.sRGB) else { return 1 }
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    /// Mixed toward white just enough to reach luminance 0.35, so bars stay visible on black (spec §2).
    var readableOnBlack: NSColor {
        guard relativeLuminance < 0.35 else { return self }
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if (blended(withFraction: mid, of: .white)?.relativeLuminance ?? 1) < 0.35 { lo = mid } else { hi = mid }
        }
        return blended(withFraction: hi, of: .white) ?? .white
    }
}

/// `NOTCH_SELFCHECK=1 Notch` runs these and exits.
enum EqualizerSelfCheck {
    static func run() {
        // Envelope: ~95% of a hit in 100 ms, falls to rest in under 0.6 s.
        let m = Meter(), t0 = Date()
        m.step(to: .zero, at: t0)
        var t = t0
        for _ in 0..<3 { t += 1.0 / 30; m.step(to: SIMD4(repeating: 1), at: t) }
        precondition(m.current[0] > 0.9, "attack too slow: \(m.current[0])")
        // From a typical playing level (0.6), bars read as dots (< 0.25 pt above min) within 0.6 s.
        m.current = SIMD4(repeating: 0.6)
        for _ in 0..<18 { t += 1.0 / 30; m.step(to: .zero, at: t) }
        precondition(m.current.max() * 11 < 0.25, "decay too slow: \(m.current)")
        // Simulated signal: bass peaks on the 0.5 s beat, all bands stay in 0...1.
        let onBeat = SimulatedLevels.at(100.0), offBeat = SimulatedLevels.at(100.4)
        precondition(onBeat[0] > offBeat[0], "bass not on the beat")
        precondition((0..<200).allSatisfy { i in let v = SimulatedLevels.at(Double(i) * 0.037); return v.min() >= 0 && v.max() <= 1 })
        // Contrast floor: near-black tint becomes visible, white stays white.
        precondition(NSColor(red: 0.05, green: 0.02, blue: 0.08, alpha: 1).readableOnBlack.relativeLuminance >= 0.349)
        precondition(NSColor.white.readableOnBlack == .white)
        // FFT bands: a bass tone lights the left bar, a 5 kHz tone the right one.
        for (hz, loud, quiet) in [(80.0, 0, 3), (5000.0, 3, 0)] {
            let a = BandAnalyzer(sampleRate: 48000)
            a.append((0..<BandAnalyzer.size).map { Float(0.5 * sin(2 * Double.pi * hz * Double($0) / 48000)) })
            let v = a.levels()
            precondition(v[loud] > 0.8 && v[quiet] < 0.3, "\(hz) Hz -> \(v)")
        }
        let silent = BandAnalyzer(sampleRate: 48000)
        silent.append([Float](repeating: 0, count: 512))
        precondition(!silent.heardSound && silent.levels() == .zero)
        print("equalizer self-check passed")
    }
}

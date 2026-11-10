import AppKit
import SwiftUI

/// The Office tab's pet: an original pixel sprout (office-tab-v2-spec.md §5), drawn from a grid in code.
/// Each frame is a tiny CGImage scaled with nearest-neighbour filtering (crisp at any scale); motion is
/// Core Animation only, and the layers go away with the view, so a hidden tab costs nothing.
struct PixelPet: NSViewRepresentable {
    enum Mood: Equatable { case blocked, tired, working, idle, asleep }

    let mood: Mood
    let animated: Bool

    /// 16×14 cells of 2pt.
    static let cols = 16, rows = 14, cell: CGFloat = 2
    static let size = CGSize(width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)

    static let body = [
        "......A.......",
        "......O.......",
        "....OOOOOO....",
        "...OLLOOOOO...",
        "..OLOOOOOOOO..",
        "..OOEOOOOEOO..",
        "..OOEOOOOEOO..",
        "..OOOOOOOOOO..",
        "..OOOOOOOOOO..",
        "...DOOOOOOD...",
        "....DDDDDD....",
        "....D....D....",
    ]
    static let bubble = [
        ".BBB.",
        "BBKBB",
        "BBKBB",
        "BBBBB",
        "BBKBB",
        ".BBB.",
        "B....",
    ]
    /// The body sits 2 rows down so the bubble fits above-right.
    static let bodyRow = 2, bubbleCol = 11
    static let tipCell = (col: 6, row: bodyRow)

    private static let colors: [Character: Int] = [
        "O": 0xD97757, "L": 0xF0A985, "D": 0xB5583A, "E": 0x1A1410, "B": 0xF0B54A, "K": 0x1A1410, "Z": 0x8F8B85, "S": 0x8FC7FF,
    ]
    static let tipLit = 0xFFD9C2, tipDim = 0xB5583A, amber = 0xF0B54A

    final class Coordinator { var drawn: (Mood, Bool)? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let root = view.layer, context.coordinator.drawn.map({ $0 != (mood, animated) }) ?? true else { return }
        context.coordinator.drawn = (mood, animated)
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let sprite = CALayer()
        sprite.frame = CGRect(origin: .zero, size: Self.size)
        let scale = view.window?.backingScaleFactor ?? 2

        // Body (eyes per mood; the asleep "z" pixels are part of this frame).
        let art = Self.sprite(mood)
        let bodyLayer = Self.pixelLayer(art, origin: (0, 0), scale: scale)
        sprite.addSublayer(bodyLayer)

        // Antenna tip: its own layer so idle can blink it without redrawing the body.
        let tip = CALayer()
        tip.frame = Self.rect(col: Self.tipCell.col, row: Self.tipCell.row, w: 1, h: 1)
        let tipColor = mood == .blocked ? Self.amber : mood == .asleep || mood == .tired ? Self.tipDim : Self.tipLit
        tip.backgroundColor = Self.cg(tipColor)
        sprite.addSublayer(tip)

        var bubble: CALayer?
        if mood == .blocked {
            let b = Self.pixelLayer(Self.bubble, origin: (Self.bubbleCol, 0), scale: scale)
            sprite.addSublayer(b)
            bubble = b
        }
        root.addSublayer(sprite)

        guard animated else { return }
        switch mood {
        case .blocked:
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1; pulse.toValue = 0.6
            pulse.duration = 1.2; pulse.autoreverses = true; pulse.repeatCount = .infinity
            bubble?.add(pulse, forKey: "pulse")
        case .working:
            let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
            hop.values = [0, Self.cell]   // up one cell (layer y grows upward)
            hop.keyTimes = [0, 0.5, 1]
            hop.calculationMode = .discrete
            hop.duration = 0.6; hop.repeatCount = .infinity
            sprite.add(hop, forKey: "hop")
        case .idle:
            let blink = CAKeyframeAnimation(keyPath: "backgroundColor")
            blink.values = [Self.cg(Self.tipLit), Self.cg(Self.tipDim)]
            blink.keyTimes = [0, 0.5, 1]
            blink.calculationMode = .discrete
            blink.duration = 2.4; blink.repeatCount = .infinity
            tip.add(blink, forKey: "blink")
        case .asleep, .tired:
            break
        }
    }

    /// The 16×14 frame for a mood: body offset 2 rows down; sleepy eyes blank eye row 1; "z" pixels when asleep,
    /// a sweat drop when tired.
    static func sprite(_ mood: Mood) -> [String] {
        var grid = Array(repeating: String(repeating: ".", count: cols), count: rows)
        for (r, line) in body.enumerated() {
            var row = line.replacingOccurrences(of: "A", with: ".")   // the tip is its own layer
            if r == 5, [.idle, .asleep, .tired].contains(mood) { row = row.replacingOccurrences(of: "E", with: "O") }
            grid[r + bodyRow] = row + String(repeating: ".", count: cols - row.count)
        }
        if mood == .asleep {
            for (c, r) in [(12, 1), (13, 1), (12, 3), (13, 2)] {
                var chars = Array(grid[r]); chars[c] = "Z"; grid[r] = String(chars)
            }
        }
        if mood == .tired {   // sweat drop
            for (c, r) in [(13, 5), (13, 6), (12, 6), (13, 7)] {
                var chars = Array(grid[r]); chars[c] = "S"; grid[r] = String(chars)
            }
        }
        return grid
    }

    /// One pixel per cell, scaled up by the layer with nearest filtering.
    private static func pixelLayer(_ art: [String], origin: (Int, Int), scale: CGFloat) -> CALayer {
        let w = art.map(\.count).max() ?? 0, h = art.count
        let layer = CALayer()
        layer.frame = rect(col: origin.0, row: origin.1, w: w, h: h)
        layer.magnificationFilter = .nearest
        layer.contentsScale = scale
        layer.contents = image(art)
        return layer
    }

    /// Grid rows count from the top; layer y counts from the bottom.
    static func rect(col: Int, row: Int, w: Int, h: Int) -> CGRect {
        CGRect(x: CGFloat(col) * cell, y: CGFloat(rows - row - h) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell)
    }

    static func image(_ art: [String]) -> CGImage? {
        let w = art.map(\.count).max() ?? 0, h = art.count
        guard w > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (r, line) in art.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let v = colors[ch] else { continue }
                ctx.setFillColor(cg(v))
                ctx.fill(CGRect(x: c, y: h - 1 - r, width: 1, height: 1))   // CG is bottom-up
            }
        }
        return ctx.makeImage()
    }

    static func cg(_ v: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? { Self.size }
}

import AppKit
import SwiftUI

/// Office overview card (spec: Resources/design/office-overview-spec.md).
struct OfficeCard: View {
    @ObservedObject var office: OfficeMonitor
    /// Munder Difflin's location; nil hides the button. Re-checked each time the panel opens.
    @State private var app: Shortcut.App?

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                if let app { ShortcutButton(app: app, label: "Open Munder Difflin") }
            }
            .onAppear { app = Shortcut.app(Shortcut.munderDifflin) }
            // Polls the hive only while shown: panel open, Home tab, Office chosen as the widget.
            .onAppear { office.setActive(true) }
            .onDisappear { office.setActive(false) }
    }

    @ViewBuilder private var content: some View {
        switch office.snapshot {
        case .offline:
            placeholder("moon.zzz", "Office offline", detail: "Munder Difflin isn't running")
        case .rows(let rows) where rows.isEmpty:
            placeholder("person.2", "No one in the office")
        case .rows(let rows):
            GeometryReader { geo in
                let maxRows = max(1, Int((geo.size.height - 20) / 20))
                let overflow = rows.count > maxRows
                let shown = overflow ? Array(rows.prefix(maxRows - 1)) : rows
                VStack(alignment: .leading, spacing: 2) {
                    header(rows).padding(.bottom, 6)
                    ForEach(shown) { OfficeRowView(row: $0) }
                    if overflow {
                        let hidden = rows.dropFirst(maxRows - 1)
                        Text("+\(hidden.count) more")
                            .font(.system(size: 11)).foregroundStyle(.primary.opacity(0.5))
                            .padding(.leading, 16).frame(height: 18)
                            .help(hidden.map { "\($0.name): \($0.state.label)" }.joined(separator: "\n"))
                    }
                    Spacer(minLength: 0)
                }
                .animation(.easeInOut(duration: 0.2), value: rows)
            }
        }
    }

    private func header(_ rows: [OfficeRow]) -> some View {
        let attention = rows.filter { $0.state <= .blocked }.count
        let working = rows.filter { $0.state == .working }.count
        return HStack {
            Text("Office").font(.system(size: 11, weight: .semibold))
            Spacer()
            Group {
                if attention > 0 {
                    Text("\(attention) need you").foregroundStyle(.orange)
                } else if working > 0 {
                    Text("\(working) working")
                } else {
                    Text("All idle")
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            .padding(.trailing, app == nil ? 0 : 22)
        }
        .frame(minHeight: app == nil ? nil : 16) // centres the header text on the 16pt button
        .foregroundStyle(.primary.opacity(0.6))
    }

    private func placeholder(_ symbol: String, _ text: String, detail: String? = nil) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.primary.opacity(0.4))
            Text(text).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.5))
            if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.primary.opacity(0.4)) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OfficeRowView: View {
    let row: OfficeRow

    private var color: Color {
        switch row.state {
        case .breaker: .red
        case .blocked: .orange
        case .working: .green
        case .paused, .idle: .secondary
        }
    }

    private var symbol: String {
        switch row.state {
        case .paused: "pause.fill"
        case .idle: "circle"
        default: "circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if row.state == .working {
                    PulseDot(color: .systemGreen)
                } else {
                    Image(systemName: symbol).font(.system(size: 7)).foregroundStyle(color)
                }
            }
            .frame(width: 10)
            Text(row.name).font(.system(size: 11, weight: .semibold))
                .lineLimit(1).frame(maxWidth: 56, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            Text(row.doing).font(.system(size: 11))
                .foregroundStyle(row.state <= .blocked ? AnyShapeStyle(color) : AnyShapeStyle(.primary.opacity(0.6)))
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(height: 18)
        .opacity(row.state >= .paused ? 0.55 : 1)
        .help("\(row.name)\(row.role.isEmpty ? "" : " · " + row.role)\n\(row.state.label): \(row.doing)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.state.label), \(row.doing)")
    }
}

/// Pulsing 7pt dot for Working rows. A Core Animation opacity animation runs in the window
/// server, so the app does no per-frame work; SwiftUI's .symbolEffect(.pulse) re-rendered the
/// glass panel every frame (~7% CPU with two working rows).
struct PulseDot: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let dot = CALayer()
        dot.frame = CGRect(x: 0, y: 0, width: 7, height: 7)
        dot.cornerRadius = 3.5
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(pulse, forKey: "pulse")
        view.layer?.addSublayer(dot)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Resolve the dynamic system colour for the current appearance.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.sublayers?.first?.backgroundColor = color.cgColor
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: 7, height: 7)
    }
}

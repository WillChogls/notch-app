import AppKit
import SwiftUI

/// The Office tab, v2 (spec: Resources/design/office-tab-v2-spec.md): summary row, then
/// Agents | Limits | Ask me. Read-only. Shares OfficeMonitor with Home's Office card;
/// polls only while this tab is on screen, and reads the limits files only then.
struct OfficeTab: View {
    @ObservedObject var office: OfficeMonitor
    /// The loading state shows only if the first read takes longer than 0.5 s.
    @State private var slow = false

    var body: some View {
        // A ZStack, not bare content: modifiers on an EmptyView (loading, first 0.5 s) never run,
        // so onAppear would never start the poll.
        ZStack { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { office.wantLimits(true); office.setActive(true) }
            .onDisappear { office.wantLimits(false); office.setActive(false) }
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                slow = !Task.isCancelled
            }
    }

    @ViewBuilder private var content: some View {
        switch office.snapshot {
        case .loading:
            if slow {
                VStack(spacing: 8) {
                    LoadingDots().frame(width: 23, height: 5)
                    Text("Opening the office…").font(.system(size: 12)).foregroundStyle(Warm.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        case .offline:
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz").font(.system(size: 22)).foregroundStyle(Warm.ink3)
                Text("Office offline").font(.system(size: 12)).foregroundStyle(Warm.ink2)
                Text("Munder Difflin isn't running").font(.system(size: 10)).foregroundStyle(Warm.ink3)
            }
            .accessibilityElement(children: .combine)
        case .live(let floor):
            VStack(spacing: 6) {
                SummaryRow(floor: floor)
                HStack(spacing: 8) {
                    AgentsCard(floor: floor).officeCard(width: 180, label: "Agents, \(floor.rows.count)")
                    LimitsCard(limits: office.limits).officeCard(width: 188, label: "Limits")
                    AskCard(questions: floor.questions)
                        .officeCard(width: 150, label: "Ask me, \(floor.questions?.count ?? 0) open")
                }
                .frame(height: 116)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Colours (Office tab only, dark only)

enum Warm {
    static let clay = hex(0xD97757)
    static let ink = hex(0xF4EFE6)
    static let ink2 = ink.opacity(0.62)
    static let ink3 = ink.opacity(0.42)
    static let amber = hex(0xF0B54A)
    static let ember = hex(0xE8613C)
    static let dark = hex(0x1A1410)

    static func hex(_ v: Int) -> Color {
        Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension OfficeFloor {
    /// Blocked or breaker agents plus open questions.
    var needYou: Int { rows.filter { $0.state <= .blocked }.count + (questions?.count ?? 0) }
    var blockedCards: Int { tasks?.filter { $0.status == .blocked }.count ?? 0 }
    var working: Int { rows.filter { $0.state == .working }.count }
    /// The summary as plain text (pet tooltip, VoiceOver).
    var summaryText: String {
        let parts = [(needYou, "need you"), (blockedCards, "blocked"), (working, "working")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "All quiet" : parts.joined(separator: " · ")
    }
}

// MARK: - Summary row

private struct SummaryRow: View {
    let floor: OfficeFloor

    var body: some View {
        HStack(spacing: 0) {
            Text("Office").font(.system(size: 12, weight: .semibold)).foregroundStyle(Warm.ink)
            Text("   ")
            parts.font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(1)
            Spacer(minLength: 8)
            (Text(OfficeAge.usd(floor.usd)).foregroundStyle(Warm.ink2) + Text(" spent").foregroundStyle(Warm.ink3))
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .frame(height: 16)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Office: \(floor.summaryText). \(OfficeAge.usd(floor.usd)) spent")
    }

    private var parts: Text {
        var items: [Text] = []
        if floor.needYou > 0 { items.append(Text("\(floor.needYou) need you").fontWeight(.semibold).foregroundStyle(Warm.clay)) }
        if floor.blockedCards > 0 { items.append(Text("\(floor.blockedCards) blocked").foregroundStyle(Warm.amber)) }
        if floor.working > 0 { items.append(Text("\(floor.working) working").foregroundStyle(Warm.ink2)) }
        guard var t = items.first else { return Text("All quiet").foregroundStyle(Warm.ink2) }
        for item in items.dropFirst() { t = t + Text("  ·  ").foregroundStyle(Warm.ink3) + item }
        return t
    }
}

// MARK: - Agents

private struct AgentsCard: View {
    let floor: OfficeFloor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardHeader(title: "Agents") {
                if !floor.rows.isEmpty { Text("\(floor.rows.count)").foregroundStyle(Warm.ink3) }
            }
            if floor.rows.isEmpty {
                CardEmpty(symbol: "person.2", text: "No one in the office")
            } else {
                let (shown, hidden) = OfficeFit.split(floor.rows, 4)
                ForEach(shown) { AgentRow(row: $0) }
                OfficeMore(hidden.map { "\($0.name): \($0.state.label)" })
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: floor.rows)
    }
}

private struct AgentRow: View {
    let row: OfficeRow

    private var color: Color {
        switch row.state {
        case .breaker: .red
        case .blocked: Warm.amber
        case .working: .green
        case .paused, .idle: Warm.ink3
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if row.state == .working {
                    PulseDot(color: .systemGreen)
                } else {
                    Image(systemName: row.state == .paused ? "pause.fill" : row.state == .idle ? "circle" : "circle.fill")
                        .font(.system(size: 7)).foregroundStyle(color)
                }
            }
            .frame(width: 10)
            Text(row.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Warm.ink)
                .lineLimit(1).frame(maxWidth: 56, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            Text(row.doing).font(.system(size: 11))
                .foregroundStyle(row.state <= .blocked ? color : Warm.ink2)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if row.backlog > 0 {
                Text(row.backlog > 99 ? "99+" : "\(row.backlog)")
                    .font(.system(size: 9, weight: .semibold)).monospacedDigit().foregroundStyle(Warm.ink2)
                    .padding(.horizontal, 4).frame(minWidth: 13, minHeight: 13)
                    .background(Capsule().fill(Warm.ink.opacity(0.12)))
                    .fixedSize()
            }
        }
        .frame(height: 18)
        .opacity(row.state >= .paused ? 0.6 : 1)
        .help("\(row.name)\(row.role.isEmpty ? "" : " · " + row.role)\n\(row.state.label): \(row.doing)\n"
              + "\(OfficeAge.usd(row.usd)) · \(row.backlog) unread")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(row.state.label), \(row.doing)\(row.backlog > 0 ? ", \(row.backlog) unread" : "")")
    }
}

// MARK: - Limits (spec v1.1 §4)

private struct LimitsCard: View {
    /// nil: not read yet (loading). `.some(nil)`: unavailable.
    let limits: UsageLimits??

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 2) {
                CardHeader(title: "Limits") { header(now) }
                switch limits {
                case .some(.none):
                    VStack(spacing: 3) {
                        Image(systemName: "gauge.with.dots.needle.0percent").font(.system(size: 16)).foregroundStyle(Warm.ink3)
                        Text("Usage unavailable").font(.system(size: 11)).foregroundStyle(Warm.ink2)
                        Text("Open /usage in Claude Code").font(.system(size: 10)).foregroundStyle(Warm.ink3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                case .some(.some(let l)):
                    VStack(spacing: 4) {
                        LimitMeter(name: "Session", window: "5 h", meter: l.session, limits: l, now: now)
                        LimitMeter(name: "Weekly", window: "7 d", meter: l.weekly, limits: l, now: now)
                    }
                    .opacity(l.stale(now: now) ? 0.7 : 1)
                    Spacer(minLength: 0)
                case .none:   // loading: empty tracks, "–"
                    VStack(spacing: 4) {
                        LimitMeter(name: "Session", window: "5 h", meter: nil, limits: nil, now: now)
                        LimitMeter(name: "Weekly", window: "7 d", meter: nil, limits: nil, now: now)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func header(_ now: Date) -> some View {
        if case .some(.some(let l)) = limits {
            let age = LimitsText.age(now.timeIntervalSince(l.updated))
            if l.stale(now: now) {
                Label("\(age) · /usage", systemImage: "clock.arrow.circlepath")
                    .labelStyle(TightLabel()).font(.system(size: 10, weight: .medium)).foregroundStyle(Warm.amber)
            } else {
                Text(age == "now" ? "Updated now" : "Updated \(age)").font(.system(size: 10, weight: .medium)).foregroundStyle(Warm.ink3)
            }
        }
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

private struct LimitMeter: View {
    let name: String, window: String
    let meter: UsageLimits.Meter?
    let limits: UsageLimits?
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stale = limits?.stale(now: now) ?? false
        let passed = meter?.passed(now) ?? false
        let pct = meter.map { Int($0.percent.rounded()) }
        let shown = passed ? nil : pct          // never an old percent after its reset
        let tint = stale ? Warm.ink3 : (shown ?? 0) >= 80 ? Warm.ember : Warm.clay
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Warm.ink)
                Text(window).font(.system(size: 10)).foregroundStyle(Warm.ink3)
                Spacer(minLength: 2)
                Text(shown.map { "\($0)%" } ?? "–").font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(shown == nil ? Warm.ink3 : tint)
            }
            .frame(height: 14)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Warm.ink.opacity(0.12))
                    if let shown {
                        Capsule().fill(tint).frame(width: max(5, geo.size.width * CGFloat(shown) / 100))
                    }
                    Rectangle().fill(Warm.ink.opacity(0.28)).frame(width: 1).offset(x: geo.size.width * 0.8)
                }
            }
            .frame(height: 5)
            .padding(.top, 3)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: shown)
            resetLine(stale: stale, passed: passed, maxed: shown == 100)
                .lineLimit(1)
                .frame(height: 11)
                .padding(.top, 2)
        }
        .help(tooltip(pct: shown))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(stale: stale, passed: passed, pct: shown))
    }

    @ViewBuilder private func resetLine(stale: Bool, passed: Bool, maxed: Bool) -> some View {
        let reset = meter.flatMap { LimitsText.resets(window: window, at: $0.resetsAt, now: now) } ?? ""
        if meter == nil {
            Text(" ").font(.system(size: 10))
        } else if passed {
            if stale {
                Text("Reset passed · open /usage").font(.system(size: 10)).foregroundStyle(Warm.ink3)
            } else {
                Text("Resetting…").font(.system(size: 10, weight: .medium)).foregroundStyle(Warm.clay)
            }
        } else if maxed && !stale {
            Text("Maxed · \(reset)").font(.system(size: 10, weight: .medium)).foregroundStyle(Warm.ember)
        } else {
            Text(reset).font(.system(size: 10)).foregroundStyle(Warm.ink3)
        }
    }

    private func tooltip(pct: Int?) -> String {
        let span = window == "5 h" ? "5-hour window" : "7-day window"
        guard let limits, let meter else { return "\(name) (\(span))" }
        let at = meter.resetsAt.map { $0.formatted(date: window == "5 h" ? .omitted : .abbreviated, time: .shortened) } ?? "unknown"
        let source = limits.source == .cache ? "~/.claude.json (/usage cache)" : "Office statusline file"
        let used = pct.map { "\($0)% used" } ?? "resetting"
        return "\(name) (\(span)): \(used) · resets \(at) · source: \(source), updated \(OfficeAge.spoken(now.timeIntervalSince(limits.updated)))"
    }

    private func spoken(stale: Bool, passed: Bool, pct: Int?) -> String {
        guard let limits, let meter else { return "\(name), loading" }
        let from = stale ? ", from \(OfficeAge.spoken(now.timeIntervalSince(limits.updated)))" : ""
        if passed { return stale ? "\(name), reset passed, open usage to refresh" : "\(name), resetting" }
        let reset = LimitsText.resetsSpoken(window: window, at: meter.resetsAt, now: now)
        return "\(name), \(pct ?? 0) percent used\(pct == 100 ? ", maxed" : "")\(reset.map { ", " + $0 } ?? "")\(from)"
    }
}

enum LimitsText {
    /// "now", "5m ago", "2h ago", "2 d ago".
    static func age(_ seconds: TimeInterval) -> String {
        let s = OfficeAge.short(seconds)
        if s == "now" { return s }
        return s.hasSuffix("d") ? "\(s.dropLast()) d ago" : "\(s) ago"
    }

    /// "resets in 2 h 05 m" / "resets in 46 m" (minutes rounded up).
    static func resetsIn(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded(.up)))
        return m < 60 ? "resets in \(m) m" : "resets in \(m / 60) h " + String(format: "%02d m", m % 60)
    }

    /// Session counts down; weekly names the day: "resets Mon 11:00".
    static func resets(window: String, at: Date?, now: Date) -> String? {
        guard let at else { return nil }
        if window == "5 h" || at.timeIntervalSince(now) < 86400 { return resetsIn(at.timeIntervalSince(now)) }
        return "resets " + at.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func resetsSpoken(window: String, at: Date?, now: Date) -> String? {
        guard let at else { return nil }
        if window == "5 h" || at.timeIntervalSince(now) < 86400 {
            let m = max(1, Int((at.timeIntervalSince(now) / 60).rounded(.up)))
            let h = m / 60, mm = m % 60
            let parts = [h > 0 ? "\(h) hour\(h == 1 ? "" : "s")" : nil, mm > 0 ? "\(mm) minute\(mm == 1 ? "" : "s")" : nil]
            return "resets in " + parts.compactMap { $0 }.joined(separator: " ")
        }
        return "resets " + at.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

// MARK: - Ask me

private struct AskCard: View {
    let questions: [OfficeQuestion]?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardHeader(title: "Ask me") {
                if let n = questions?.count, n > 0 { Text("\(n) open").foregroundStyle(Warm.clay) }
            }
            if let questions {
                if questions.isEmpty {
                    CardEmpty(symbol: "checkmark.circle", text: "Nothing waiting on you")
                } else {
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 4) {
                            // One question: 3 lines. Two or more: the first 2, 1 line each, then "+N more".
                            let lines = questions.count == 1 ? 3 : 1
                            ForEach(questions.prefix(2)) { item($0, lines: lines, now: context.date) }
                            // 14pt, not 18: two items plus this fill the card's 96pt exactly.
                            OfficeMore(questions.dropFirst(2).map { "\($0.from): \($0.text.prefix(60))" }, height: 14)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: questions)
                    Spacer(minLength: 0)
                }
            } else {
                CardEmpty(symbol: "exclamationmark.triangle", text: "Can't read tasks")
            }
        }
    }

    private func item(_ q: OfficeQuestion, lines: Int, now: Date) -> some View {
        let age = OfficeAge.short(now.timeIntervalSince(q.askedAt))
        return VStack(alignment: .leading, spacing: 1) {
            Text(q.text).font(.system(size: 11)).foregroundStyle(Warm.ink).lineLimit(lines).truncationMode(.tail)
            Text("\(q.from) · \(q.card) · \(age)").font(.system(size: 10)).foregroundStyle(Warm.ink3).lineLimit(1)
        }
        .help("\(q.text)\nAsked by \(q.from) on \(q.card), \(age == "now" ? "just now" : age + " ago")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(q.from) asks: \(q.text), \(OfficeAge.spoken(now.timeIntervalSince(q.askedAt)))")
    }
}

// MARK: - Shared pieces

private struct CardHeader<Right: View>: View {
    let title: String
    @ViewBuilder let right: Right

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Warm.ink2)
            Spacer(minLength: 4)
            right.font(.system(size: 11)).monospacedDigit().lineLimit(1)
        }
        .frame(height: 14)
    }
}

private struct CardEmpty: View {
    let symbol: String, text: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Warm.ink3)
            Text(text).font(.system(size: 11)).foregroundStyle(Warm.ink2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// "+N more" row; its tooltip lists what is hidden. Nothing when nothing is hidden.
private struct OfficeMore: View {
    let hidden: [String]
    var height: CGFloat = 18
    init(_ hidden: [String], height: CGFloat = 18) { self.hidden = hidden; self.height = height }

    var body: some View {
        if !hidden.isEmpty {
            Text("+\(hidden.count) more")
                .font(.system(size: 11)).foregroundStyle(Warm.ink3)
                .padding(.leading, 16).frame(height: height)
                .help(hidden.joined(separator: "\n"))
        }
    }
}

enum OfficeFit {
    /// All items if they fit in `max` rows, else the first max-1 plus the rest for a "+N more" row.
    static func split<T>(_ items: [T], _ max: Int) -> ([T], [T]) {
        items.count > max ? (Array(items.prefix(max - 1)), Array(items.dropFirst(max - 1))) : (items, [])
    }
}

extension View {
    /// Home's card container (padding 10, radius 16, glass); before macOS 26 a warm tinted fill.
    @ViewBuilder fileprivate func officeCard(width: CGFloat, label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let padded = padding(10).frame(width: width, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .top)
        Group {
            if #available(macOS 26, *) {
                padded.glass(shape)
            } else {
                padded.background(shape.fill(Warm.ink.opacity(0.07)))
                    .overlay(shape.stroke(Warm.ink.opacity(0.12), lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

enum OfficeAge {
    /// "now" under a minute, then "4m", "2h", "3d".
    static func short(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "now"
        case ..<3600: "\(Int(seconds / 60))m"
        case ..<86400: "\(Int(seconds / 3600))h"
        default: "\(Int(seconds / 86400))d"
        }
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let s = short(seconds)
        guard s != "now", let n = Int(s.dropLast()) else { return "just now" }
        let unit = ["m": "minute", "h": "hour", "d": "day"][String(s.last!)]!
        return "\(n) \(unit)\(n == 1 ? "" : "s") ago"
    }

    static func badge(_ n: Int) -> String { n > 9 ? "9+" : "\(n)" }
    static func usd(_ v: Double) -> String { String(format: "$%.2f", v) }
}

// MARK: - Tab bar pieces

/// VoiceOver label for a tab button; Office also says how many questions wait.
struct TabLabel: ViewModifier {
    let tab: NotchModel.Tab
    @ObservedObject var office: OfficeMonitor

    func body(content: Content) -> some View {
        guard tab == .office else { return content.accessibilityLabel(tab.label) }
        let n: Int = if case .live(let f) = office.snapshot { f.questions?.count ?? 0 } else { 0 }
        return content.accessibilityLabel("Office, \(n) question\(n == 1 ? "" : "s") waiting")
    }
}

/// Clay count of open ASK ME questions on the Office tab button; hidden at 0, offline and loading.
struct OfficeTabBadge: View {
    @ObservedObject var office: OfficeMonitor

    var body: some View {
        if case .live(let f) = office.snapshot, let n = f.questions?.count, n > 0 {
            Text(OfficeAge.badge(n))
                .font(.system(size: 9, weight: .bold)).monospacedDigit().foregroundStyle(Warm.dark)
                .padding(.horizontal, 3.5)
                .frame(minWidth: 13, minHeight: 13)
                .background(Capsule().fill(Warm.clay))
                .fixedSize()
                .offset(x: 5, y: -4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The pet in the tab bar's left wing, Office tab only; its state follows the summary.
struct OfficePet: View {
    @ObservedObject var office: OfficeMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Each minute, so the tired state ends when a limit resets even if no file changes.
        TimelineView(.everyMinute) { context in pet(context.date) }
    }

    private func pet(_ now: Date) -> some View {
        let snap = office.snapshot
        let state: PixelPet.Mood, help: String, loading: Bool
        switch snap {
        case .loading: (state, help, loading) = (.idle, "Office", true)
        case .offline: (state, help, loading) = (.asleep, "Office offline", false)
        case .live(let f):
            // Blocked > tired (a limit at 90%+, fresh) > working > idle.
            if f.needYou == 0, let t = office.limits??.tired(now: now) {
                (state, help, loading) = (.tired, "\(t.name) limit at \(t.percent)%", false)
            } else {
                (state, help, loading) = (f.needYou > 0 ? .blocked : f.working > 0 ? .working : .idle, "Office: \(f.summaryText)", false)
            }
        }
        // Loading: idle frame A, no motion until the data lands.
        return PixelPet(mood: state, animated: !reduceMotion && !loading)
            .frame(width: PixelPet.size.width, height: PixelPet.size.height)
            .help(help)
            .accessibilityHidden(true)
    }
}

/// Three 5pt dots; one steps every 0.4 s in Core Animation (no per-frame app work). Static under Reduce Motion.
private struct LoadingDots: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        for i in 0..<3 {
            let dot = CALayer()
            dot.frame = CGRect(x: CGFloat(i) * 9, y: 0, width: 5, height: 5)
            dot.cornerRadius = 2.5
            dot.backgroundColor = NSColor.white.cgColor
            dot.opacity = i == 0 ? 0.6 : 0.25
            if !reduceMotion {
                let step = CAKeyframeAnimation(keyPath: "opacity")
                step.values = (0..<3).map { $0 == i ? 0.6 : 0.25 }
                step.keyTimes = [0, 0.3333, 0.6667, 1]
                step.calculationMode = .discrete
                step.duration = 1.2
                step.repeatCount = .infinity
                dot.add(step, forKey: "step")
            }
            view.layer?.addSublayer(dot)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

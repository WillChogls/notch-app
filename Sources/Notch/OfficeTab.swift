import AppKit
import SwiftUI

/// The Office tab (spec: Resources/design/office-tab-spec.md): Agents | Workload | Ask me, read-only.
/// Shares OfficeMonitor with Home's Office card; polls only while this tab is on screen.
struct OfficeTab: View {
    @ObservedObject var office: OfficeMonitor
    /// The loading state shows only if the first read takes longer than 0.5 s.
    @State private var slow = false

    static let maxRows = 5

    var body: some View {
        // A ZStack, not bare content: modifiers on an EmptyView (loading, first 0.5 s) never run,
        // so onAppear would never start the poll.
        ZStack { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { office.setActive(true) }
            .onDisappear { office.setActive(false) }
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
                    Text("Opening the office…").font(.system(size: 12)).foregroundStyle(.primary.opacity(0.5))
                }
                .accessibilityElement(children: .combine)
            }
        case .offline:
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz").font(.system(size: 22)).foregroundStyle(.primary.opacity(0.4))
                Text("Office offline").font(.system(size: 12)).foregroundStyle(.primary.opacity(0.5))
                Text("Munder Difflin isn't running").font(.system(size: 10)).foregroundStyle(.primary.opacity(0.4))
            }
            .accessibilityElement(children: .combine)
        case .live(let floor):
            HStack(spacing: 8) {
                AgentsCard(floor: floor).officeCard(width: 172, label: "Agents, \(floor.rows.count)")
                WorkloadCard(tasks: floor.tasks)
                    .officeCard(width: 194, label: "Workload" + (floor.tasks.map { t in
                        let b = t.filter { $0.status == .blocked }.count
                        return b > 0 ? ", \(b) blocked" : ", \(t.filter { $0.status == .doing }.count) doing"
                    } ?? ""))
                AskCard(questions: floor.questions)
                    .officeCard(width: 152, label: "Ask me, \(floor.questions?.count ?? 0) open")
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Cards

private struct AgentsCard: View {
    let floor: OfficeFloor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            OfficeCardHeader(title: "Agents") {
                Text(OfficeAge.usd(floor.usd)).foregroundStyle(.primary.opacity(0.5))
            }
            if floor.rows.isEmpty {
                OfficeEmpty(symbol: "person.2", text: "No one in the office")
            } else {
                let (shown, hidden) = OfficeFit.split(floor.rows, OfficeTab.maxRows)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { OfficeRowView(row: $0, detailed: true) }
                    OfficeMore(hidden.map { "\($0.name): \($0.state.label)" })
                }
                .animation(.easeInOut(duration: 0.2), value: floor.rows)
            }
        }
    }
}

private struct WorkloadCard: View {
    let tasks: [OfficeTask]?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let tasks {
                let open = tasks.filter { $0.status != .done }
                let done = tasks.filter { $0.status == .done }
                OfficeCardHeader(title: "Workload") {
                    if !tasks.isEmpty { summary(open) }
                }
                .help(done.isEmpty ? "" : "Last done:\n" + done.map { "\($0.id) · \($0.title)" }.joined(separator: "\n"))
                if tasks.isEmpty {
                    OfficeEmpty(symbol: "checklist", text: "No cards")
                } else {
                    // Done cards only fill rows the open ones leave free.
                    let (shown, hidden) = open.count > OfficeTab.maxRows
                        ? OfficeFit.split(open, OfficeTab.maxRows)
                        : (open + done.prefix(OfficeTab.maxRows - open.count), [])
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { TaskRow(task: $0) }
                        OfficeMore(hidden.map { "\($0.id) · \($0.title)" })
                    }
                    .animation(.easeInOut(duration: 0.2), value: tasks)
                }
            } else {
                OfficeCardHeader(title: "Workload") { EmptyView() }
                OfficeEmpty(symbol: "exclamationmark.triangle", text: "Can't read tasks")
            }
        }
    }

    @ViewBuilder private func summary(_ open: [OfficeTask]) -> some View {
        let blocked = open.filter { $0.status == .blocked }.count
        let doing = open.filter { $0.status == .doing }.count
        let todo = open.filter { $0.status == .todo }.count
        if blocked > 0 {
            Text("\(blocked) blocked").foregroundStyle(.orange)
                + Text(" · \(doing + todo)").foregroundStyle(.primary.opacity(0.5))
        } else {
            Text("\(doing) doing · \(todo) todo").foregroundStyle(.primary.opacity(0.5))
        }
    }
}

private struct TaskRow: View {
    let task: OfficeTask

    private var mark: (String, Color) {
        switch task.status {
        case .blocked: ("exclamationmark.circle.fill", .orange)
        case .doing: ("circle.fill", .green)
        case .todo: ("circle", .secondary)
        case .done: ("checkmark.circle", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mark.0).font(.system(size: 8)).foregroundStyle(mark.1).frame(width: 10)
            Text(task.id).font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(.primary.opacity(0.5)).fixedSize()
            Text(task.title).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if let who = task.assignee, let initial = who.first {
                Text(String(initial).uppercased()).font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(.white.opacity(0.14)))
            }
        }
        .frame(height: 18)
        .opacity(task.status == .done ? 0.55 : 1)
        .help("\(task.id) · \(task.title)\n\(task.status.label)\(task.assignee.map { " · " + $0 } ?? "")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(task.id), \(task.title), \(task.status.label.lowercased())\(task.assignee.map { ", " + $0 } ?? "")")
    }
}

private struct AskCard: View {
    let questions: [OfficeQuestion]?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            OfficeCardHeader(title: "Ask me") {
                if let n = questions?.count, n > 0 { Text("\(n) open").foregroundStyle(.orange) }
            }
            if let questions {
                if questions.isEmpty {
                    OfficeEmpty(symbol: "checkmark.circle", text: "Nothing waiting on you")
                } else {
                    // 2 fit; with 3 or more, 1 and "+N more".
                    let (shown, hidden) = OfficeFit.split(questions, 2)
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(shown) { item($0, now: context.date) }
                            OfficeMore(hidden.map { "\($0.from): \($0.text.prefix(60))" })
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: questions)
                }
            } else {
                OfficeEmpty(symbol: "exclamationmark.triangle", text: "Can't read tasks")
            }
        }
    }

    private func item(_ q: OfficeQuestion, now: Date) -> some View {
        let age = OfficeAge.short(now.timeIntervalSince(q.askedAt))
        return VStack(alignment: .leading, spacing: 1) {
            Text(q.text).font(.system(size: 11)).lineLimit(2).truncationMode(.tail)
            Text("\(q.from) · \(q.card) · \(age)").font(.system(size: 10)).foregroundStyle(.primary.opacity(0.5)).lineLimit(1)
        }
        .frame(height: 42, alignment: .top)
        .help("\(q.text)\nAsked by \(q.from) on \(q.card), \(age == "now" ? "just now" : age + " ago")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(q.from) asks: \(q.text), \(OfficeAge.spoken(now.timeIntervalSince(q.askedAt)))")
    }
}

// MARK: - Shared pieces

private struct OfficeCardHeader<Right: View>: View {
    let title: String
    @ViewBuilder let right: Right

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary.opacity(0.6))
            Spacer(minLength: 4)
            right.font(.system(size: 11)).monospacedDigit().lineLimit(1)
        }
        .frame(height: 14)
    }
}

private struct OfficeEmpty: View {
    let symbol: String, text: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(.primary.opacity(0.4))
            Text(text).font(.system(size: 11)).foregroundStyle(.primary.opacity(0.5))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// "+N more" row; its tooltip lists what is hidden. Nothing when nothing is hidden.
private struct OfficeMore: View {
    let hidden: [String]
    init(_ hidden: [String]) { self.hidden = hidden }

    var body: some View {
        if !hidden.isEmpty {
            Text("+\(hidden.count) more")
                .font(.system(size: 11)).foregroundStyle(.primary.opacity(0.5))
                .padding(.leading, 16).frame(height: 18)
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
    /// Same container as Home's cards: padding 10, glass radius 16, full height, top-aligned.
    fileprivate func officeCard(width: CGFloat, label: String) -> some View {
        padding(10)
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : n >= 1000 ? "\(n / 1000)k" : "\(n)"
    }
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

/// Orange count of open ASK ME questions on the Office tab button; hidden at 0, offline and loading.
struct OfficeTabBadge: View {
    @ObservedObject var office: OfficeMonitor

    var body: some View {
        if case .live(let f) = office.snapshot, let n = f.questions?.count, n > 0 {
            Text(OfficeAge.badge(n))
                .font(.system(size: 9, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 3.5)
                .frame(minWidth: 13, minHeight: 13)
                .background(Capsule().fill(.orange))
                .fixedSize()
                .offset(x: 5, y: -4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// One phrase left of the battery, Office tab only: "N need you", else "N working", else "All idle".
struct OfficeSummary: View {
    @ObservedObject var office: OfficeMonitor

    var body: some View {
        if case .live(let f) = office.snapshot {
            let need = f.rows.filter { $0.state <= .blocked }.count
            let working = f.rows.filter { $0.state == .working }.count
            Group {
                if need > 0 {
                    Text("\(need) need you").foregroundStyle(.orange)
                } else {
                    Text(working > 0 ? "\(working) working" : "All idle").foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
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

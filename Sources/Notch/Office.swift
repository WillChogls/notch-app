import Foundation

/// Live overview of the Munder Difflin office, read (never written) from the hive's
/// fleet.json + tasks.json. Spec: Resources/design/office-overview-spec.md.
enum OfficeState: Int, Comparable {
    case breaker, blocked, working, paused, idle
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .breaker: "Breaker tripped"
        case .blocked: "Needs you"
        case .working: "Working"
        case .paused: "On hold"
        case .idle: "Idle"
        }
    }
}

struct OfficeRow: Equatable, Identifiable {
    let id: String
    let name: String
    let role: String
    let state: OfficeState
    /// Full doing text, e.g. "Needs you · Review plan" or "Active · Bash".
    let doing: String
}

enum OfficeSnapshot: Equatable {
    case offline
    case rows([OfficeRow])

    /// NOTCH_HIVE_ROOT overrides it for testing (fake or missing hive).
    static let hiveRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_HIVE_ROOT"] ?? "/Users/willwhite/office/hive")
    /// fleet.json is rewritten every few seconds; older than this means the office isn't running.
    static let staleAfter: TimeInterval = 120

    private struct Fleet: Decodable {
        let ts: Double
        let agents: [Agent]
    }
    private struct Agent: Decodable {
        let id: String
        let name: String?
        let role: String?
        let breaker: String?
        let onHold: Bool?
        let lastTool: String?
        let lastActiveSecAgo: Double?
    }
    private struct Tasks: Decodable { let tasks: [Card] }
    private struct Card: Decodable {
        let title: String?
        let status: String?
        let assignee: String?
    }

    /// Pure: state rules first-match-wins, then sort by state and name.
    /// Latest turn start / turn end per agent id, from the tail of hive/log.jsonl.
    struct TurnLog: Equatable {
        var lastSubmit: [String: Double] = [:]
        var lastEnd: [String: Double] = [:]

        private struct Event: Decodable {
            let ts: Double?
            let kind: String?
            let agentId: String?
            let outcome: String?
            let why: String?
        }

        /// `tail` is the last bytes of the log; `partial` = it starts mid-line (drop the first line).
        static func parse(_ tail: Data, partial: Bool) -> TurnLog {
            var log = TurnLog()
            var lines = tail.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            if partial, !lines.isEmpty { lines.removeFirst() }
            let decoder = JSONDecoder()
            for line in lines {
                guard line.count < 4096, let e = try? decoder.decode(Event.self, from: Data(line)),
                      let id = e.agentId, let ts = e.ts else { continue }
                if e.kind == "pty-submit", e.outcome == "submitted" {
                    log.lastSubmit[id] = max(log.lastSubmit[id] ?? 0, ts)
                } else if e.kind == "inbox-settled", e.why == "turn-end" {
                    log.lastEnd[id] = max(log.lastEnd[id] ?? 0, ts)
                }
            }
            return log
        }
    }

    /// Working = mid-turn per the log (latest counted submit after latest turn end), unless fleet says
    /// it has been quiet > 600 s (a missed turn end must not stick). No log or no events for the
    /// agent: fall back to fleet activity in the last 15 s.
    static func isWorking(submit: Double?, end: Double?, lastActiveSecAgo: Double?) -> Bool {
        let ago = lastActiveSecAgo ?? .infinity
        guard submit != nil || end != nil else { return ago < 15 }
        return (submit ?? 0) > (end ?? 0) && ago <= 600
    }

    static func parse(fleet: Data?, tasks: Data?, log: TurnLog? = nil, now: Date) -> OfficeSnapshot {
        guard let fleet, let f = try? JSONDecoder().decode(Fleet.self, from: fleet),
              now.timeIntervalSince1970 - f.ts / 1000 < staleAfter else { return .offline }
        let cards = (tasks.flatMap { try? JSONDecoder().decode(Tasks.self, from: $0) })?.tasks ?? []
        func card(_ id: String, _ status: String) -> String? {
            cards.first { $0.assignee == id && $0.status == status }.map { $0.title ?? "" }
        }
        let rows = f.agents.map { a -> OfficeRow in
            let state: OfficeState
            let doing: String
            if let b = a.breaker, b != "healthy" {
                (state, doing) = (.breaker, "Breaker tripped")
            } else if let t = card(a.id, "blocked") {
                (state, doing) = (.blocked, "Needs you · " + t)
            } else if a.onHold == true {
                (state, doing) = (.paused, "On hold")
            } else if isWorking(submit: log?.lastSubmit[a.id], end: log?.lastEnd[a.id], lastActiveSecAgo: a.lastActiveSecAgo) {
                (state, doing) = (.working, card(a.id, "doing") ?? "Active · " + (a.lastTool ?? "working"))
            } else {
                // A doing card only supplies the text; the row stays idle (dimmed).
                (state, doing) = (.idle, card(a.id, "doing") ?? "Idle")
            }
            return OfficeRow(id: a.id, name: a.name ?? a.id, role: a.role ?? "", state: state, doing: doing)
        }
        return .rows(rows.sorted { ($0.state, $0.name.lowercased()) < ($1.state, $1.name.lowercased()) })
    }
}

/// Polls the hive every 5 s, only while the panel is open. Parses off the main thread and
/// skips the parse when neither file changed (still re-checks staleness).
@MainActor
final class OfficeMonitor: ObservableObject {
    @Published private(set) var snapshot: OfficeSnapshot = .offline

    private var task: Task<Void, Never>?
    /// Per file: (mtime + size stamp, parsed value), so unchanged files are not re-read.
    private var cache = Cache()

    struct Cache: Sendable {
        var fleet: (String?, Data?) = (nil, nil)
        var tasks: (String?, Data?) = (nil, nil)
        var log: (String?, OfficeSnapshot.TurnLog?) = (nil, nil)
    }

    func setActive(_ active: Bool) {
        task?.cancel()
        task = nil
        guard active else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refresh() async {
        let root = OfficeSnapshot.hiveRoot
        let old = cache
        let (new, snap) = await Task.detached(priority: .utility) { () -> (Cache, OfficeSnapshot) in
            func stamp(_ name: String) -> String? {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path),
                      let date = attrs[.modificationDate] as? Date else { return nil }
                return "\(date.timeIntervalSince1970)|\(attrs[.size] as? Int ?? 0)"
            }
            var c = old
            let fs = stamp("fleet.json"), ts = stamp("tasks.json"), ls = stamp("log.jsonl")
            if fs != c.fleet.0 { c.fleet = (fs, try? Data(contentsOf: root.appendingPathComponent("fleet.json"))) }
            if ts != c.tasks.0 { c.tasks = (ts, try? Data(contentsOf: root.appendingPathComponent("tasks.json"))) }
            if ls != c.log.0 { c.log = (ls, Self.readLogTail(root.appendingPathComponent("log.jsonl"))) }
            return (c, OfficeSnapshot.parse(fleet: c.fleet.1, tasks: c.tasks.1, log: c.log.1, now: .now))
        }.value
        guard !Task.isCancelled else { return }
        cache = new
        if snapshot != snap { snapshot = snap }
    }

    /// Last 256 KB of the append-only log, never the whole file.
    nonisolated static func readLogTail(_ url: URL) -> OfficeSnapshot.TurnLog? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return nil }
        let start = size > 262_144 ? size - 262_144 : 0
        guard (try? h.seek(toOffset: start)) != nil, let data = try? h.readToEnd() else { return nil }
        return .parse(data, partial: start > 0)
    }
}

/// Runs with the equalizer self-check (`NOTCH_SELFCHECK=1`).
enum OfficeSelfCheck {
    static func run() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ts = now.timeIntervalSince1970 * 1000
        let fleet = """
        {"ts": \(ts), "agents": [
          {"id":"k","name":"Kevin","breaker":"healthy","onHold":false,"lastTool":"Read","lastActiveSecAgo":900},
          {"id":"d","name":"Dwight","breaker":"healthy","onHold":true,"lastActiveSecAgo":3},
          {"id":"j","name":"Jim","role":"Senior software engineer","breaker":"healthy","lastTool":"Bash","lastActiveSecAgo":4},
          {"id":"p","name":"Pam","breaker":"healthy","lastActiveSecAgo":500},
          {"id":"o","name":"Oscar","breaker":"tripped","lastActiveSecAgo":1},
          {"id":"a","name":"Angela","breaker":"healthy","lastActiveSecAgo":999}]}
        """.data(using: .utf8)!
        let tasks = """
        {"tasks":[{"id":"1","title":"Review plan","status":"blocked","assignee":"p"},
                  {"id":"2","title":"Ship it","status":"doing","assignee":"a"},
                  {"id":"3","title":"Old","status":"done","assignee":"k"}]}
        """.data(using: .utf8)!
        guard case .rows(let rows) = OfficeSnapshot.parse(fleet: fleet, tasks: tasks, now: now) else {
            preconditionFailure("fresh fleet read as offline")
        }
        // No log: 15 s fallback. Angela has a doing card but is quiet, so she is an idle row with its title.
        precondition(rows.map(\.name) == ["Oscar", "Pam", "Jim", "Dwight", "Angela", "Kevin"], "\(rows.map(\.name))")
        precondition(rows.map(\.doing) == ["Breaker tripped", "Needs you · Review plan", "Active · Bash", "On hold", "Ship it", "Idle"],
                     "\(rows.map(\.doing))")
        // Garbage tasks.json: fleet-only rows, no crash. Stale or missing fleet: offline.
        guard case .rows(let bare) = OfficeSnapshot.parse(fleet: fleet, tasks: Data("{nope".utf8), now: now) else {
            preconditionFailure("bad tasks.json took the card offline")
        }
        precondition(bare.first { $0.name == "Pam" }?.state == .idle)
        precondition(OfficeSnapshot.parse(fleet: fleet, tasks: tasks, now: now + 121) == .offline)
        precondition(OfficeSnapshot.parse(fleet: nil, tasks: tasks, now: now) == .offline)
        precondition(OfficeSnapshot.parse(fleet: Data("garbage".utf8), tasks: nil, now: now) == .offline)
        // Working rule from log.jsonl (turn start = submitted pty-submit, turn end = inbox-settled turn-end).
        func ev(_ id: String, _ kind: String, ts: Int, outcome: String = "submitted") -> String {
            kind == "submit"
                ? #"{"ts":\#(ts),"kind":"pty-submit","agentId":"\#(id)","outcome":"\#(outcome)"}"#
                : #"{"ts":\#(ts),"kind":"inbox-settled","agentId":"\#(id)","why":"turn-end"}"#
        }
        let lines = [#"{"ts":1,"kind":"pty-sub"#,  // partial first line of the tail window
                     ev("a", "submit", ts: 10), ev("a", "end", ts: 20),           // a: finished turn
                     ev("b", "end", ts: 10), ev("b", "submit", ts: 20),           // b: mid-turn
                     ev("c", "end", ts: 10), ev("c", "submit", ts: 20, outcome: "unconfirmed"),
                     "not json"]
        let log = OfficeSnapshot.TurnLog.parse(Data(lines.joined(separator: "\n").utf8), partial: true)
        func working(_ id: String, _ ago: Double) -> Bool {
            OfficeSnapshot.isWorking(submit: log.lastSubmit[id], end: log.lastEnd[id], lastActiveSecAgo: ago)
        }
        precondition(!working("a", 5), "submit then turn-end must be Idle")
        precondition(working("b", 5), "turn-end then submit must be Working")
        precondition(!working("c", 5), "unconfirmed submit must be ignored")
        precondition(!working("b", 700), "working by log but quiet 700 s must be Idle")
        precondition(working("x", 10) && !working("x", 200), "no events: 15 s fallback")
        precondition(OfficeMonitor.readLogTail(URL(fileURLWithPath: "/nonexistent/log.jsonl")) == nil, "missing log")
        precondition(OfficeSnapshot.isWorking(submit: nil, end: nil, lastActiveSecAgo: 10), "missing log: fallback")
        // Idle agent with a doing card: dimmed idle row showing the card title.
        let idleLog = OfficeSnapshot.TurnLog(lastSubmit: ["a": 1], lastEnd: ["a": 2])
        guard case .rows(let withLog) = OfficeSnapshot.parse(fleet: fleet, tasks: tasks, log: idleLog, now: now),
              let angela = withLog.first(where: { $0.name == "Angela" }) else { preconditionFailure() }
        precondition(angela.state == .idle && angela.doing == "Ship it", "\(angela)")
        print("office self-check passed")
    }
}

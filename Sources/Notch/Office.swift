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
    var usd: Double = 0
    var tokens: Int = 0
    var backlog: Int = 0
}

/// A tasks.json card for the Office tab's Workload.
struct OfficeTask: Equatable, Identifiable {
    enum Status: Int, Comparable {
        case blocked, doing, todo, done
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        var label: String { ["Blocked", "Doing", "Todo", "Done"][rawValue] }
    }
    let id: String
    let title: String
    let status: Status
    /// Display name (fleet name when known); nil when unassigned.
    let assignee: String?
}

/// An open ASK ME question: a humanQA entry with no answer.
struct OfficeQuestion: Equatable, Identifiable {
    var id: String { card + "|" + String(askedAt.timeIntervalSince1970) }
    let text: String
    let from: String
    let card: String
    let askedAt: Date
}

/// Everything one read of the hive gives: the Home card uses `rows`, the Office tab all of it.
struct OfficeFloor: Equatable {
    var rows: [OfficeRow]
    var usd: Double = 0
    /// Blocked, doing, todo (file order within each), then the last 3 done; nil = tasks.json unreadable.
    var tasks: [OfficeTask]? = []
    /// Newest first; nil = tasks.json unreadable.
    var questions: [OfficeQuestion]? = []
}

enum OfficeSnapshot: Equatable {
    /// Before the first read finishes.
    case loading
    case offline
    case live(OfficeFloor)

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
        let usd: Double?
        let tokens: Double?
        let inboxBacklog: Int?
    }
    private struct Tasks: Decodable { let tasks: [Card] }
    private struct Card: Decodable {
        let id: String?
        let title: String?
        let status: String?
        let assignee: String?
        let doneAt: String?
        let humanQA: [QA]?
    }
    private struct QA: Decodable {
        let q: String?
        let from: String?
        let askedAt: String?
        let a: String?
    }

    /// ISO 8601 with any number of fractional digits (the hive writes 3 or 6).
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// Questions are markdown; the notch shows plain text on one flowing line.
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression) // [text](url)
            .replacingOccurrences(of: #"(?<![\w*_])[*_]{1,2}([^*_\n]+?)[*_]{1,2}(?![\w*_])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
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
        let decoded = (tasks.flatMap { try? JSONDecoder().decode(Tasks.self, from: $0) })?.tasks
        let cards = decoded ?? []
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
            return OfficeRow(id: a.id, name: a.name ?? a.id, role: a.role ?? "", state: state, doing: doing,
                             usd: a.usd ?? 0, tokens: Int(a.tokens ?? 0), backlog: a.inboxBacklog ?? 0)
        }
        var floor = OfficeFloor(rows: rows.sorted { ($0.state, $0.name.lowercased()) < ($1.state, $1.name.lowercased()) },
                                usd: f.agents.reduce(0) { $0 + ($1.usd ?? 0) }, tasks: nil, questions: nil)
        guard let decoded else { return .live(floor) }
        let names = Dictionary(f.agents.map { ($0.id, $0.name ?? $0.id) }, uniquingKeysWith: { a, _ in a })
        func task(_ c: Card, _ s: OfficeTask.Status) -> OfficeTask {
            OfficeTask(id: c.id ?? "", title: c.title ?? "", status: s, assignee: c.assignee.map { names[$0] ?? $0 })
        }
        let statuses: [String: OfficeTask.Status] = ["blocked": .blocked, "doing": .doing, "todo": .todo]
        let open = decoded.compactMap { c in c.status.flatMap { statuses[$0] }.map { task(c, $0) } }
        let done = decoded.filter { $0.status == "done" }
            .sorted { (date($0.doneAt) ?? .distantPast) > (date($1.doneAt) ?? .distantPast) }
            .prefix(3).map { task($0, .done) }
        floor.tasks = open.enumerated().sorted { ($0.element.status, $0.offset) < ($1.element.status, $1.offset) }.map(\.element) + done
        floor.questions = decoded.flatMap { c in
            (c.humanQA ?? []).compactMap { qa -> OfficeQuestion? in
                guard qa.a == nil, let q = qa.q, let at = date(qa.askedAt) else { return nil }
                return OfficeQuestion(text: plain(q), from: qa.from.map { names[$0] ?? $0 } ?? "", card: c.id ?? "", askedAt: at)
            }
        }.sorted { $0.askedAt > $1.askedAt }
        return .live(floor)
    }
}

/// Polls the hive every 5 s, only while the panel is open. Parses off the main thread and
/// skips the parse when neither file changed (still re-checks staleness).
@MainActor
final class OfficeMonitor: ObservableObject {
    @Published private(set) var snapshot: OfficeSnapshot = .loading

    private var task: Task<Void, Never>?
    /// Views that need live data (Home's Office card, the Office tab). Counted, so a tab switch can't
    /// stop the poll whichever of onAppear / onDisappear runs first.
    private var users = 0
    /// Per file: (mtime + size stamp, parsed value), so unchanged files are not re-read.
    private var cache = Cache()

    struct Cache: Sendable {
        var fleet: (String?, Data?) = (nil, nil)
        var tasks: (String?, Data?) = (nil, nil)
        var log: (String?, OfficeSnapshot.TurnLog?) = (nil, nil)
    }

    func setActive(_ active: Bool) {
        users = max(0, users + (active ? 1 : -1))
        guard (users > 0) != (task != nil) else { return }
        task?.cancel()
        task = nil
        guard users > 0 else { return }
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
        guard case .live(let floor) = OfficeSnapshot.parse(fleet: fleet, tasks: tasks, now: now) else {
            preconditionFailure("fresh fleet read as offline")
        }
        let rows = floor.rows
        // No log: 15 s fallback. Angela has a doing card but is quiet, so she is an idle row with its title.
        precondition(rows.map(\.name) == ["Oscar", "Pam", "Jim", "Dwight", "Angela", "Kevin"], "\(rows.map(\.name))")
        precondition(rows.map(\.doing) == ["Breaker tripped", "Needs you · Review plan", "Active · Bash", "On hold", "Ship it", "Idle"],
                     "\(rows.map(\.doing))")
        // Garbage tasks.json: fleet-only rows, no crash. Stale or missing fleet: offline.
        guard case .live(let bareFloor) = OfficeSnapshot.parse(fleet: fleet, tasks: Data("{nope".utf8), now: now) else {
            preconditionFailure("bad tasks.json took the card offline")
        }
        precondition(bareFloor.rows.first { $0.name == "Pam" }?.state == .idle)
        precondition(bareFloor.tasks == nil && bareFloor.questions == nil, "bad tasks.json must read as unreadable")
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
        guard case .live(let withLog) = OfficeSnapshot.parse(fleet: fleet, tasks: tasks, log: idleLog, now: now),
              let angela = withLog.rows.first(where: { $0.name == "Angela" }) else { preconditionFailure() }
        precondition(angela.state == .idle && angela.doing == "Ship it", "\(angela)")
        OfficeTabSelfCheck.run(now: now, fleet: fleet)
        print("office self-check passed")
    }
}

/// Office tab parsing (OFF-17): workload grouping, open ASK ME questions, costs.
enum OfficeTabSelfCheck {
    static func run(now: Date, fleet _: Data) {
        let ts = now.timeIntervalSince1970 * 1000
        let fleet = """
        {"ts": \(ts), "agents": [
          {"id":"p","name":"Pam","usd":1.5,"tokens":340000,"inboxBacklog":2,"lastActiveSecAgo":900},
          {"id":"j","name":"Jim","usd":2.62,"lastActiveSecAgo":900}]}
        """.data(using: .utf8)!
        let tasks = #"""
        {"tasks":[
          {"id":"OFF-1","title":"Todo one","status":"todo","assignee":"j"},
          {"id":"OFF-2","title":"Doing","status":"doing","assignee":"p"},
          {"id":"OFF-3","title":"Done old","status":"done","doneAt":"2026-01-01T00:00:00.000Z"},
          {"id":"OFF-4","title":"Blocked","status":"blocked","assignee":"zed",
           "humanQA":[{"q":"**Ship it?**\n\nRun `x`.","from":"p","askedAt":"2026-01-02T00:00:00.123456+00:00"},
                      {"q":"answered","from":"j","askedAt":"2026-01-03T00:00:00Z","a":"yes"}]},
          {"id":"OFF-5","title":"Done 2","status":"done","doneAt":"2026-01-05T00:00:00.000Z"},
          {"id":"OFF-6","title":"Done 3","status":"done","doneAt":"2026-01-04T00:00:00.000Z"},
          {"id":"OFF-7","title":"Done newest","status":"done","doneAt":"2026-01-06T00:00:00.000Z",
           "humanQA":[{"q":"Newer","from":"j","askedAt":"2026-01-07T00:00:00.5Z"}]},
          {"id":"OFF-8","title":"Todo two","status":"todo"},
          {"id":"OFF-9","title":"Weird","status":"someday"}]}
        """#.data(using: .utf8)!
        guard case .live(let f) = OfficeSnapshot.parse(fleet: fleet, tasks: tasks, now: now),
              let t = f.tasks, let q = f.questions else { preconditionFailure("office tab: no floor") }
        precondition(t.map(\.id) == ["OFF-4", "OFF-2", "OFF-1", "OFF-8", "OFF-7", "OFF-5", "OFF-6"], "\(t.map(\.id))")
        precondition(t.map(\.assignee) == ["zed", "Pam", "Jim", nil, nil, nil, nil], "assignee names: \(t.map(\.assignee))")
        precondition(q.map(\.card) == ["OFF-7", "OFF-4"] && q.map(\.from) == ["Jim", "Pam"], "open questions: \(q)")
        precondition(q[1].text == "Ship it? Run x.", "plain text: \(q[1].text)")
        precondition(OfficeSnapshot.plain("Is _it_ *ok*? See [the spec](http://x) or snake_case_name.")
                     == "Is it ok? See the spec or snake_case_name.", OfficeSnapshot.plain("Is _it_ *ok*? See [the spec](http://x) or snake_case_name."))
        precondition(abs(f.usd - 4.12) < 0.001, "floor cost \(f.usd)")
        let pam = f.rows.first { $0.name == "Pam" }
        precondition(pam?.tokens == 340_000 && pam?.backlog == 2, "fleet extras")
        precondition(OfficeSnapshot.date("2026-11-08T18:24:41.900300+00:00") != nil, "6-digit fraction")
        // No tasks file at all: fleet rows, workload and questions unreadable.
        guard case .live(let noTasks) = OfficeSnapshot.parse(fleet: fleet, tasks: nil, now: now) else { preconditionFailure() }
        precondition(noTasks.rows.count == 2 && noTasks.tasks == nil)
        precondition(OfficeAge.short(60 * 4) == "4m" && OfficeAge.short(30) == "now" && OfficeAge.short(7200) == "2h"
                     && OfficeAge.short(3 * 86400) == "3d" && OfficeAge.badge(12) == "9+", "age / badge format")
    }
}

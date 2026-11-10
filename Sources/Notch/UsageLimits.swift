import Foundation

/// The account's Claude session (5 h) and weekly (7 d) limits for the Office tab's Limits card (OFF-18).
/// Sources, read-only, never the Keychain or the network:
///  - live: hive/usage-limits.json, written by the hive's statusline hook (`{ts, rate_limits}`);
///  - fallback: ONLY the `cachedUsageUtilization` key of ~/.claude.json (what /usage last fetched).
/// The newer one wins; the fallback is always shown as stale.
struct UsageLimits: Equatable, Sendable {
    struct Meter: Equatable, Sendable {
        var percent: Double        // 0...100
        var resetsAt: Date?
    }
    enum Source: Equatable, Sendable { case statusline, cache }

    var session: Meter?
    var weekly: Meter?
    var updated: Date
    var source: Source

    /// From the fallback, or more than 1 h old.
    func stale(now: Date) -> Bool { source == .cache || now.timeIntervalSince(updated) > 3600 }

    /// The meter at or over 90% that makes the pet tired (fresh data, not reset yet), highest first.
    func tired(now: Date) -> (name: String, percent: Int)? {
        guard !stale(now: now) else { return nil }
        return [("Session", session), ("Weekly", weekly)]
            .compactMap { name, m in m.flatMap { $0.percent >= 90 && !$0.passed(now) ? (name, Int($0.percent.rounded())) : nil } }
            .max { $0.1 < $1.1 }
    }

    nonisolated static let liveFile = "usage-limits.json"
    nonisolated static let cacheURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_CLAUDE_JSON"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json").path)

    /// `{"ts": ms, "rate_limits": {"five_hour": {"used_percentage", "resets_at"}, "seven_day": {...}}}`
    static func parseLive(_ data: Data?) -> UsageLimits? {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = root["rate_limits"] as? [String: Any], let ts = date(root["ts"]) else { return nil }
        return make(rl, percentKey: "used_percentage", updated: ts, source: .statusline)
    }

    /// Reads only `cachedUsageUtilization` (`{fetchedAtMs, utilization: {five_hour: {utilization, resets_at}}}`).
    static func parseCache(_ data: Data?) -> UsageLimits? {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let c = root["cachedUsageUtilization"] as? [String: Any],
              let u = c["utilization"] as? [String: Any], let ts = date(c["fetchedAtMs"]) else { return nil }
        return make(u, percentKey: "utilization", updated: ts, source: .cache)
    }

    static func pick(_ live: UsageLimits?, _ cache: UsageLimits?) -> UsageLimits? {
        guard let live, let cache else { return live ?? cache }
        return cache.updated > live.updated ? cache : live
    }

    private static func make(_ windows: [String: Any], percentKey: String, updated: Date, source: Source) -> UsageLimits? {
        func meter(_ key: String) -> Meter? {
            guard let w = windows[key] as? [String: Any], let p = (w[percentKey] as? NSNumber)?.doubleValue else { return nil }
            // ponytail: a non-whole value up to 1 is a fraction (0.25 = 25%); a whole 1 stays 1%.
            let pct = p <= 1 && p != p.rounded() ? p * 100 : p
            return Meter(percent: min(max(pct, 0), 100), resetsAt: date(w["resets_at"]))
        }
        let s = meter("five_hour"), w = meter("seven_day")
        guard s != nil || w != nil else { return nil }
        return UsageLimits(session: s, weekly: w, updated: updated, source: source)
    }

    /// Epoch seconds or milliseconds, or an ISO 8601 string.
    static func date(_ v: Any?) -> Date? {
        if let n = v as? NSNumber, !(v is Bool) {
            let d = n.doubleValue
            return Date(timeIntervalSince1970: d > 1e11 ? d / 1000 : d)
        }
        return (v as? String).flatMap(OfficeSnapshot.date)
    }
}

extension UsageLimits.Meter {
    func passed(_ now: Date) -> Bool { resetsAt.map { now >= $0 } ?? false }
}

/// Runs with the office self-check (`NOTCH_SELFCHECK=1`).
enum UsageLimitsSelfCheck {
    static func run() {
        let now = Date(timeIntervalSince1970: 1_794_266_625)
        func d(_ s: String) -> Data { s.data(using: .utf8)! }
        // Live shape as the statusline writes it today: whole percent, epoch-second resets, ms ts.
        let live = UsageLimits.parseLive(d(#"{"ts":1794266625536,"rate_limits":{"five_hour":{"used_percentage":62,"resets_at":1794278400},"seven_day":{"used_percentage":14,"resets_at":1794826800}}}"#))
        precondition(live?.session?.percent == 62 && live?.weekly?.percent == 14 && live?.source == .statusline, "live \(String(describing: live))")
        precondition(live?.session?.resetsAt == Date(timeIntervalSince1970: 1_794_278_400), "epoch resets")
        precondition(live?.stale(now: now) == false && live?.tired(now: now) == nil, "fresh, not tired")
        // Fraction percent and ISO resets.
        let frac = UsageLimits.parseLive(d(#"{"ts":"2026-11-09T23:00:00Z","rate_limits":{"five_hour":{"used_percentage":0.25,"resets_at":"2026-11-10T01:00:00.123456+00:00"}}}"#))
        precondition(frac?.session?.percent == 25 && frac?.session?.resetsAt != nil && frac?.weekly == nil, "fraction / ISO \(String(describing: frac))")
        // Fallback: only cachedUsageUtilization, always stale.
        let cache = UsageLimits.parseCache(d(#"{"other":{"x":1},"cachedUsageUtilization":{"fetchedAtMs":1794055840868,"utilization":{"five_hour":{"utilization":25,"resets_at":"2026-11-07T17:29:59.811364+00:00"},"seven_day":{"utilization":15,"resets_at":"2026-11-09T10:59:59.811381+00:00"}}}}"#))
        precondition(cache?.session?.percent == 25 && cache?.source == .cache && cache?.stale(now: now) == true, "cache")
        precondition(cache?.session?.passed(now) == true, "past reset")
        // Newer wins.
        precondition(UsageLimits.pick(live, cache)?.source == .statusline && UsageLimits.pick(nil, cache)?.source == .cache, "pick live")
        var newer = cache!; newer.updated = now.addingTimeInterval(60)
        precondition(UsageLimits.pick(live, newer)?.source == .cache && UsageLimits.pick(nil, nil) == nil, "pick newer")
        // Stale after 1 h; tired at 90% only when fresh and not reset.
        var hot = live!; hot.weekly?.percent = 92
        precondition(hot.tired(now: now)?.name == "Weekly" && hot.tired(now: now)?.percent == 92, "tired")
        precondition(hot.stale(now: now.addingTimeInterval(3601)) && hot.tired(now: now.addingTimeInterval(3601)) == nil, "stale not tired")
        hot.weekly?.resetsAt = now.addingTimeInterval(-1)
        precondition(hot.tired(now: now) == nil, "reset not tired")
        // Missing or bad files.
        for bad in [nil, d("{bad"), d("{}"), d(#"{"ts":1,"rate_limits":{}}"#), d(#"{"cachedUsageUtilization":null}"#)] {
            precondition(UsageLimits.parseLive(bad) == nil && UsageLimits.parseCache(bad) == nil, "bad input")
        }
        precondition(LimitsText.resetsIn(2 * 3600 + 5 * 60) == "resets in 2 h 05 m" && LimitsText.resetsIn(45 * 60 + 10) == "resets in 46 m"
                     && LimitsText.age(30) == "now" && LimitsText.age(2 * 86400 + 5) == "2 d ago" && LimitsText.age(300) == "5m ago", "text")
    }
}

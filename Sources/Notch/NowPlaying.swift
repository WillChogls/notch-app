import AppKit
import os

/// Tracks Music / Spotify via their distributed notifications (no permission needed)
/// and uses AppleScript for controls, artwork and position (asks for Automation permission once).
@MainActor
final class NowPlaying: ObservableObject {
    enum Source: String {
        case spotify = "Spotify", music = "Music"
        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    @Published private(set) var source: Source?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var tint: NSColor = .white
    /// Shuffle / repeat of the playing app; nil when unknown (the toggle is then hidden).
    @Published private(set) var isShuffle: Bool?
    @Published private(set) var isRepeat: Bool?
    /// macOS refused Notch's Apple Events to the player (Automation permission off): shown instead of the toggles.
    @Published private(set) var automationBlocked = false

    private var position: Double = 0
    private var positionDate = Date()
    private var trackKey = ""
    private let scriptQueue = DispatchQueue(label: "notch.applescript")

    var hasTrack: Bool { source != nil && !title.isEmpty }

    init() {
        let center = DistributedNotificationCenter.default()
        for (name, source) in [("com.spotify.client.PlaybackStateChanged", Source.spotify),
                               ("com.apple.Music.playerInfo", Source.music)] {
            center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.handle(info, from: source) }
            }
        }
        for source in [Source.spotify, .music] where source.isRunning { refresh(source) }
        // A player that quits while "playing" sends no stopped notification: clear it, which stops the tap and bars.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let id, self.source?.bundleID == id else { return }
                self.clear()
            }
        }
    }

    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(positionDate))
    }

    // MARK: Controls

    func playPause() { command("playpause"); isPlaying.toggle(); setPosition(position(at: .now)) }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        guard let source else { return }
        setPosition(seconds)
        run(source, "tell application \"\(source.rawValue)\" to set player position to \(seconds)")
    }

    // MARK: Shuffle / repeat (read on panel open, on player notifications and after each tap; no timers)
    //
    // Measured: Spotify takes 590-750 ms after a set before it reports the new value, so a read
    // in that window returns the OLD value. A tap therefore flips the button at once, sends only
    // the set, and ignores reads until `settle` has passed; one read after `settle` corrects the
    // button only if the app disagrees.

    private static let settle: TimeInterval = 1.2
    private let modeQueue = DispatchQueue(label: "notch.applescript.modes", qos: .userInitiated)
    /// Compiled scripts by source text; touched only on `modeQueue` (NSAppleScript isn't thread safe).
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]
    private var lastModeTap = Date.distantPast

    func refreshModes() {
        guard let source, source.isRunning else { isShuffle = nil; isRepeat = nil; return }
        let read = source == .spotify ? "{shuffling, repeating}" : "{shuffle enabled, (song repeat as string) is not \"off\"}"
        let started = Date()
        runMode("tell application \"\(source.rawValue)\" to return \(read)") { [weak self] result, error in
            self?.automationBlocked = error == -1743 // errAEEventNotPermitted
            guard let self, self.source == source,
                  started.timeIntervalSince(self.lastModeTap) >= Self.settle else { return } // stale: began before the app applied a tap
            let ok = (result?.numberOfItems ?? 0) == 2
            self.isShuffle = ok ? result?.atIndex(1)?.booleanValue : nil
            self.isRepeat = ok ? result?.atIndex(2)?.booleanValue : nil
            self.sentShuffle = self.isShuffle
            self.sentRepeat = self.isRepeat
        }
    }

    func toggleShuffle() {
        guard let on = isShuffle else { return }
        isShuffle = !on
        requestModeWrite()
    }

    func toggleRepeat() {
        guard let on = isRepeat else { return }
        isRepeat = !on
        requestModeWrite()
    }

    /// Spotify drops or reorders sets that arrive a few ms apart (5 fast taps ended in the wrong
    /// state), so the first tap is sent at once and later ones are coalesced: at most one write per
    /// `writeGap`, carrying only what differs from what the app was last told.
    private static let writeGap: TimeInterval = 0.8
    private var sentShuffle: Bool?
    private var sentRepeat: Bool?
    private var lastWrite = Date.distantPast
    private var writeScheduled = false

    private func requestModeWrite() {
        lastModeTap = .now
        guard !writeScheduled else { return }
        writeScheduled = true
        let wait = max(0, lastWrite.addingTimeInterval(Self.writeGap).timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.writeScheduled = false
            self?.writeModes()
        }
    }

    private func writeModes() {
        guard let source, source.isRunning else { return }
        var sets: [String] = []
        if let s = isShuffle, s != sentShuffle {
            sets.append(source == .spotify ? "set shuffling to \(s)" : "set shuffle enabled to \(s)")
            sentShuffle = s
        }
        if let r = isRepeat, r != sentRepeat {
            sets.append(source == .spotify ? "set repeating to \(r)" : "set song repeat to \(r ? "all" : "off")")
            sentRepeat = r
        }
        guard !sets.isEmpty else { return }
        let now = Date()
        lastWrite = now
        lastModeTap = now
        runMode("tell application \"\(source.rawValue)\"\n\(sets.joined(separator: "\n"))\nend tell")
        // One check once the app has applied it; skipped if another tap or write came in meanwhile.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
            guard let self, self.lastModeTap == now else { return }
            self.refreshModes()
        }
    }

    nonisolated private static let log = Logger(subsystem: "dev.local.notch", category: "applescript")

    /// Own serial queue so toggles never wait behind artwork/position scripts; scripts compile once.
    /// A cached script stays bound to the player process it first reached, so once the player relaunches
    /// every run fails: on any error the cached copy is dropped and the script runs once more, freshly compiled.
    private func runMode(_ source: String, completion: (@MainActor (NSAppleEventDescriptor?, Int?) -> Void)? = nil) {
        modeQueue.async {
            var error: NSDictionary?
            var result: NSAppleEventDescriptor?
            for attempt in 0..<2 {
                error = nil
                let script: NSAppleScript? = Self.compiled[source] ?? {
                    guard let s = NSAppleScript(source: source), s.compileAndReturnError(&error) else { return nil }
                    Self.compiled[source] = s
                    return s
                }()
                result = script?.executeAndReturnError(&error)
                guard result == nil, let error else { break }
                Self.compiled[source] = nil
                Self.log.error("mode script failed (attempt \(attempt + 1, privacy: .public)): \(error[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public) \(error[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)")
            }
            let code = result == nil ? error?[NSAppleScript.errorNumber] as? Int : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { completion?(result, code) } }
        }
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    private func command(_ cmd: String) {
        guard let source else { return }
        run(source, "tell application \"\(source.rawValue)\" to \(cmd)")
    }

    // MARK: State

    private func handle(_ info: [AnyHashable: Any], from source: Source) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        let durationMs = (info["Total Time"] as? Double) ?? (info["Duration"] as? Double) ?? 0
        apply(source: source, state: state,
              title: info["Name"] as? String ?? "",
              artist: info["Artist"] as? String ?? "",
              album: info["Album"] as? String ?? "",
              duration: durationMs / 1000,
              position: info["Playback Position"] as? Double)
    }

    private func apply(source: Source, state: String, title: String, artist: String,
                       album: String, duration: Double, position: Double?) {
        if state == "stopped" {
            if self.source == source { clear() }
            return
        }
        // Don't let a paused player steal focus from one that is actively playing.
        if let current = self.source, current != source, isPlaying, state != "playing" { return }

        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = state == "playing"
        self.duration = duration
        if let position { setPosition(position) } else { fetchPosition() }
        refreshModes()

        let key = "\(source.rawValue)|\(title)|\(artist)|\(album)"
        if key != trackKey {
            trackKey = key
            artwork = nil
            tint = .white
            fetchArtwork()
        }
    }

    private func clear() {
        source = nil; title = ""; artist = ""; album = ""
        isPlaying = false; duration = 0; artwork = nil; trackKey = ""
        isShuffle = nil; isRepeat = nil; sentShuffle = nil; sentRepeat = nil
    }

    private func setPosition(_ seconds: Double) {
        position = seconds
        positionDate = .now
    }

    /// Initial snapshot for players that were already running when we launched.
    private func refresh(_ source: Source) {
        let durationExpr = source == .spotify ? "(duration of current track) / 1000" : "duration of current track"
        let script = """
        tell application "\(source.rawValue)"
            if player state is stopped then return {"stopped"}
            return {player state as string, name of current track, artist of current track, \
        album of current track, \(durationExpr), player position}
        end tell
        """
        run(source, script) { [weak self] result in
            guard let self, let result, result.numberOfItems >= 1 else { return }
            let state = result.atIndex(1)?.stringValue ?? "stopped"
            guard result.numberOfItems >= 6 else { return self.apply(source: source, state: state, title: "", artist: "", album: "", duration: 0, position: 0) }
            self.apply(source: source, state: state,
                       title: result.atIndex(2)?.stringValue ?? "",
                       artist: result.atIndex(3)?.stringValue ?? "",
                       album: result.atIndex(4)?.stringValue ?? "",
                       duration: result.atIndex(5)?.doubleValue ?? 0,
                       position: result.atIndex(6)?.doubleValue ?? 0)
        }
    }

    private func fetchPosition() {
        guard let source else { return }
        run(source, "tell application \"\(source.rawValue)\" to get player position") { [weak self] result in
            if let value = result?.doubleValue { self?.setPosition(value) }
        }
    }

    private func fetchArtwork() {
        guard let source else { return }
        let key = trackKey
        switch source {
        case .spotify:
            run(.spotify, "tell application \"Spotify\" to get artwork url of current track") { [weak self] result in
                guard let s = result?.stringValue, let url = URL(string: s) else { return }
                Task {
                    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                    self?.setArtwork(NSImage(data: data), for: key)
                }
            }
        case .music:
            run(.music, "tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] result in
                guard let data = result?.data else { return }
                self?.setArtwork(NSImage(data: data), for: key)
            }
        }
    }

    private func setArtwork(_ image: NSImage?, for key: String) {
        guard key == trackKey, let image else { return }
        artwork = image
        tint = image.averageColor ?? .white
    }

    /// Every script goes through here: never talks to (and so never relaunches) a player that has quit.
    private func run(_ app: Source, _ source: String, completion: (@MainActor (NSAppleEventDescriptor?) -> Void)? = nil) {
        guard app.isRunning else { return }
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion?(result) } }
        }
    }
}

extension NSImage {
    /// Average color, brightened so it reads well on black.
    var averageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        return NSColor(hue: color.hueComponent, saturation: min(color.saturationComponent * 1.2, 1),
                       brightness: max(color.brightnessComponent, 0.75), alpha: 1)
    }
}

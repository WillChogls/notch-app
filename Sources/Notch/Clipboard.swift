import AppKit
import CryptoKit
import ImageIO

/// One remembered clipboard copy (OFF-24, Resources/design/clipboard-plan.md). Memory only.
struct ClipEntry: Identifiable {
    enum Kind: Equatable, Sendable { case text, rich, image, file, url }
    let id = UUID()
    let kind: Kind
    /// Text: first 4 lines. Image: "Image". File: the name, or "3 files". URL: the host.
    let preview: String
    /// URL: the path ("/docs/clipboard"), shown under the host.
    var detail = ""
    var thumbnail: NSImage?
    /// File copies: the file URLs, for the icon and the drag.
    var files: [URL] = []
    /// The pasteboard items as copied (allowed types only), written back on click.
    let items: [[NSPasteboard.PasteboardType: Data]]
    let hash: Data
    var date = Date()
    var source: String?
}

/// Polls the pasteboard's change count (0.5 s) and keeps the last 5 copies, newest first.
/// Reads the type list first; concealed or transient copies, and copies made while a password
/// manager is in front, are never read. Nothing is written to disk, logged or sent anywhere.
@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var entries: [ClipEntry] = []
    /// macOS denies Notch the clipboard (Privacy & Security): the view shows one line instead.
    @Published private(set) var blocked = false

    nonisolated static let defaultsKey = "clipboardHistory"
    nonisolated static let maxEntries = 5
    nonisolated static let maxText = 200 * 1024
    nonisolated static let maxImage = 10 * 1024 * 1024

    /// Test seam: NOTCH_PASTEBOARD=<name> watches a private named pasteboard instead of the real one.
    let pasteboard: NSPasteboard = ProcessInfo.processInfo.environment["NOTCH_PASTEBOARD"]
        .map { NSPasteboard(name: .init($0)) } ?? .general

    /// Test seam: NOTCH_FRONTMOST=<bundle id> stands in for the frontmost app (password-manager skip).
    nonisolated static let frontmostOverride = ProcessInfo.processInfo.environment["NOTCH_FRONTMOST"]

    private var task: Task<Void, Never>?
    private var lastCount = 0
    /// The change count right after Notch's own copy-back, so the poller skips it.
    private var ownWrite: Int?
    private var asleep = false
    private var observers: [NSObjectProtocol] = []
    /// KVO on the one key, not UserDefaults.didChangeNotification (that fires for every key the app writes).
    private var toggle: NSKeyValueObservation?

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.screensDidSleepNotification, true),
                                 (NSWorkspace.didWakeNotification, false), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.asleep = sleeping; self?.update() }
            })
        }
        UserDefaults.standard.register(defaults: [Self.defaultsKey: true])
        toggle = UserDefaults.standard.observe(\.clipboardHistory) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.update() } }
        }
        update()
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.defaultsKey) }

    /// Starts or stops the poll for the toggle and sleep state. Off clears the entries at once.
    private func update() {
        if !enabled, !entries.isEmpty { entries = [] }
        let run = enabled && !asleep
        guard run != (task != nil) else { return }
        task?.cancel()
        task = nil
        guard run else { return }
        lastCount = pasteboard.changeCount   // what was on the clipboard before is not history
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(250))
            }
        }
    }

    private func poll() async {
        let count = pasteboard.changeCount
        guard count != lastCount else { return }
        lastCount = count
        if count == ownWrite { return }
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            blocked = true
            return
        }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let front = Self.frontmostOverride ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !Self.skip(types: types, frontmost: front) else { return }
        let items = Self.read(pasteboard)
        // Denied = a wanted type is listed but no data comes back (nil). Empty data ("" copied) is real.
        blocked = Self.isBlocked(types: types, items: items)
        guard !blocked, let entry = await Task.detached(priority: .utility, operation: { Self.entry(items) }).value,
              enabled, pasteboard.changeCount == count else { return }
        var e = entry
        e.source = front
        entries = Self.add(e, to: entries)
    }

    /// Writes the entry back and ignores the change it causes. The card calls `promote` after its "Copied" beat.
    func copyBack(_ entry: ClipEntry) {
        pasteboard.clearContents()
        pasteboard.writeObjects(entry.items.map { fields in
            let item = NSPasteboardItem()
            for (type, data) in fields { item.setData(data, forType: type) }
            return item
        })
        ownWrite = pasteboard.changeCount
    }

    func promote(_ entry: ClipEntry) {
        guard entries.contains(where: { $0.id == entry.id }) else { return }
        var e = entry
        e.date = .now
        entries = Self.add(e, to: entries)
    }

    func remove(_ entry: ClipEntry) { entries.removeAll { $0.id == entry.id } }
    func clear() { entries = [] }

    // MARK: Pure parts (self-checked)

    nonisolated static let secretTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType",
    ]
    nonisolated static let passwordApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal",
        "com.dashlane.Dashlane", "com.lastpass.LastPass", "org.keepassxc.keepassxc", "in.sinew.Enpass-Desktop",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]
    nonisolated static let textType = NSPasteboard.PasteboardType.string.rawValue   // public.utf8-plain-text
    nonisolated static let allowed: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .png, .tiff, .rtf, .html, .string]

    /// Never read the content: secret or transient copies, or a password manager in front.
    nonisolated static func skip(types: [String], frontmost: String?) -> Bool {
        types.contains(where: secretTypes.contains) || frontmost.map(passwordApps.contains) == true
    }

    nonisolated static func isBlocked(types: [String], items: [[NSPasteboard.PasteboardType: Data]]) -> Bool {
        wanted(types) && items.allSatisfy(\.isEmpty)
    }

    nonisolated static func wanted(_ types: [String]) -> Bool { types.contains { t in allowed.contains { $0.rawValue == t } } }

    /// Allowed types only. Several items only for file copies; otherwise the first item.
    static func read(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        let all = pb.pasteboardItems ?? []
        let isFiles = all.first?.types.contains(.fileURL) == true
        return (isFiles ? all : Array(all.prefix(1))).map { item in
            var out: [NSPasteboard.PasteboardType: Data] = [:]
            for t in allowed where item.types.contains(t) {
                if let d = item.data(forType: t) { out[t] = d }
            }
            return out
        }
    }

    /// Classifies a copy; nil when it holds nothing supported or is over a size cap.
    nonisolated static func entry(_ items: [[NSPasteboard.PasteboardType: Data]]) -> ClipEntry? {
        guard let first = items.first, !first.isEmpty else { return nil }
        let text = first[.string].flatMap { String(data: $0, encoding: .utf8) }
        if first[.fileURL] != nil {
            let urls = items.compactMap { $0[.fileURL].flatMap { URL(dataRepresentation: $0, relativeTo: nil) } }.filter(\.isFileURL)
            guard !urls.isEmpty else { return nil }
            let kept = items.map { $0.filter { $0.key == .fileURL } }
            return ClipEntry(kind: .file, preview: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files",
                             files: urls, items: kept, hash: sha(urls.map(\.path).joined(separator: "\n")))
        }
        if let img = first[.png] ?? first[.tiff] {
            guard img.count <= maxImage else { return nil }
            let kept = first.filter { $0.key == .png || $0.key == .tiff }
            return ClipEntry(kind: .image, preview: "Image", thumbnail: thumbnail(img), items: [kept], hash: sha(img))
        }
        let link = first[.URL].flatMap { String(data: $0, encoding: .utf8) } ?? text
        if let link, let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
           ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host, !link.contains("\n") {
            guard link.utf8.count <= maxText else { return nil }
            let shortHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return ClipEntry(kind: .url, preview: shortHost, detail: url.path, items: [first.filter { $0.key == .URL || $0.key == .string }], hash: sha(url.absoluteString))
        }
        guard let text, !text.isEmpty, text.utf8.count <= maxText else { return nil }
        let rich = first[.rtf] != nil || first[.html] != nil
        let kept = first.filter { [.rtf, .html, .string].contains($0.key) }
        return ClipEntry(kind: rich ? .rich : .text, preview: lines(text), items: [kept], hash: sha(text))
    }

    /// Same content moves the existing entry to the front; otherwise newest first, at most 5.
    nonisolated static func add(_ e: ClipEntry, to entries: [ClipEntry]) -> [ClipEntry] {
        var list = entries
        if let i = list.firstIndex(where: { $0.hash == e.hash }) {
            var old = list.remove(at: i)
            old.date = e.date
            list.insert(old, at: 0)
            return list
        }
        list.insert(e, at: 0)
        return Array(list.prefix(maxEntries))
    }

    nonisolated static func lines(_ s: String) -> String {
        s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).prefix(4).joined(separator: "\n")
    }

    nonisolated static func sha(_ s: String) -> Data { sha(Data(s.utf8)) }
    nonisolated static func sha(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }

    /// Made once, off the main thread; 200 px on the long side.
    nonisolated static func thumbnail(_ data: Data) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: 200,
                                                                     kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

extension UserDefaults {
    /// KVO handle for ClipboardHistory.defaultsKey (the property name must equal the key).
    @objc dynamic var clipboardHistory: Bool { bool(forKey: ClipboardHistory.defaultsKey) }
}

/// Runs with the office self-check (`NOTCH_SELFCHECK=1`). Uses a private pasteboard only, never the real one.
enum ClipboardSelfCheck {
    @MainActor static func run() {
        typealias C = ClipboardHistory
        func t(_ s: String) -> [[NSPasteboard.PasteboardType: Data]] { [[.string: Data(s.utf8)]] }
        // Skip rule.
        precondition(C.skip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], frontmost: nil), "concealed")
        precondition(C.skip(types: ["org.nspasteboard.TransientType"], frontmost: nil) && C.skip(types: ["org.nspasteboard.AutoGeneratedType"], frontmost: nil), "transient")
        precondition(C.skip(types: ["public.utf8-plain-text"], frontmost: "com.1password.1password"), "password app")
        precondition(!C.skip(types: ["public.utf8-plain-text"], frontmost: "com.apple.Safari"), "normal copy")
        // Kinds and caps.
        precondition(C.entry(t("a\nb\nc\nd\ne"))?.preview == "a\nb\nc\nd" && C.entry(t("hi"))?.kind == .text, "text")
        precondition(C.entry(t("https://www.example.com/x"))?.kind == .url && C.entry(t("https://www.example.com/x"))?.preview == "example.com"
                     && C.entry(t("https://www.example.com/x"))?.detail == "/x", "url")
        precondition(C.entry([[.string: Data("hi".utf8), .rtf: Data("{\\rtf1 hi}".utf8)]])?.kind == .rich, "rich")
        precondition(C.entry(t(String(repeating: "x", count: C.maxText + 1))) == nil, "text cap")
        precondition(C.entry([[.png: Data(count: C.maxImage + 1)]]) == nil, "image cap")
        let files = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.png")].map { [NSPasteboard.PasteboardType.fileURL: $0.dataRepresentation] }
        precondition(C.entry(files)?.kind == .file && C.entry(files)?.preview == "2 files", "files")
        precondition(C.entry([[:]]) == nil && C.entry([]) == nil && C.entry(t("")) == nil, "empty")
        // Blocked only when listed types give no data; an empty string is a real copy.
        precondition(C.isBlocked(types: [C.textType], items: [[:]]) && !C.isBlocked(types: [C.textType], items: t("")), "blocked")
        // Dedupe and the cap at 5.
        var list: [ClipEntry] = []
        for s in ["1", "2", "3", "4", "5", "6", "7"] { list = C.add(C.entry(t(s))!, to: list) }
        precondition(list.map(\.preview) == ["7", "6", "5", "4", "3"], "cap \(list.map(\.preview))")
        list = C.add(C.entry(t("4"))!, to: list)
        precondition(list.map(\.preview) == ["4", "7", "6", "5", "3"], "dedupe \(list.map(\.preview))")
        // Private pasteboard round trip: read what was written, and copy-back writes the same items.
        let pb = NSPasteboard(name: .init("dev.local.notch.selfcheck.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("round trip", forType: .string)
        let read = C.read(pb)
        precondition(C.entry(read)?.preview == "round trip", "read private pasteboard")
        print("clipboard self-check passed")
    }
}

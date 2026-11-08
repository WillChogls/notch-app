import AppKit

/// Files dropped onto the notch. Stored as paths so they survive relaunches.
@MainActor
final class Shelf: ObservableObject {
    private static let key = "shelfPaths"

    @Published private(set) var items: [URL] = [] {
        didSet { UserDefaults.standard.set(items.map(\.path), forKey: Self.key) }
    }

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        items = paths.map(URL.init(fileURLWithPath:)).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, !self.items.contains(url) else { return }
                        self.items.append(url)
                    }
                }
            }
        }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url } }
    func clear() { items.removeAll() }

    func airDrop() {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: items)
    }
}

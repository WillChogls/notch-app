import AppKit
import SwiftUI

/// "Open app" buttons on the office and now-playing cards (Resources/design/shortcut-buttons-spec.md).
enum Shortcut {
    static let munderDifflin = "in.munderdiffl.app"

    struct App: Equatable {
        let url: URL
        let icon: NSImage
    }

    /// The installed app's location, or nil (the button is then hidden).
    static func url(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The installed app and its real icon, resolved once per panel open; nil hides the button.
    static func app(_ bundleID: String) -> App? {
        url(bundleID).map { App(url: $0, icon: NSWorkspace.shared.icon(forFile: $0.path)) }
    }

    /// The "Music app" setting: "spotify" or "music". Default: Spotify if installed, else Apple Music.
    static var defaultMusicApp: String { url(NowPlaying.Source.spotify.bundleID) != nil ? "spotify" : "music" }

    static func musicSource(_ setting: String) -> NowPlaying.Source { setting == "music" ? .music : .spotify }
}

extension NowPlaying.Source {
    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
}

struct ShortcutButton: View {
    let app: Shortcut.App
    let label: String
    var frame: CGFloat = 16
    var hitPadding: CGFloat = 4

    var body: some View {
        Button {
            NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
        } label: {
            EmptyView()
        }
        .buttonStyle(Style(icon: app.icon, frame: frame, hitPadding: hitPadding))
        .help(label)
        .accessibilityLabel(label)
    }

    private struct Style: ButtonStyle {
        let icon: NSImage, frame: CGFloat, hitPadding: CGFloat
        @State private var hover = false

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: frame, height: frame)
                .opacity(pressed ? 0.7 : hover ? 1 : 0.85)
                .scaleEffect(pressed ? 0.92 : hover ? 1.12 : 1)
                .animation(.spring(duration: 0.2), value: hover)
                .animation(.spring(duration: 0.15), value: pressed)
                .padding(hitPadding).contentShape(Rectangle()).padding(-hitPadding)
                .onHover { hover = $0 }
        }
    }
}

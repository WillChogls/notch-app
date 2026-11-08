import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a button work even though the panel never activates the app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchWindowController {
    /// Large transparent canvas at the top-center of the screen; the notch draws inside it.
    static let canvasSize = CGSize(width: 720, height: 280)

    let model = NotchModel()
    private let panel: NotchPanel

    init() {
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        let root = NotchRootView()
            .environmentObject(model)
            .environmentObject(model.player)
            .environmentObject(model.battery)
            .environmentObject(model.shelf)
        let host = FirstMouseHostingView(rootView: root)
        // Never let SwiftUI resize the window from its content: that shifted the canvas
        // sideways mid-animation, so the panel slid in from the right instead of the centre.
        host.sizingOptions = []
        panel.contentView = host
        reposition()
    }

    func show() { panel.orderFrontRegardless() }

    func reposition() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else { return }
        model.configure(for: screen)
        let size = Self.canvasSize
        panel.setFrame(
            NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                   width: size.width, height: size.height),
            display: true
        )
    }
}

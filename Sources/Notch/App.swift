import AppKit
import ServiceManagement
import SwiftUI

@main
enum NotchApp {
    static func main() {
        if ProcessInfo.processInfo.environment["NOTCH_SELFCHECK"] == "1" { EqualizerSelfCheck.run(); OfficeSelfCheck.run(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always dark, whatever macOS is set to (the human's call); drop the old Appearance setting.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        UserDefaults.standard.removeObject(forKey: "appearance")
        // Open at login by default, once; after that the Settings toggle owns it.
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
        }
        let controller = NotchWindowController()
        controller.show()
        self.controller = controller

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller?.reposition() }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// Launching the app again while it runs (Spotlight, Finder) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Notch Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

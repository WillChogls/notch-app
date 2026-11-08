import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchModel: ObservableObject {
    enum State { case closed, open }
    enum Tab: String, CaseIterable {
        case home, shelf
        var symbol: String { self == .home ? "house.fill" : "tray.full.fill" }
    }

    @Published var state: State = .closed
    @Published var tab: Tab = .home
    /// Size of the physical notch (or a fallback pill on Macs without one).
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var hasNotch = true
    @Published private(set) var chargingFlash = false

    let openSize = CGSize(width: 600, height: 190)

    let player = NowPlaying()
    let battery = BatteryMonitor()
    let shelf = Shelf()
    let audio = AudioTap()
    let office = OfficeMonitor()
    let weather = WeatherModel.shared

    private var hovering = false
    private var dropTargeted = false
    private var pending: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var playingSub: AnyCancellable?

    init() {
        battery.onPlugIn = { [weak self] in self?.flashCharging() }
        // Capture the playing app's audio for the equalizer only while it plays; re-tap if the source changes.
        playingSub = player.$isPlaying.combineLatest(player.$source)
            .map { $0 ? $1?.bundleID : nil }
            .removeDuplicates()
            .sink { [audio] in audio.follow($0) }
    }

    func configure(for screen: NSScreen) {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                               height: screen.safeAreaInsets.top)
        } else {
            hasNotch = false
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 190, height: max(menuBar, 24))
        }
    }

    func setHovering(_ value: Bool) { guard value != hovering else { return }; hovering = value; reevaluate() }

    func setDropTargeted(_ value: Bool) {
        dropTargeted = value
        if value { tab = .shelf }
        reevaluate()
    }

    private func reevaluate() {
        pending?.cancel()
        let wantsOpen = hovering || dropTargeted
        let delay: Duration = wantsOpen ? .zero : .milliseconds(80)
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if wantsOpen, self.state == .closed {
                self.state = .open
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            } else if !wantsOpen {
                self.state = .closed
            }
        }
    }

    private func flashCharging() {
        flashTask?.cancel()
        chargingFlash = true
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.chargingFlash = false
        }
    }
}

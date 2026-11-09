import SwiftUI

enum LiveActivity: Equatable { case none, music, charging }

struct NotchRootView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var player: NowPlaying
    @State private var dropTargeted = false
    @AppStorage("openScale") private var openScale = 1.0

    private var isOpen: Bool { model.state == .open }
    private var topRadius: CGFloat { isOpen ? 19 : 6 }
    private var bottomRadius: CGFloat { isOpen ? 24 : 14 }

    private var activity: LiveActivity {
        if model.chargingFlash { return .charging }
        if player.hasTrack && player.isPlaying { return .music }
        return .none
    }

    private var size: CGSize {
        if isOpen { return model.openSize }
        let h = model.notchSize.height
        let wings: CGFloat = activity == .none ? 0 : (activity == .charging ? 70 : h + 8) * 2
        return CGSize(width: model.notchSize.width + wings + topRadius * 2, height: h)
    }

    var body: some View {
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius, width: size.width, height: size.height)
        // Fixed, centred canvas: only the shape's own size animates, never the layout frame,
        // so the panel can't slide in from a side.
        let canvas = model.openSize
        ZStack(alignment: .top) {
            NotchBackground(shape: shape, isOpen: isOpen,
                            notchFraction: model.notchSize.height / model.openSize.height)
                .shadow(color: .black.opacity(isOpen ? 0.6 : 0), radius: 10, y: 4)
            Group {
                if isOpen {
                    // Laid out at its final size so nothing reflows while the shell grows;
                    // the expanding shape reveals it from the centre outward.
                    OpenContent()
                        .frame(width: model.openSize.width - 38, height: model.openSize.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .top)))
                } else {
                    ClosedContent(activity: activity)
                        .frame(width: size.width - topRadius * 2, height: size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: canvas.width, height: canvas.height)
        .contentShape(shape)
        // Closed, only the hardware notch itself opens the panel (not the live-activity
        // wings or flared corners). Open, the whole panel keeps it open.
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                let w = model.notchSize.width
                model.setHovering(isOpen || CGRect(x: (canvas.width - w) / 2, y: 0, width: w, height: size.height).contains(p))
            case .ended:
                model.setHovering(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            model.shelf.add(providers)
            return true
        }
        .onChange(of: dropTargeted) { _, value in model.setDropTargeted(value) }
        .scaleEffect(isOpen ? openScale : 1, anchor: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: isOpen)
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: activity)
    }
}

// MARK: - Closed (live activities around the hardware notch)

struct ClosedContent: View {
    let activity: LiveActivity
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var player: NowPlaying
    @EnvironmentObject var battery: BatteryMonitor

    var body: some View {
        let h = model.notchSize.height
        HStack(spacing: 0) {
            switch activity {
            case .music:
                Artwork(image: player.artwork, side: h - 12, corner: 5)
                    .padding(.leading, 8)
                Spacer(minLength: 0)
                Bars(levels: model.audio.levels, playing: player.isPlaying, tint: player.tint)
                    .padding(.trailing, 10)
            case .charging:
                Text("Charging").font(.system(size: 12, weight: .semibold))
                    .padding(.leading, 10)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("\(battery.level)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Image(systemName: "battery.100percent.bolt").foregroundStyle(.green)
                }
                .padding(.trailing, 10)
            case .none:
                Color.clear
            }
        }
        .foregroundStyle(.white)
        .frame(height: h)
    }
}

// MARK: - Open

struct OpenContent: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var battery: BatteryMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(NotchModel.Tab.allCases, id: \.self) { tab in
                    Button { model.tab = tab } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 22)
                            .modifier(SelectedGlass(selected: model.tab == tab))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.5))
                }
                Spacer()
                if battery.hasBattery {
                    HStack(spacing: 4) {
                        Text("\(battery.level)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Image(systemName: battery.symbol)
                            .foregroundStyle(battery.isCharging ? .green : (battery.level <= 20 ? .red : .white))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 12)
            .glassGroup()
            .frame(height: model.notchSize.height)

            Group {
                switch model.tab {
                case .home: HomeView()
                case .shelf: ShelfView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .padding(.top, 6)
        }
        .foregroundStyle(.primary)
    }
}

struct HomeView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var player: NowPlaying

    var body: some View {
        HStack(spacing: 16) {
            if player.hasTrack {
                NowPlayingCard()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.primary.opacity(0.4))
                    Text("Nothing playing").font(.system(size: 12)).foregroundStyle(.primary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            WidgetCard()
        }
    }
}

struct NowPlayingCard: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var player: NowPlaying
    @AppStorage("musicApp") private var musicApp = Shortcut.defaultMusicApp
    /// The chosen music app's location; nil hides the button. Re-checked each time the panel opens.
    @State private var app: Shortcut.App?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Artwork(image: player.artwork, side: 96, corner: 14)
                .shadow(color: Color(nsColor: player.tint).opacity(0.35), radius: 12)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(player.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Bars(levels: model.audio.levels, playing: player.isPlaying, tint: player.tint,
                         barWidth: 4, gap: 3, minHeight: 4, maxHeight: 20, fps: 60)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        // Paused bars read as a "..." menu: hide them in the open panel.
                        .opacity(player.isPlaying ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: player.isPlaying)
                }
                Text(player.artist).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.6)).lineLimit(1)
                Spacer(minLength: 4)
                ProgressRow()
                HStack(spacing: 16) {
                    control("backward.fill", size: 15, action: player.previous)
                    control(player.isPlaying ? "pause.fill" : "play.fill", size: 22, action: player.playPause)
                    control("forward.fill", size: 15, action: player.next)
                }
                .frame(maxWidth: .infinity)
                .glassGroup(spacing: 16)
                // Shuffle, Repeat left of Previous (shuffle-repeat-spec v2). An unknown state keeps its slot.
                .overlay(alignment: .leading) {
                    if player.automationBlocked {
                        // macOS blocks Notch from reading the player: say so instead of hiding the toggles.
                        Button(action: player.openAutomationSettings) {
                            Image(systemName: "lock.fill").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.5))
                                .frame(width: 20, height: 20).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Shuffle and Repeat need permission: allow Notch under Automation in System Settings")
                        .accessibilityLabel("Shuffle and Repeat need Automation permission. Open System Settings")
                    } else if player.isShuffle != nil || player.isRepeat != nil {
                        HStack(spacing: 8) {
                            ModeToggle(symbol: "shuffle", name: "Shuffle", isOn: player.isShuffle ?? false,
                                       action: player.toggleShuffle)
                                .hidden(player.isShuffle == nil)
                            ModeToggle(symbol: "repeat", name: "Repeat", isOn: player.isRepeat ?? false,
                                       action: player.toggleRepeat)
                                .hidden(player.isRepeat == nil)
                        }
                    }
                }
                .overlay(alignment: .trailing) {
                    if let app {
                        ShortcutButton(app: app, label: "Open \(Shortcut.musicSource(musicApp).displayName)",
                                       frame: 20, hitPadding: 2)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top) // artwork top flush with the Office card
        .onAppear { checkApp(); player.refreshModes() }
        .onChange(of: musicApp) { checkApp() }
    }

    private func checkApp() { app = Shortcut.app(Shortcut.musicSource(musicApp).bundleID) }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 34, height: 34)
                .contentShape(Circle())
                .glass(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

/// Shuffle / repeat toggle (shuffle-repeat-spec.md v2): grey when off, system accent plus a dot when on.
struct ModeToggle: View {
    let symbol: String, name: String, isOn: Bool, action: () -> Void

    /// System accent, or system blue when the accent is Graphite (grey "on" would read as "off").
    private static var tint: Color {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        return (accent?.saturationComponent ?? 0) < 0.15 ? Color(nsColor: .systemBlue) : .accentColor
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(Style(symbol: symbol, isOn: isOn, tint: Self.tint, reduceMotion: reduceMotion))
            .help("\(name) \(isOn ? "on" : "off")")
            .accessibilityLabel(name)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
    }

    private struct Style: ButtonStyle {
        let symbol: String, isOn: Bool, tint: Color, reduceMotion: Bool
        @State private var hover = false

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.primary.opacity(hover ? 0.8 : 0.5)))
                .frame(width: 16, height: 16)
                .background(Circle().fill(.primary.opacity(hover ? 0.10 : 0)).frame(width: 20, height: 20))
                .overlay(alignment: .bottom) {
                    Circle().fill(tint).frame(width: 3, height: 3).offset(y: 4.5)
                        .scaleEffect(isOn || reduceMotion ? 1 : 0.01)
                        .opacity(isOn ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.2), value: isOn)
                }
                .opacity(pressed ? 0.7 : 1)
                .scaleEffect(pressed && !reduceMotion ? 0.92 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
                .animation(.easeOut(duration: 0.15), value: isOn)
                .animation(.spring(duration: 0.15), value: pressed)
                .padding(4).contentShape(Rectangle()).padding(-4)
                .onHover { hover = $0 }
        }
    }
}

struct ProgressRow: View {
    @EnvironmentObject var player: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let pos = player.position(at: context.date)
            let fraction = player.duration > 0 ? pos / player.duration : 0
            HStack(spacing: 8) {
                Text(format(pos))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.2))
                        Capsule().fill(Color(nsColor: player.tint))
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(height: 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        let f = min(max(value.location.x / geo.size.width, 0), 1)
                        player.seek(to: f * player.duration)
                    })
                }
                .frame(height: 14)
                Text(format(player.duration))
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.primary.opacity(0.6))
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}


struct ShelfView: View {
    @EnvironmentObject var shelf: Shelf

    var body: some View {
        if shelf.items.isEmpty {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 22))
                        Text("Drop files here").font(.system(size: 12))
                    }
                    .foregroundStyle(.primary.opacity(0.5))
                }
        } else {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(shelf.items, id: \.self) { ShelfItem(url: $0) }
                    }
                }
                VStack(spacing: 8) {
                    shelfButton("airplayaudio", label: "AirDrop", action: shelf.airDrop)
                    shelfButton("trash", label: "Clear", action: shelf.clear)
                }
                .glassGroup()
            }
        }
    }

    private func shelfButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 84, height: 28)
                .glass(Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct ShelfItem: View {
    let url: URL
    @EnvironmentObject var shelf: Shelf
    @State private var hovering = false
    @State private var unhover: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .padding(6)
        // Gestures sit under the X, not around it, so a click on X never waits on the double-click.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        // Nothing is inserted or removed on hover (glass and X only fade): changing the view tree resets
        // hover tracking, so the item lost its hover, and its X, with the pointer still on it.
        .background { Color.clear.glass(RoundedRectangle(cornerRadius: 12, style: .continuous)).opacity(hovering ? 1 : 0) }
        .overlay(alignment: .topTrailing) {
            Button { shelf.remove(url) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    .foregroundStyle(.white, .gray)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .accessibilityLabel("Remove \(url.lastPathComponent)")
        }
        // A few points of hover slop around the card (the strip's spacing is folded into this padding).
        .padding(3)
        .contentShape(Rectangle())
        .onHover { inside in
            unhover?.cancel()
            if inside { hovering = true; return }
            // Grace period: a quick move toward the X, or across the edge, keeps the item hovered.
            unhover = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { hovering = false }
            }
        }
        .help(url.path)
    }
}

// MARK: - Small pieces

extension View {
    /// Keeps the view's slot but hides it, so neighbours don't move.
    @ViewBuilder func hidden(_ hide: Bool) -> some View {
        if hide { hidden() } else { self }
    }
}

struct Artwork: View {
    let image: NSImage?
    let side: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.primary.opacity(0.12)
                    Image(systemName: "music.note").font(.system(size: side * 0.4)).foregroundStyle(.primary.opacity(0.5))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Glass behind a selected/hovered element, nothing otherwise.
struct SelectedGlass<S: Shape>: ViewModifier {
    let selected: Bool
    var shape: S

    func body(content: Content) -> some View {
        if selected { content.glass(shape) } else { content }
    }
}

extension SelectedGlass where S == Capsule {
    init(selected: Bool) { self.init(selected: selected, shape: Capsule()) }
}

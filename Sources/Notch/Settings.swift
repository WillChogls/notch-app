import AppKit
import ServiceManagement
import SwiftUI

enum Appearance: String, CaseIterable {
    case system, light, dark

    var label: String { self == .system ? "Auto" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    static func apply(_ raw: String) {
        NSApp.appearance = switch Appearance(rawValue: raw) {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}

/// Settings window, per Oscar's spec (Resources/design/settings-spec.md).
struct SettingsView: View {
    @AppStorage("glassOpacity") private var opacity = 0.7
    @AppStorage("openScale") private var openScale = 1.0
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("musicApp") private var musicApp = Shortcut.defaultMusicApp
    @AppStorage("widget") private var widget = WidgetKind.office.rawValue
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @Environment(\.colorScheme) private var scheme

    static let blue = Color(red: 0.42, green: 0.55, blue: 1.0)
    static let lavender = Color(red: 0.66, green: 0.55, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.60, blue: 0.84)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            section("Panel", top: 24) {
                sliderRow("Opacity", a11y: "Panel opacity", value: $opacity, range: 0.2...1,
                          min: "circle.dotted", max: "circle.fill")
                Divider()
                sliderRow("Size", a11y: "Open panel size", value: $openScale, range: 0.8...1.15,
                          min: "minus.magnifyingglass", max: "plus.magnifyingglass")
            }
            section("General") {
                HStack {
                    Text("Appearance")
                    Spacer()
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) {
                            Label($0.label, systemImage: $0.symbol).labelStyle(.titleAndIcon).tag($0.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .frame(height: 44)
                Divider()
                musicRow
                Divider()
                HStack {
                    Text("Widget")
                    Spacer()
                    Picker("Widget", selection: $widget) {
                        ForEach(WidgetKind.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .frame(height: 44)
                // The one moment Location is asked for: the human picks Weather.
                .onChange(of: widget) { _, value in
                    if value == WidgetKind.weather.rawValue { WeatherModel.shared.requestPermission() }
                }
                Divider()
                loginRow.padding(.vertical, 12)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20)
        .padding(.top, 24) // + 28pt transparent title bar = 52pt from the window top
        .padding(.bottom, 20)
        .frame(width: 440)
        .background(alignment: .top) { headerWash }
        .fixedSize()
        .onChange(of: appearance) { _, value in Appearance.apply(value) }
        .onAppear {
            // Older builds stored unstepped values (e.g. 0.864); snap them to the 5% grid.
            opacity = (opacity * 20).rounded() / 20
            openScale = (openScale * 20).rounded() / 20
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
                .shadow(color: Self.lavender.opacity(0.45), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notch").font(.system(size: 22, weight: .bold))
                Text("Your notch, made useful.").foregroundStyle(.secondary)
            }
            Spacer()
            Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.primary.opacity(0.08)))
        }
    }

    private var headerWash: some View {
        LinearGradient(colors: [Self.blue, Self.lavender, Self.pink], startPoint: .leading, endPoint: .trailing)
            .opacity(scheme == .dark ? 0.22 : 0.18)
            .frame(height: 160)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
    }

    private func section<Content: View>(_ title: String, top: CGFloat = 20, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 14)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(scheme == .dark ? 0.06 : 0.7)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        }
        .padding(.top, top)
    }

    /// Native slider without tick marks; the binding snaps to 5% steps.
    private func sliderRow(_ title: String, a11y: String, value: Binding<Double>, range: ClosedRange<Double>,
                           min: String, max: String) -> some View {
        let snapped = Binding(get: { value.wrappedValue }, set: { value.wrappedValue = ($0 * 20).rounded() / 20 })
        return VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: min)
                Slider(value: snapped, in: range).accessibilityLabel(a11y)
                Image(systemName: max)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var musicRow: some View {
        let chosen = Shortcut.musicSource(musicApp)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Music app")
                Spacer()
                Picker("Music app", selection: $musicApp) {
                    Text("Spotify").tag("spotify")
                    Text("Apple Music").tag("music")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .frame(height: 44)
            if Shortcut.url(chosen.bundleID) == nil {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("\(chosen.displayName) isn't installed.").foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.bottom, 10)
            }
        }
    }

    private var loginRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Open at login")
                Spacer()
                Toggle("Open at login", isOn: Binding(get: { loginStatus == .enabled }, set: setLogin))
                    .toggleStyle(.switch).labelsHidden().tint(.green)
            }
            if loginStatus == .requiresApproval {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("Waiting for your OK in Login Items.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
                .font(.system(size: 11))
            }
            if let loginError {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(loginError).foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }
}

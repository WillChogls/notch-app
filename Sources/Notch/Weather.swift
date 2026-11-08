import AppKit
import CoreLocation
import SwiftUI

/// Weather widget data: Open-Meteo (free, no key) at city-level location (widget-slot-spec.md §5).
/// Location is asked once, when Weather is first picked; it is read once per refresh, never tracked.
/// Only coordinates rounded to 2 decimals leave the Mac. Refreshes only while the widget is shown.
@MainActor
final class WeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherModel()

    struct Reading: Codable, Equatable {
        var city: String?
        var celsius: Double
        var highC: Double
        var lowC: Double
        var code: Int
        var isDay: Bool
        var updated: Date
    }

    enum Phase { case idle, locating, loading }

    @Published private(set) var data: Reading?
    @Published private(set) var phase = Phase.idle
    @Published private(set) var offline = false
    @Published private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var active = false
    private var loop: Task<Void, Never>?
    private static let cacheKey = "weatherCache"

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let raw = UserDefaults.standard.data(forKey: Self.cacheKey) {
            data = try? JSONDecoder().decode(Reading.self, from: raw)
        }
    }

    var locationOff: Bool { status == .denied || status == .restricted }

    /// Called when the human picks Weather in Settings: the one moment we ask.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// The widget is on screen (panel open and Weather chosen): refresh if stale, then every 30 min.
    func setActive(_ on: Bool) {
        active = on
        loop?.cancel()
        guard on else { return }
        if (data?.updated.timeIntervalSinceNow ?? -.infinity) < -15 * 60 || offline { refresh() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            phase = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            phase = .idle
        default:
            phase = .locating
            manager.requestLocation()
        }
    }

    func openLocationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        MainActor.assumeIsolated {
            status = s
            if active, s != .notDetermined { refresh() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        MainActor.assumeIsolated { fetch(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            phase = .idle
            offline = true
        }
    }

    // MARK: Network

    private func fetch(_ loc: CLLocation) {
        phase = .loading
        let lat = (loc.coordinate.latitude * 100).rounded() / 100
        let lon = (loc.coordinate.longitude * 100).rounded() / 100
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=1")!
        Task {
            async let city = cityName(loc)
            do {
                let (raw, _) = try await URLSession.shared.data(from: url)
                let r = try JSONDecoder().decode(Response.self, from: raw)
                let d = Reading(city: await city, celsius: r.current.temperature_2m,
                             highC: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                             lowC: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                             code: r.current.weather_code, isDay: r.current.is_day == 1, updated: .now)
                data = d
                offline = false
                UserDefaults.standard.set(try? JSONEncoder().encode(d), forKey: Self.cacheKey)
            } catch {
                offline = true
            }
            phase = .idle
        }
    }

    /// Reverse-geocodes once per place; reuses the cached name when we haven't moved ~5 km.
    private var lastGeocoded: (CLLocation, String?)?
    private func cityName(_ loc: CLLocation) async -> String? {
        if let (prev, name) = lastGeocoded, prev.distance(from: loc) < 5000 { return name }
        let name = try? await geocoder.reverseGeocodeLocation(loc).first?.locality
        lastGeocoded = (loc, name ?? nil)
        return name ?? nil
    }

    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let current: Current
        let daily: Daily
    }

    /// WMO weather code → SF Symbol and words.
    static func condition(_ code: Int, day: Bool) -> (symbol: String, text: String) {
        switch code {
        case 0: (day ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1, 2: (day ? "cloud.sun.fill" : "cloud.moon.fill", code == 1 ? "Mostly clear" : "Partly cloudy")
        case 3: ("cloud.fill", "Cloudy")
        case 45, 48: ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57: ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67, 80, 81, 82: ("cloud.rain.fill", code >= 80 ? "Showers" : "Rain")
        case 71, 73, 75, 77, 85, 86: ("cloud.snow.fill", "Snow")
        case 95, 96, 99: ("cloud.bolt.rain.fill", "Thunderstorm")
        default: ("cloud.fill", "—")
        }
    }

    /// °C or °F from the system locale.
    static func temp(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

struct WeatherWidget: View {
    @ObservedObject var weather: WeatherModel
    /// Spinners show only after 0.5 s so quick loads don't flicker.
    @State private var showBusy = false

    var body: some View {
        content
            .onAppear { weather.setActive(true) }
            .onDisappear { weather.setActive(false) }
            .task(id: weather.phase) {
                showBusy = false
                guard weather.phase != .idle else { return }
                try? await Task.sleep(for: .milliseconds(500))
                showBusy = !Task.isCancelled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Weather widget")
    }

    @ViewBuilder private var content: some View {
        if weather.locationOff {
            WidgetPlaceholder(symbol: "location.slash", text: "Location off", detail: "Weather needs your location",
                              action: ("Open System Settings", weather.openLocationSettings))
        } else if let d = weather.data {
            loaded(d)
        } else if weather.phase != .idle {
            if showBusy {
                WidgetPlaceholder(symbol: nil, text: weather.phase == .locating ? "Locating…" : "Loading weather", loading: true)
            } else {
                Color.clear
            }
        } else {
            WidgetPlaceholder(symbol: "wifi.slash", text: "Weather unavailable", detail: "Check your connection")
        }
    }

    private func loaded(_ d: WeatherModel.Reading) -> some View {
        let c = WeatherModel.condition(d.code, day: d.isDay)
        let city = d.city ?? "Current location"
        return VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: city)
            HStack(spacing: 8) {
                Text(WeatherModel.temp(d.celsius)).font(.system(size: 32, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: c.symbol).font(.system(size: 24))
                    .symbolRenderingMode(.multicolor)
            }
            Text(c.text).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.6)).lineLimit(1)
            Text("H \(WeatherModel.temp(d.highC))  L \(WeatherModel.temp(d.lowC))")
                .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.primary.opacity(0.6))
                .padding(.top, 4)
            Spacer(minLength: 0)
            footer(d.updated)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(city), \(WeatherModel.temp(d.celsius)), \(c.text), high \(WeatherModel.temp(d.highC)), "
                            + "low \(WeatherModel.temp(d.lowC)), updated \(d.updated.formatted(.relative(presentation: .named)))")
    }

    private func footer(_ updated: Date) -> some View {
        TimelineView(.everyMinute) { context in
            let ago = context.date.timeIntervalSince(updated) < 60 ? "just now"
                : updated.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
            Text(weather.offline ? "Offline · updated \(ago)" : "Updated \(ago)")
                .font(.system(size: 10))
                .foregroundStyle(weather.offline ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary.opacity(0.4)))
                .lineLimit(1)
        }
    }
}

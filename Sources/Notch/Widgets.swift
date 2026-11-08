import SwiftUI

/// The open panel's right-hand slot (Resources/design/widget-slot-spec.md). Only the chosen widget is
/// built, so the others have no timers or polling.
enum WidgetKind: String, CaseIterable {
    case office, calendar, clock, weather
    var label: String { rawValue.capitalized }
}

struct WidgetCard: View {
    @EnvironmentObject var model: NotchModel
    @AppStorage("widget") private var widget = WidgetKind.office.rawValue

    var body: some View {
        Group {
            switch WidgetKind(rawValue: widget) ?? .office {
            case .office: OfficeCard(office: model.office)
            case .calendar: CalendarWidget()
            case .clock: ClockWidget()
            case .weather: WeatherWidget(weather: model.weather)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: widget)
        .padding(10)
        .frame(width: 170)
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Office's header style, for widgets that have a header.
struct WidgetHeader: View {
    let title: String
    var summary: String?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer()
            if let summary { Text(summary).font(.system(size: 11)).monospacedDigit() }
        }
        .foregroundStyle(.primary.opacity(0.6))
        .frame(minHeight: 16)
        .padding(.bottom, 6)
    }
}

/// Empty / loading / error look shared by widgets: calm, never red.
struct WidgetPlaceholder: View {
    let symbol: String?
    let text: String
    var detail: String?
    var action: (title: String, run: () -> Void)?
    var loading = false

    var body: some View {
        VStack(spacing: 6) {
            if loading {
                ProgressView().controlSize(.small)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.primary.opacity(0.4))
            }
            Text(text).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.5))
            if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.primary.opacity(0.4)) }
            if let action {
                Button(action: action.run) {
                    Text(action.title).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .frame(minHeight: 24)
                        .glass(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClockWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let date = context.date
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.bottom, 4)
                Text(date, format: .dateTime.weekday(.wide)).font(.system(size: 13, weight: .semibold))
                Text(date, format: .dateTime.day().month(.wide)).font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date.formatted(.dateTime.hour().minute()) + ", "
                                + date.formatted(.dateTime.weekday(.wide)) + ", "
                                + date.formatted(.dateTime.day().month(.wide)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clock widget")
    }
}

/// Date only: no EventKit, no calendar permission (the human's decision).
struct CalendarWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let date = Calendar.current.startOfDay(for: context.date)
            content(date)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar widget")
    }

    private func content(_ today: Date) -> some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let week = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let month = cal.component(.month, from: today)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: today.formatted(.dateTime.month(.wide).year()))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(today, format: .dateTime.day()).font(.system(size: 28, weight: .bold))
                    Text(today, format: .dateTime.weekday(.wide)).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                .padding(.bottom, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(today.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
                    let isToday = cal.isDate(day, inSameDayAs: today)
                    VStack(spacing: 2) {
                        Text(cal.veryShortWeekdaySymbols[cal.component(.weekday, from: day) - 1])
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.primary.opacity(0.5))
                        Text(day, format: .dateTime.day())
                            .font(.system(size: 11, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? AnyShapeStyle(.white)
                                             : AnyShapeStyle(.primary.opacity(cal.component(.month, from: day) == month ? 0.85 : 0.4)))
                            .frame(width: 20, height: 20)
                            .background { if isToday { Circle().fill(Color.accentColor) } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Week of " + (week.first?.formatted(.dateTime.day()) ?? "") + " to "
                                + (week.last?.formatted(.dateTime.day().month(.wide)) ?? ""))
            Spacer(minLength: 0)
        }
    }
}

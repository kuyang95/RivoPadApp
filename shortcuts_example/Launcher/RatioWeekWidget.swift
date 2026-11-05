import SwiftUI

struct RatioWeekWidget: View {
    let onEdit: () -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var dayWidth = 40.0

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = context.date
            let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
            let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            ViewThatFits(in: .horizontal) {
                weekRow(week, today: today, columns: 7)
                VStack(spacing: 4) {
                    weekRow(Array(week.prefix(4)), today: today, columns: 4)
                    weekRow(Array(week.dropFirst(4)), today: today, columns: 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(RatioExperience().background.opacity(0.86), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func weekRow(_ dates: [Date], today: Date, columns: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(dates, id: \.self) { date in
                let current = calendar.isDate(date, inSameDayAs: today)
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.day().locale(locale)))
                        .visionCraftAndroidText(26, weight: current ? .bold : .semibold)
                    Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                        .visionCraftAndroidText(14)
                        .foregroundStyle(current ? RatioExperience().accent : RatioExperience().text.opacity(0.8))
                }
                .foregroundStyle(RatioExperience().text)
                .padding(.vertical, 6)
                .frame(minWidth: dayWidth, maxWidth: .infinity, minHeight: 64)
                .overlay {
                    if current {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(RatioExperience().outline, lineWidth: 1.5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year().locale(locale)))
                .accessibilityAddTraits(current ? .isSelected : [])
                .accessibilityAction(named: "위젯 설정") { onEdit() }
            }
            ForEach(dates.count..<columns, id: \.self) { _ in
                Color.clear.frame(minWidth: dayWidth, maxWidth: .infinity, maxHeight: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

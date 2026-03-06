import SwiftUI

struct CalendarTabView: View {
    var settings: Settings
    let entries: [DayEntry]
    let netConfigs: [NetWageMonthConfig]
    let holidays: [HolidayCalendarDay]
    let isOffline: Bool

    @State private var displayedMonth = Date()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { previousMonth() }) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(monthYearString(displayedMonth))
                    .font(.headline)
                Spacer()
                Button(action: { nextMonth() }) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)

            CalendarMonthView(settings: settings, entries: entries, netConfigs: netConfigs, holidays: holidays)
                .frame(minHeight: 300)

            if isOffline {
                Label("Offline", systemImage: "wifi.slash")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    private func previousMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    private func nextMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}

#Preview {
    CalendarTabView(settings: Settings(), entries: [], netConfigs: [], holidays: [], isOffline: false)
}

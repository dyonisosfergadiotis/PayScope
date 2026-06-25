import Combine
import Foundation

@MainActor
final class TVWeeklyScheduleViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(TVWeekSchedule)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var selectedWeekStart: Date

    private let calendar: Calendar
    private let store: TVCloudKitShiftStore

    init(
        calendar: Calendar = .current,
        store: TVCloudKitShiftStore = .shared,
        referenceDate: Date = Date()
    ) {
        self.calendar = calendar
        self.store = store
        selectedWeekStart = Self.startOfWeek(containing: referenceDate, calendar: calendar)
    }

    func reload() async {
        state = .loading
        do {
            let schedule = try await store.fetchWeek(startingAt: selectedWeekStart, calendar: calendar)
            state = .loaded(schedule)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func moveWeek(by value: Int) {
        selectedWeekStart = calendar.date(byAdding: .day, value: value * 7, to: selectedWeekStart) ?? selectedWeekStart
        Task {
            await reload()
        }
    }

    func jumpToCurrentWeek() {
        selectedWeekStart = Self.startOfWeek(containing: Date(), calendar: calendar)
        Task {
            await reload()
        }
    }

    static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}

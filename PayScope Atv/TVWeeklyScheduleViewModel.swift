import Combine
import Foundation

@MainActor
final class TVWeeklyScheduleViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(TVWeekSchedule, notice: String?)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var selectedWeekStart: Date

    private let calendar: Calendar
    private let cloudStore: TVShiftScheduleStore
    private let localStore: TVShiftScheduleStore
    private let cacheStore: TVWeekScheduleCacheStore
    private let allowsLocalFallback: Bool
    private let cacheFreshnessInterval: TimeInterval = 10 * 60

    convenience init(referenceDate: Date = Date()) {
        self.init(
            calendar: .current,
            cloudStore: TVCloudKitShiftStore.shared,
            localStore: TVLocalShiftStore(),
            cacheStore: TVWeekScheduleCacheStore(),
            allowsLocalFallback: Self.defaultAllowsLocalFallback,
            referenceDate: referenceDate
        )
    }

    init(
        calendar: Calendar,
        cloudStore: TVShiftScheduleStore,
        localStore: TVShiftScheduleStore,
        cacheStore: TVWeekScheduleCacheStore,
        allowsLocalFallback: Bool,
        referenceDate: Date = Date()
    ) {
        self.calendar = calendar
        self.cloudStore = cloudStore
        self.localStore = localStore
        self.cacheStore = cacheStore
        self.allowsLocalFallback = allowsLocalFallback
        selectedWeekStart = Self.startOfWeek(containing: referenceDate, calendar: calendar)
    }

    func reload() async {
        let cachedSchedule = cacheStore.cachedWeek(startingAt: selectedWeekStart, calendar: calendar)
        if let cachedSchedule {
            if cacheStore.isFresh(cachedSchedule, maxAge: cacheFreshnessInterval) {
                state = .loaded(cachedSchedule, notice: nil)
                return
            }
            state = .loaded(cachedSchedule, notice: "Cache angezeigt. Aktualisierung läuft im Hintergrund.")
        } else {
            state = .loading
        }

        do {
            let schedule = try await cloudStore.fetchWeek(startingAt: selectedWeekStart, calendar: calendar)
            cacheStore.save(schedule, calendar: calendar)
            state = .loaded(schedule, notice: nil)
        } catch let cloudError {
            if let cachedSchedule {
                state = .loaded(
                    cachedSchedule,
                    notice: "Cache angezeigt, iCloud gerade nicht aktualisiert: \(cloudError.localizedDescription)"
                )
                return
            }

            guard allowsLocalFallback else {
                state = .failed(cloudError.localizedDescription)
                return
            }

            do {
                let schedule = try await localStore.fetchWeek(startingAt: selectedWeekStart, calendar: calendar)
                cacheStore.save(schedule, calendar: calendar)
                state = .loaded(schedule, notice: "Lokale Demo-Schichten, weil iCloud nicht verfügbar ist: \(cloudError.localizedDescription)")
            } catch {
                state = .failed(error.localizedDescription)
            }
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

    private static var defaultAllowsLocalFallback: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

import Foundation

struct TVWeekScheduleCacheStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = baseURL
            .appendingPathComponent("PayScope", isDirectory: true)
            .appendingPathComponent("TVWeekSchedules", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func cachedWeek(startingAt weekStart: Date, calendar: Calendar) -> TVWeekSchedule? {
        let url = cacheURL(for: weekStart, calendar: calendar)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(TVWeekSchedule.self, from: data)
    }

    func save(_ schedule: TVWeekSchedule, calendar: Calendar) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(schedule)
            try data.write(to: cacheURL(for: schedule.weekStart, calendar: calendar), options: [.atomic])
        } catch {
            assertionFailure("Could not cache tvOS week schedule: \(error.localizedDescription)")
        }
    }

    func isFresh(_ schedule: TVWeekSchedule, maxAge: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(schedule.generatedAt) < maxAge
    }

    private func cacheURL(for weekStart: Date, calendar: Calendar) -> URL {
        directoryURL.appendingPathComponent("\(weekKey(for: weekStart, calendar: calendar)).json")
    }

    private func weekKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
    }
}

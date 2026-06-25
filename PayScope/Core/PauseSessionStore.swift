import Foundation

struct PauseSessionSnapshot: Codable, Equatable, Sendable {
    var startedAt: Date
    var shiftDayStart: Date
    var shiftStart: Date
    var shiftEnd: Date
}

enum PauseSessionStore {
    private static let appGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    private static let sessionKey = "payscope.pauseSession.v1"

    static func load() -> PauseSessionSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: sessionKey)
        else {
            return nil
        }

        return try? JSONDecoder().decode(PauseSessionSnapshot.self, from: data)
    }

    static func save(_ snapshot: PauseSessionSnapshot) {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }

        defaults.set(data, forKey: sessionKey)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: sessionKey)
    }
}

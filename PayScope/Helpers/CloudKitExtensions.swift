import CloudKit
import Foundation
import SwiftUI

// MARK: - Environment Key for CloudKitViewModel

private struct CloudKitViewModelKey: EnvironmentKey {
    static let defaultValue: CloudKitViewModel? = nil
}

extension EnvironmentValues {
    var cloudKitViewModel: CloudKitViewModel? {
        get { self[CloudKitViewModelKey.self] }
        set { self[CloudKitViewModelKey.self] = newValue }
    }
}

// MARK: - View Extension for CloudKit Integration

extension View {
    func withCloudKit(viewModel: CloudKitViewModel) -> some View {
        environment(\.cloudKitViewModel, viewModel)
    }
}

// MARK: - Date Extension for CloudKit Formatting

extension Date {
    var cloudKitDescription: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    static func startOfDayUTC() -> Date {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: Date.now)
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? Date.now
    }
}

// MARK: - CKAccountStatus Extension

extension CKAccountStatus {
    var description: String {
        switch self {
        case .available:
            return "Verfügbar"
        case .restricted:
            return "Eingeschränkt"
        case .noAccount:
            return "Kein Konto"
        case .couldNotDetermine:
            return "Wird überprüft..."
        case .temporarilyUnavailable:
            return "Nicht verfügbar"
        @unknown default:
            return "Unbekannt"
        }
    }

    var isAvailable: Bool {
        self == .available
    }
}

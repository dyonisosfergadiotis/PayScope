import CloudKit
import Combine
import Foundation
import os
import SwiftUI

@MainActor
final class CloudKitViewModel: ObservableObject {
    private static let logger = Logger(
        subsystem: "com.dyonisos.paysco",
        category: String(describing: CloudKitViewModel.self)
    )

    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published var syncError: Error?

    private let cloudKitService = CloudKitService.shared

    func fetchAccountStatus() async {
        do {
            accountStatus = try await cloudKitService.checkAccountStatus()
            Self.logger.info("Account status: \(String(describing: self.accountStatus), privacy: .public)")
        } catch {
            Self.logger.error("Failed to fetch account status: \(error.localizedDescription, privacy: .public)")
            syncError = error
        }
    }

    func syncDayEntries(_ entries: [DayEntry]) async {
        isSyncing = true
        defer { isSyncing = false }

        for entry in entries {
            do {
                try await cloudKitService.saveDayEntry(entry)
            } catch {
                Self.logger.error("Failed to sync DayEntry: \(error.localizedDescription, privacy: .public)")
                syncError = error
                return
            }
        }

        lastSyncDate = Date.now
        Self.logger.info("Successfully synced \(entries.count) entries")
    }

    func fetchDayEntriesFromCloud(in interval: DateInterval) async -> [DayEntry]? {
        do {
            let entries = try await cloudKitService.fetchDayEntries(in: interval)
            return entries
        } catch {
            Self.logger.error("Failed to fetch DayEntries: \(error.localizedDescription, privacy: .public)")
            syncError = error
            return nil
        }
    }

    func isAccountAvailable() -> Bool {
        accountStatus == .available
    }
}

import Foundation

struct LocalTipDeletionTombstone: Codable, Equatable {
    var id: String
    var lastModified: Date
}

private struct LocalSyncedTipMarker: Codable, Equatable {
    var id: String
    var lastSyncedAt: Date
}

final class LocalTipEntryStore {
    static let shared = LocalTipEntryStore()

    private let queue = DispatchQueue(label: "LocalTipEntryStore.queue")
    private let fileManager = FileManager.default
    private let directoryURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("TipEntries", isDirectory: true)
        ensureDirectory()
    }

    func loadAll() -> [TipEntry] {
        queue.sync {
            loadAllEntries()
        }
    }

    func loadAll(in interval: DateInterval) -> [TipEntry] {
        queue.sync {
            loadAllEntries()
                .filter { interval.contains($0.date) }
        }
    }

    func save(_ tip: TipEntry) {
        queue.sync {
            upsert(tip)
            clearDeletionTombstoneIfPresent(for: tip.id)
        }
    }

    func upsertMany(_ tips: [TipEntry], markSynced: Bool = true) {
        guard !tips.isEmpty else { return }
        queue.sync {
            for tip in tips {
                upsert(tip)
                clearDeletionTombstoneIfPresent(for: tip.id)
                if markSynced {
                    writeSyncedMarker(for: tip.id)
                }
            }
        }
    }

    func delete(_ tip: TipEntry, markTombstone: Bool = true, deletedAt: Date = Date()) {
        queue.sync {
            try? fileManager.removeItem(at: fileURL(for: tip.id))
            if markTombstone {
                writeDeletionTombstone(LocalTipDeletionTombstone(id: tip.id, lastModified: deletedAt))
            } else {
                clearDeletionTombstoneIfPresent(for: tip.id)
                clearSyncedMarkerIfPresent(for: tip.id)
            }
        }
    }

    func markSynced(_ tip: TipEntry) {
        queue.sync {
            writeSyncedMarker(for: tip.id)
            clearDeletionTombstoneIfPresent(for: tip.id)
        }
    }

    func isSynced(id: String) -> Bool {
        queue.sync {
            fileManager.fileExists(atPath: syncedMarkerFileURL(for: id).path)
        }
    }

    func clearSyncedMarker(id: String) {
        queue.sync {
            _ = clearSyncedMarkerIfPresent(for: id)
        }
    }

    func clearDeletionTombstone(id: String) {
        queue.sync {
            _ = clearDeletionTombstoneIfPresent(for: id)
        }
    }

    func loadDeletionTombstones() -> [LocalTipDeletionTombstone] {
        queue.sync {
            guard let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
                return []
            }

            return files
                .filter { $0.lastPathComponent.hasPrefix("deleted-") && $0.pathExtension == "json" }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? decoder.decode(LocalTipDeletionTombstone.self, from: data)
                }
        }
    }

    func resetAll() {
        queue.sync {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try? fileManager.removeItem(at: directoryURL)
            }
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func loadAllEntries() -> [TipEntry] {
        guard let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter {
                $0.pathExtension == "json" &&
                !$0.lastPathComponent.hasPrefix("deleted-") &&
                !$0.lastPathComponent.hasPrefix("synced-")
            }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(TipEntry.self, from: data)
            }
            .sorted { $0.date > $1.date }
    }

    private func upsert(_ incoming: TipEntry) {
        let url = fileURL(for: incoming.id)
        if let data = try? Data(contentsOf: url),
           let existing = try? decoder.decode(TipEntry.self, from: data),
           existing.updatedAt > incoming.updatedAt {
            return
        }

        guard let data = try? encoder.encode(incoming) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func writeDeletionTombstone(_ tombstone: LocalTipDeletionTombstone) {
        guard let data = try? encoder.encode(tombstone) else { return }
        try? data.write(to: deletionTombstoneFileURL(for: tombstone.id), options: [.atomic])
    }

    private func writeSyncedMarker(for id: String) {
        let marker = LocalSyncedTipMarker(id: id, lastSyncedAt: Date())
        guard let data = try? encoder.encode(marker) else { return }
        try? data.write(to: syncedMarkerFileURL(for: id), options: [.atomic])
    }

    @discardableResult
    private func clearDeletionTombstoneIfPresent(for id: String) -> Bool {
        removeFileIfPresent(at: deletionTombstoneFileURL(for: id))
    }

    @discardableResult
    private func clearSyncedMarkerIfPresent(for id: String) -> Bool {
        removeFileIfPresent(at: syncedMarkerFileURL(for: id))
    }

    @discardableResult
    private func removeFileIfPresent(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try? fileManager.removeItem(at: url)
        return true
    }

    private func fileURL(for id: String) -> URL {
        directoryURL.appendingPathComponent("\(safeFileName(for: id)).json")
    }

    private func deletionTombstoneFileURL(for id: String) -> URL {
        directoryURL.appendingPathComponent("deleted-\(safeFileName(for: id)).json")
    }

    private func syncedMarkerFileURL(for id: String) -> URL {
        directoryURL.appendingPathComponent("synced-\(safeFileName(for: id)).json")
    }

    private func safeFileName(for id: String) -> String {
        id.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? String(character)
                : "_"
        }
        .joined()
    }
}

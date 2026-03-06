import Foundation

struct LocalCloudSnapshotEnvelope: Codable {
    let snapshot: CloudSnapshot
    let savedAt: Date
}

actor LocalCloudSnapshotStore {
    static let shared = LocalCloudSnapshotStore()

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let fileURL: URL

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = base.appendingPathComponent("PayScopeForMac", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("cloud_snapshot.json")
    }

    func load() -> LocalCloudSnapshotEnvelope? {
        ensureDirectoryExists()
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(LocalCloudSnapshotEnvelope.self, from: data)
    }

    func save(snapshot: CloudSnapshot) {
        ensureDirectoryExists()
        let envelope = LocalCloudSnapshotEnvelope(
            snapshot: snapshot,
            savedAt: Date()
        )
        guard let data = try? encoder.encode(envelope) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

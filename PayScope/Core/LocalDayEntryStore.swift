// LocalDayEntryStore.swift
// Lightweight JSON-backed local cache for DayEntry per day with LWW merge.

import Foundation
import Combine

// NOTE: This file is self-contained and does not depend on app model types at compile time.
// It provides bridging helpers to map to/from your app's DayEntry and DayType at runtime.
// Replace the bridging with your concrete types if needed.

// MARK: - Minimal mirrors used for persistence
fileprivate struct CachedEntry: Codable, Equatable {
    var date: Date
    // Explicit components to avoid timezone drift when keying and calendar display
    var year: Int
    var month: Int
    var day: Int
    var typeRaw: String
    var notes: String
    var shiftStart: Date?
    var shiftEnd: Date?
    var breakSeconds: Int?
    var manualWorkedSeconds: Int?
    var creditedOverrideSeconds: Int?
    var lastModified: Date
}

fileprivate struct LegacyCachedEntry: Codable, Equatable {
    var date: Date
    var typeRaw: String
    var notes: String
    var shiftStart: Date?
    var shiftEnd: Date?
    var breakSeconds: Int?
    var manualWorkedSeconds: Int?
    var creditedOverrideSeconds: Int?
    var lastModified: Date?
}

struct LocalDeletionTombstone: Codable, Equatable {
    var date: Date
    var lastModified: Date
}

// MARK: - Store
final class LocalDayEntryStore: ObservableObject {
    static let shared = LocalDayEntryStore()
    let objectWillChange = ObservableObjectPublisher()

    private let queue = DispatchQueue(label: "LocalDayEntryStore.queue")
    private let fileManager = FileManager.default
    private let directoryURL: URL

    private let isoEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let isoDecoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private let legacyDecoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .deferredToDate // supports numeric dates from older cache
        return dec
    }()

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DayEntries", isDirectory: true)
        directoryURL = dir
        ensureDirectory()
    }

    private func notifyChange() {
        let send: () -> Void = { [weak self] in
            self?.objectWillChange.send()
            NotificationCenter.default.post(name: .dayEntriesDidChange, object: nil)
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.async { send() }
        }
    }

    // Public API
    func loadAll() -> [DayEntry] {
        let cached: [CachedEntry] = queue.sync { loadAllCached() }
        return cached.compactMap { Self.toDayEntry($0) }
    }

    func loadAll(in interval: DateInterval) -> [DayEntry] {
        let cached: [CachedEntry] = queue.sync { loadAllCached(in: interval) }
        return cached.compactMap { Self.toDayEntry($0) }
    }

    func load(on day: Date) -> DayEntry? {
        let localKey = Self.keyFromLocalDay(day)
        let utcKey = Self.key(for: day)
        let cached: CachedEntry? = queue.sync {
            // Try local-keyed file first
            let localURL = fileURL(forKey: localKey)
            if let data = try? Data(contentsOf: localURL) {
                if let obj = try? isoDecoder.decode(CachedEntry.self, from: data) { return obj }
                if let legacy = try? legacyDecoder.decode(LegacyCachedEntry.self, from: data) { return Self.fromLegacy(legacy) }
            }
            // Fallback: try UTC-keyed file
            let utcURL = fileURL(forKey: utcKey)
            if let data = try? Data(contentsOf: utcURL) {
                if let obj = try? isoDecoder.decode(CachedEntry.self, from: data) { return obj }
                if let legacy = try? legacyDecoder.decode(LegacyCachedEntry.self, from: data) { return Self.fromLegacy(legacy) }
            }
            return nil
        }
        return cached.flatMap { Self.toDayEntry($0) }
    }

    func save(_ entry: DayEntry) {
        let cached = Self.toCached(entry)
        let didChange = queue.sync {
            let didUpsert = upsertCached(cached)
            let didClearTombstone = clearDeletionTombstoneIfPresent(for: cached.date)
            return didUpsert || didClearTombstone
        }
        if didChange {
            notifyChange()
        }
    }

    func save(date: Date, shiftStart: Date?, shiftEnd: Date?, type: DayType, notes: String = "", breakSeconds: Int? = nil, manualWorkedSeconds: Int? = nil, creditedOverrideSeconds: Int? = nil) {
        let entry = DayEntry(date: date, type: type, notes: notes)
        entry.shiftStart = shiftStart
        entry.shiftEnd = shiftEnd
        entry.breakSeconds = breakSeconds ?? 0
        entry.manualWorkedSeconds = manualWorkedSeconds
        entry.creditedOverrideSeconds = creditedOverrideSeconds
        save(entry)
    }

    func upsertMany(_ entries: [DayEntry], notify: Bool = true) {
        guard !entries.isEmpty else { return }
        let cached = entries.map(Self.toCached)
        let changedAny = queue.sync {
            var changed = false
            for e in cached {
                if upsertCached(e) {
                    changed = true
                }
            }
            return changed
        }
        if notify && changedAny {
            notifyChange()
        }
    }

    func delete(on day: Date, markTombstone: Bool = true, deletedAt: Date = Date()) {
        let localKey = Self.keyFromLocalDay(day)
        let utcKey = Self.key(for: day)
        let didChange = queue.sync {
            var changed = false
            let localURL = fileURL(forKey: localKey)
            let utcURL = fileURL(forKey: utcKey)
            if fileManager.fileExists(atPath: localURL.path) {
                try? fileManager.removeItem(at: localURL)
                changed = true
            }
            if utcURL != localURL, fileManager.fileExists(atPath: utcURL.path) {
                try? fileManager.removeItem(at: utcURL)
                changed = true
            }
            if markTombstone {
                let normalizedDate = Self.utcDateForLocalCivilDay(day)
                let key = Self.key(for: normalizedDate)
                let tombstone = LocalDeletionTombstone(date: normalizedDate, lastModified: deletedAt)
                let tombstoneURL = tombstoneFileURL(forKey: key)
                if let data = try? isoEncoder.encode(tombstone) {
                    try? data.write(to: tombstoneURL, options: [.atomic])
                    changed = true
                }
            } else {
                if clearDeletionTombstoneIfPresent(for: day) {
                    changed = true
                }
            }
            return changed
        }
        if didChange {
            notifyChange()
        }
    }

    func resetAll() {
        queue.sync {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try? fileManager.removeItem(at: directoryURL)
            }
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        notifyChange()
    }

    func clearDeletionTombstone(on day: Date) {
        let didChange = queue.sync {
            clearDeletionTombstoneIfPresent(for: day)
        }
        if didChange {
            notifyChange()
        }
    }

    func deletionTimestamp(on day: Date) -> Date? {
        queue.sync {
            for key in Self.tombstoneCandidateKeys(for: day) {
                let url = tombstoneFileURL(forKey: key)
                if let data = try? Data(contentsOf: url),
                   let tombstone = try? isoDecoder.decode(LocalDeletionTombstone.self, from: data) {
                    return tombstone.lastModified
                }
            }
            return nil
        }
    }

    func loadDeletionTombstones() -> [LocalDeletionTombstone] {
        queue.sync {
            guard let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
                return []
            }
            var result: [LocalDeletionTombstone] = []
            for url in files where url.lastPathComponent.hasPrefix("deleted-") && url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let tombstone = try? isoDecoder.decode(LocalDeletionTombstone.self, from: data) else {
                    continue
                }
                result.append(tombstone)
            }
            return result
        }
    }

    // MARK: - Internal helpers
    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent("\(key).json")
    }

    private func tombstoneFileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent("deleted-\(key).json")
    }

    private func loadAllCached() -> [CachedEntry] {
        guard let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { return [] }
        var result: [CachedEntry] = []
        for url in files where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("deleted-") {
            if let data = try? Data(contentsOf: url) {
                if let obj = try? isoDecoder.decode(CachedEntry.self, from: data) {
                    result.append(obj)
                } else if let legacy = try? legacyDecoder.decode(LegacyCachedEntry.self, from: data) {
                    result.append(Self.fromLegacy(legacy))
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    private func loadAllCached(in interval: DateInterval) -> [CachedEntry] {
        guard let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [CachedEntry] = []
        for url in files where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("deleted-") {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let obj = try? isoDecoder.decode(CachedEntry.self, from: data), interval.contains(obj.date) {
                result.append(obj)
            } else if let legacy = try? legacyDecoder.decode(LegacyCachedEntry.self, from: data) {
                let migrated = Self.fromLegacy(legacy)
                if interval.contains(migrated.date) {
                    result.append(migrated)
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    @discardableResult
    private func upsertCached(_ incoming: CachedEntry) -> Bool {
        let key = Self.key(for: incoming.date)
        let url = fileURL(forKey: key)
        var final = incoming
        var existing: CachedEntry?
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? isoDecoder.decode(CachedEntry.self, from: data) {
                final = merge(local: decoded, remote: incoming)
                existing = decoded
            } else if let legacy = try? legacyDecoder.decode(LegacyCachedEntry.self, from: data) {
                let migrated = Self.fromLegacy(legacy)
                final = merge(local: migrated, remote: incoming)
                existing = migrated
            }
        }
        if let existing, existing == final {
            return false
        }
        if let data = try? isoEncoder.encode(final) {
            try? data.write(to: url, options: [.atomic])
            return true
        }
        return false
    }

    @discardableResult
    private func clearDeletionTombstoneIfPresent(for day: Date) -> Bool {
        var removed = false
        for key in Self.tombstoneCandidateKeys(for: day) {
            let url = tombstoneFileURL(forKey: key)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
                removed = true
            }
        }
        return removed
    }

    // Last-Write-Wins on entry level: prefer newer lastModified.
    private func merge(local: CachedEntry, remote: CachedEntry) -> CachedEntry {
        // If dates differ in local timezone day, prefer remote's date field (but keys are per day).
        if remote.lastModified >= local.lastModified {
            return remote
        } else {
            return local
        }
    }

    // MARK: - Keying helpers
    // Builds a key from the local civil day (used when callers pass a UI-selected local date)
    private static func keyFromLocalDay(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    
    // Note: keys are UTC-normalized to avoid timezone drift.
    private static func key(for date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = utc.startOfDay(for: date)
        let comps = utc.dateComponents([.year, .month, .day], from: start)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // Map a local civil day to UTC midnight of the same Y-M-D.
    private static func utcDateForLocalCivilDay(_ date: Date) -> Date {
        let localComps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: localComps) ?? date.startOfDayUTC()
    }

    private static func tombstoneCandidateKeys(for day: Date) -> [String] {
        let candidates = [
            key(for: day), // legacy path
            key(for: utcDateForLocalCivilDay(day))
        ]
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func fromLegacy(_ legacy: LegacyCachedEntry) -> CachedEntry {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = utc.startOfDay(for: legacy.date)
        let comps = utc.dateComponents([.year, .month, .day], from: start)
        return CachedEntry(
            date: start,
            year: comps.year ?? 0,
            month: comps.month ?? 0,
            day: comps.day ?? 0,
            typeRaw: legacy.typeRaw,
            notes: legacy.notes,
            shiftStart: legacy.shiftStart,
            shiftEnd: legacy.shiftEnd,
            breakSeconds: legacy.breakSeconds,
            manualWorkedSeconds: legacy.manualWorkedSeconds,
            creditedOverrideSeconds: legacy.creditedOverrideSeconds,
            lastModified: legacy.lastModified ?? start
        )
    }

    // MARK: - Bridging
    // NOTE: These helpers assume DayEntry & DayType exist in the app target.
    // If they don't at compile time, adjust access control or move this file into the app target.
    private static func toCached(_ entry: DayEntry) -> CachedEntry {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = utc.startOfDay(for: entry.date)
        let comps = utc.dateComponents([.year, .month, .day], from: startOfDay)
        return CachedEntry(
            date: startOfDay,
            year: comps.year ?? 0,
            month: comps.month ?? 0,
            day: comps.day ?? 0,
            typeRaw: entry.type.rawValue,
            notes: entry.notes,
            shiftStart: entry.shiftStart,
            shiftEnd: entry.shiftEnd,
            breakSeconds: entry.breakSeconds,
            manualWorkedSeconds: entry.manualWorkedSeconds,
            creditedOverrideSeconds: entry.creditedOverrideSeconds,
            lastModified: entry.updatedAt
        )
    }

    private static func toDayEntry(_ cached: CachedEntry) -> DayEntry? {
        let type = DayType(rawValue: cached.typeRaw) ?? .work
        let e = DayEntry(date: cached.date, updatedAt: cached.lastModified, type: type, notes: cached.notes)
        e.shiftStart = cached.shiftStart
        e.shiftEnd = cached.shiftEnd
        e.breakSeconds = cached.breakSeconds ?? 0
        e.manualWorkedSeconds = cached.manualWorkedSeconds
        e.creditedOverrideSeconds = cached.creditedOverrideSeconds
        return e
    }
}

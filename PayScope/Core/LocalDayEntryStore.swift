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
    var alwaysApplyFifteenMinuteBuffer: Bool?
    var tipAmountCents: Int?
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
    var alwaysApplyFifteenMinuteBuffer: Bool?
    var tipAmountCents: Int?
    var lastModified: Date?
}

struct LocalDeletionTombstone: Codable, Equatable {
    var date: Date
    var lastModified: Date
}

struct DayEntriesChangePayload {
    let changedDays: Set<Date>
    let invalidatesAllEntries: Bool

    init(changedDays: [Date] = [], invalidatesAllEntries: Bool = false) {
        self.changedDays = Set(changedDays.map { $0.startOfDayLocal() })
        self.invalidatesAllEntries = invalidatesAllEntries
    }
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

    private func notifyChange(changedDays: [Date] = [], invalidatesAllEntries: Bool = false) {
        let payload = DayEntriesChangePayload(
            changedDays: changedDays,
            invalidatesAllEntries: invalidatesAllEntries
        )
        let send: () -> Void = { [weak self] in
            self?.objectWillChange.send()
            NotificationCenter.default.post(name: .dayEntriesDidChange, object: payload)
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.async { send() }
        }
    }

    // Public API
    func loadAll() -> [DayEntry] {
        let cached: [CachedEntry] = queue.sync {
            loadAllCached().filter { !isSuppressedByDeletionTombstone($0) }
        }
        return cached.compactMap { Self.toDayEntry($0) }
    }

    func loadAll(in interval: DateInterval) -> [DayEntry] {
        let cached: [CachedEntry] = queue.sync {
            loadAllCached(in: interval).filter { !isSuppressedByDeletionTombstone($0) }
        }
        return cached.compactMap { Self.toDayEntry($0) }
    }

    func load(on day: Date) -> DayEntry? {
        let localDay = day.startOfDayLocal()
        let localKey = Self.keyFromLocalDay(localDay)
        let canonicalKey = Self.key(for: Self.utcDateForLocalCivilDay(localDay))
        let legacyUTCKey = Self.key(for: localDay)
        var seenKeys = Set<String>()
        let candidateKeys = [localKey, canonicalKey, legacyUTCKey].filter { seenKeys.insert($0).inserted }
        let cached: CachedEntry? = queue.sync {
            for key in candidateKeys {
                let url = fileURL(forKey: key)
                guard let data = try? Data(contentsOf: url) else { continue }

                if let obj = try? isoDecoder.decode(CachedEntry.self, from: data) {
                    guard Self.cachedEntry(obj, representsLocalDay: localDay) else { continue }
                    return isSuppressedByDeletionTombstone(obj) ? nil : obj
                }

                if let legacy = try? legacyDecoder.decode(LegacyCachedEntry.self, from: data) {
                    let migrated = Self.fromLegacy(legacy)
                    guard Self.cachedEntry(migrated, representsLocalDay: localDay) else { continue }
                    return isSuppressedByDeletionTombstone(migrated) ? nil : migrated
                }
            }
            return nil
        }
        return cached.flatMap { Self.toDayEntry($0) }
    }

    func save(_ entry: DayEntry) {
        let cached = Self.toCached(entry)
        let didChange = queue.sync {
            if isSuppressedByDeletionTombstone(cached) {
                return false
            }
            let didUpsert = upsertCached(cached)
            let didClearTombstone = clearDeletionTombstoneIfPresent(for: cached.date)
            return didUpsert || didClearTombstone
        }
        if didChange {
            notifyChange(changedDays: [cached.date])
        }
    }

    func save(
        date: Date,
        shiftStart: Date?,
        shiftEnd: Date?,
        type: DayType,
        notes: String = "",
        breakSeconds: Int? = nil,
        manualWorkedSeconds: Int? = nil,
        creditedOverrideSeconds: Int? = nil,
        alwaysApplyFifteenMinuteBuffer: Bool? = nil
    ) {
        _ = notes
        let entry = DayEntry(date: date, type: type)
        entry.shiftStart = shiftStart
        entry.shiftEnd = shiftEnd
        entry.breakSeconds = breakSeconds ?? 0
        entry.manualWorkedSeconds = manualWorkedSeconds
        entry.creditedOverrideSeconds = creditedOverrideSeconds
        entry.alwaysApplyFifteenMinuteBuffer = alwaysApplyFifteenMinuteBuffer
        save(entry)
    }

    func upsertMany(_ entries: [DayEntry], notify: Bool = true) {
        guard !entries.isEmpty else { return }
        let cached = entries.map { Self.toCached($0) }
        let changedDays = queue.sync {
            var changedDays: [Date] = []
            for e in cached {
                if isSuppressedByDeletionTombstone(e) {
                    continue
                }
                if upsertCached(e) {
                    changedDays.append(e.date)
                }
                if clearDeletionTombstoneIfPresent(for: e.date) {
                    changedDays.append(e.date)
                }
            }
            return changedDays
        }
        if notify && !changedDays.isEmpty {
            notifyChange(changedDays: changedDays)
        }
    }

    func delete(on day: Date, markTombstone: Bool = true, deletedAt: Date = Date()) {
        let localDay = day.startOfDayLocal()
        let canonicalDate = Self.utcDateForLocalCivilDay(localDay)
        let localKey = Self.keyFromLocalDay(localDay)
        let canonicalKey = Self.key(for: canonicalDate)
        let legacyUTCKey = Self.legacyUTCKey(for: localDay)
        var seenKeys = Set<String>()
        let candidateKeys = [localKey, canonicalKey, legacyUTCKey].filter { seenKeys.insert($0).inserted }

        let didChange = queue.sync {
            var changed = false

            for key in candidateKeys {
                let url = fileURL(forKey: key)
                let forceRemovalWhenUndecodable = key == localKey || key == canonicalKey
                if removeCachedEntryIfMatchesLocalDay(
                    at: url,
                    localDay: localDay,
                    forceRemovalWhenUndecodable: forceRemovalWhenUndecodable
                ) {
                    changed = true
                }
            }

            if markTombstone {
                let tombstone = LocalDeletionTombstone(date: canonicalDate, lastModified: deletedAt)
                let tombstoneURL = tombstoneFileURL(forKey: canonicalKey)
                if let data = try? isoEncoder.encode(tombstone) {
                    try? data.write(to: tombstoneURL, options: [.atomic])
                    changed = true
                }
            } else {
                if clearDeletionTombstoneIfPresent(for: localDay) {
                    changed = true
                }
            }
            return changed
        }
        if didChange {
            notifyChange(changedDays: [localDay])
        }
    }

    func resetAll() {
        queue.sync {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try? fileManager.removeItem(at: directoryURL)
            }
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        notifyChange(invalidatesAllEntries: true)
    }

    func clearDeletionTombstone(on day: Date, notify: Bool = false) {
        let didChange = queue.sync {
            clearDeletionTombstoneIfPresent(for: day)
        }
        if didChange, notify {
            notifyChange(changedDays: [day])
        }
    }

    func deletionTimestamp(on day: Date) -> Date? {
        queue.sync {
            deletionTimestampIfPresent(for: day)
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

    private func decodeCachedEntry(from url: URL) -> CachedEntry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let obj = try? isoDecoder.decode(CachedEntry.self, from: data) {
            return obj
        }
        if let legacy = try? legacyDecoder.decode(LegacyCachedEntry.self, from: data) {
            return Self.fromLegacy(legacy)
        }
        return nil
    }

    @discardableResult
    private func removeCachedEntryIfMatchesLocalDay(
        at url: URL,
        localDay: Date,
        forceRemovalWhenUndecodable: Bool
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }

        if let cached = decodeCachedEntry(from: url) {
            guard cached.date.isSameLocalDay(as: localDay) else { return false }
            try? fileManager.removeItem(at: url)
            return true
        }

        guard forceRemovalWhenUndecodable else { return false }
        try? fileManager.removeItem(at: url)
        return true
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

    private func deletionTimestampIfPresent(for day: Date) -> Date? {
        var newest: Date?
        for key in Self.tombstoneCandidateKeys(for: day) {
            let url = tombstoneFileURL(forKey: key)
            guard let data = try? Data(contentsOf: url),
                  let tombstone = try? isoDecoder.decode(LocalDeletionTombstone.self, from: data) else {
                continue
            }

            if newest == nil || tombstone.lastModified > newest! {
                newest = tombstone.lastModified
            }
        }
        return newest
    }

    private func isSuppressedByDeletionTombstone(_ cached: CachedEntry) -> Bool {
        guard let deletedAt = deletionTimestampIfPresent(for: cached.date) else {
            return false
        }
        return deletedAt >= cached.lastModified
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

    // Legacy key strategy that interpreted the absolute date in UTC before truncating.
    private static func legacyUTCKey(for date: Date) -> String {
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
            key(for: utcDateForLocalCivilDay(day)),
            keyFromLocalDay(day)
        ]
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func cachedEntry(_ entry: CachedEntry, representsLocalDay localDay: Date) -> Bool {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: localDay)
        if entry.year == components.year,
           entry.month == components.month,
           entry.day == components.day {
            return true
        }

        return entry.date.isSameLocalDay(as: localDay)
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
            notes: "",
            shiftStart: legacy.shiftStart,
            shiftEnd: legacy.shiftEnd,
            breakSeconds: legacy.breakSeconds,
            manualWorkedSeconds: legacy.manualWorkedSeconds,
            creditedOverrideSeconds: legacy.creditedOverrideSeconds,
            alwaysApplyFifteenMinuteBuffer: legacy.alwaysApplyFifteenMinuteBuffer,
            tipAmountCents: legacy.tipAmountCents,
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
            notes: "",
            shiftStart: entry.shiftStart,
            shiftEnd: entry.shiftEnd,
            breakSeconds: entry.breakSeconds,
            manualWorkedSeconds: entry.manualWorkedSeconds,
            creditedOverrideSeconds: entry.creditedOverrideSeconds,
            alwaysApplyFifteenMinuteBuffer: entry.alwaysApplyFifteenMinuteBuffer,
            tipAmountCents: entry.tipAmountCents.map { max(0, $0) },
            lastModified: entry.updatedAt
        )
    }

    private static func toDayEntry(_ cached: CachedEntry) -> DayEntry? {
        let type = DayType.fromPersistedRaw(cached.typeRaw) ?? .work
        let e = DayEntry(date: cached.date, updatedAt: cached.lastModified, type: type)
        e.shiftStart = cached.shiftStart
        e.shiftEnd = cached.shiftEnd
        e.breakSeconds = cached.breakSeconds ?? 0
        e.manualWorkedSeconds = cached.manualWorkedSeconds
        e.creditedOverrideSeconds = cached.creditedOverrideSeconds
        e.alwaysApplyFifteenMinuteBuffer = cached.alwaysApplyFifteenMinuteBuffer
        e.tipAmountCents = cached.tipAmountCents.map { max(0, $0) }
        return e
    }
}

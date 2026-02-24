import Foundation
import SwiftData

enum ICloudSettingsSync {
    private static let payloadKey = "payScope.data.snapshot.v4"
    private static let legacyPayloadKeyV3 = "payScope.data.snapshot.v3"
    private static let legacyPayloadKeyV2 = "payScope.data.snapshot.v2"
    private static let legacySettingsPayloadKeyV1 = "payScope.settings.snapshot.v1"
    private static let localSyncStateKey = "payScope.data.localSyncState.v1"

    struct BootstrapData {
        let settings: Settings
        let dayEntries: [DayEntry]
        let netWageConfigs: [NetWageMonthConfig]
        let holidayDays: [HolidayCalendarDay]
    }

    static func bootstrapDataIfAvailable() -> BootstrapData? {
        guard let payload = loadPayload() else { return nil }
        payload.userDefaults?.value.applyToLocalStore()

        let entrySnapshots = latestRecordsByKey(payload.dayEntries)
            .values
            .compactMap { $0.value }
            .sorted(by: { $0.date < $1.date })

        let netConfigSnapshots = latestRecordsByKey(payload.netWageConfigs)
            .values
            .compactMap { $0.value }
            .sorted(by: { $0.monthStart < $1.monthStart })

        let holidaySnapshots = latestRecordsByKey(payload.holidayDays)
            .values
            .compactMap { $0.value }
            .sorted(by: { $0.key < $1.key })

        return BootstrapData(
            settings: payload.settings.value.makeSettings(),
            dayEntries: entrySnapshots.map { $0.makeDayEntry() },
            netWageConfigs: netConfigSnapshots.map { $0.makeNetWageMonthConfig() },
            holidayDays: holidaySnapshots.map { $0.makeHolidayCalendarDay() }
        )
    }

    static func forceSyncDownIntoStore(
        settings: Settings,
        localEntries: [DayEntry],
        localNetWageConfigs: [NetWageMonthConfig],
        localHolidayDays: [HolidayCalendarDay],
        modelContext: ModelContext
    ) -> Bool {
        guard let payload = loadPayload() else { return false }

        var state = loadLocalSyncState()
        state.clock = max(state.clock, maxVersion(in: payload))

        let localSettingsSnapshot = SettingsCloudSnapshot(from: settings)
        let localDefaultsSnapshot = UserDefaultsCloudSnapshot.fromLocalStore()
        let localEntrySnapshotsByKey = captureLocalDayEntryChanges(into: &state, entries: localEntries)
        let localNetConfigSnapshotsByKey = captureLocalNetWageConfigChanges(into: &state, configs: localNetWageConfigs)
        let localHolidaySnapshotsByKey = captureLocalHolidayChanges(into: &state, holidays: localHolidayDays)
        captureLocalSettingsChange(into: &state, settingsSnapshot: localSettingsSnapshot)
        captureLocalUserDefaultsChange(into: &state, userDefaultsSnapshot: localDefaultsSnapshot)

        if shouldApplyIncomingRecord(
            incomingVersion: payload.settings.version,
            incomingValue: payload.settings.value,
            localVersion: state.settings?.version ?? 0,
            localValue: localSettingsSnapshot
        ) {
            payload.settings.value.apply(to: settings)
            state.settings = LocalValueState(
                version: payload.settings.version,
                fingerprint: fingerprint(payload.settings.value)
            )
        }

        if let cloudUserDefaults = payload.userDefaults,
           shouldApplyIncomingRecord(
               incomingVersion: cloudUserDefaults.version,
               incomingValue: cloudUserDefaults.value,
               localVersion: state.userDefaults?.version ?? 0,
               localValue: localDefaultsSnapshot
           ) {
            cloudUserDefaults.value.applyToLocalStore()
            state.userDefaults = LocalValueState(
                version: cloudUserDefaults.version,
                fingerprint: fingerprint(cloudUserDefaults.value)
            )
        }

        let localEntriesByKey = Dictionary(
            localEntries.map { (dayEntryKey(for: $0.date), $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let localNetConfigsByKey = Dictionary(
            localNetWageConfigs.map { (netWageConfigKey(for: $0.monthStart), $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let localHolidaysByKey = Dictionary(
            localHolidayDays.map { ($0.key, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        for (_, cloudRecord) in latestRecordsByKey(payload.dayEntries) {
            applyCloudDayRecord(
                cloudRecord,
                localVersion: state.dayEntries[cloudRecord.key]?.version ?? 0,
                localSnapshot: localEntrySnapshotsByKey[cloudRecord.key],
                localObject: localEntriesByKey[cloudRecord.key],
                modelContext: modelContext,
                stateUpdater: { version, isDeleted, snapshot in
                    state.dayEntries[cloudRecord.key] = LocalEntityState(
                        version: version,
                        isDeleted: isDeleted,
                        fingerprint: snapshot.map { fingerprint($0) }
                    )
                }
            )
        }

        for (_, cloudRecord) in latestRecordsByKey(payload.netWageConfigs) {
            applyCloudNetWageRecord(
                cloudRecord,
                localVersion: state.netWageConfigs[cloudRecord.key]?.version ?? 0,
                localSnapshot: localNetConfigSnapshotsByKey[cloudRecord.key],
                localObject: localNetConfigsByKey[cloudRecord.key],
                modelContext: modelContext,
                stateUpdater: { version, isDeleted, snapshot in
                    state.netWageConfigs[cloudRecord.key] = LocalEntityState(
                        version: version,
                        isDeleted: isDeleted,
                        fingerprint: snapshot.map { fingerprint($0) }
                    )
                }
            )
        }

        for (_, cloudRecord) in latestRecordsByKey(payload.holidayDays) {
            applyCloudHolidayRecord(
                cloudRecord,
                localVersion: state.holidayDays[cloudRecord.key]?.version ?? 0,
                localSnapshot: localHolidaySnapshotsByKey[cloudRecord.key],
                localObject: localHolidaysByKey[cloudRecord.key],
                modelContext: modelContext,
                stateUpdater: { version, isDeleted, snapshot in
                    state.holidayDays[cloudRecord.key] = LocalEntityState(
                        version: version,
                        isDeleted: isDeleted,
                        fingerprint: snapshot.map { fingerprint($0) }
                    )
                }
            )
        }

        saveLocalSyncState(state)
        return true
    }

    static func shouldHandleExternalChange(_ notification: Notification) -> Bool {
        guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return true
        }

        return changedKeys.contains(payloadKey) ||
            changedKeys.contains(legacyPayloadKeyV3) ||
            changedKeys.contains(legacyPayloadKeyV2) ||
            changedKeys.contains(legacySettingsPayloadKeyV1)
    }

    static func export(
        settings: Settings,
        entries: [DayEntry],
        netWageConfigs: [NetWageMonthConfig],
        holidayDays: [HolidayCalendarDay]
    ) {
        guard settings.hasCompletedOnboarding else { return }

        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()

        let cloudPayload = loadPayload(store: store, alreadySynchronized: true)
        var state = loadLocalSyncState()

        if let cloudPayload {
            state.clock = max(state.clock, maxVersion(in: cloudPayload))
        }

        let settingsSnapshot = SettingsCloudSnapshot(from: settings)
        let userDefaultsSnapshot = UserDefaultsCloudSnapshot.fromLocalStore()

        let localEntrySnapshotsByKey = captureLocalDayEntryChanges(into: &state, entries: entries)
        let localNetConfigSnapshotsByKey = captureLocalNetWageConfigChanges(into: &state, configs: netWageConfigs)
        let localHolidaySnapshotsByKey = captureLocalHolidayChanges(into: &state, holidays: holidayDays)
        captureLocalSettingsChange(into: &state, settingsSnapshot: settingsSnapshot)
        captureLocalUserDefaultsChange(into: &state, userDefaultsSnapshot: userDefaultsSnapshot)

        let localPayload = payloadFromLocalState(
            state: state,
            settingsSnapshot: settingsSnapshot,
            userDefaultsSnapshot: userDefaultsSnapshot,
            daySnapshotsByKey: localEntrySnapshotsByKey,
            netConfigSnapshotsByKey: localNetConfigSnapshotsByKey,
            holidaySnapshotsByKey: localHolidaySnapshotsByKey
        )

        let mergedPayload = merge(localPayload: localPayload, cloudPayload: cloudPayload)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(mergedPayload) else {
            saveLocalSyncState(state)
            return
        }

        if let existingPayload = store.data(forKey: payloadKey), existingPayload == encoded {
            saveLocalSyncState(state)
            return
        }

        store.set(encoded, forKey: payloadKey)
        store.synchronize()
        saveLocalSyncState(state)
    }

    private static func loadPayload(
        store: NSUbiquitousKeyValueStore = .default,
        alreadySynchronized: Bool = false
    ) -> CloudPayload? {
        if !alreadySynchronized {
            store.synchronize()
        }

        let decoder = JSONDecoder()

        if let data = store.data(forKey: payloadKey),
           let payload = try? decoder.decode(CloudPayload.self, from: data) {
            return payload
        }

        if let data = store.data(forKey: legacyPayloadKeyV3),
           let legacyV3 = try? decoder.decode(LegacyCloudPayloadV3.self, from: data) {
            return convertLegacyV3ToV4(legacyV3)
        }

        if let data = store.data(forKey: legacyPayloadKeyV2),
           let legacyV2 = try? decoder.decode(LegacyCloudPayloadV2.self, from: data) {
            return convertLegacyV2ToV4(legacyV2)
        }

        if let legacyData = store.data(forKey: legacySettingsPayloadKeyV1),
           let legacySettings = try? decoder.decode(SettingsCloudSnapshot.self, from: legacyData) {
            return CloudPayload(
                settings: VersionedValue(version: 1, value: legacySettings),
                dayEntries: [],
                netWageConfigs: [],
                holidayDays: [],
                userDefaults: nil
            )
        }

        return nil
    }

    private static func convertLegacyV3ToV4(_ payload: LegacyCloudPayloadV3) -> CloudPayload {
        CloudPayload(
            settings: VersionedValue(version: 1, value: payload.settings),
            dayEntries: deduplicatedAndSortedRecords((payload.dayEntries ?? []).map {
                VersionedRecord(key: dayEntryKey(for: $0.date), version: 1, value: $0)
            }),
            netWageConfigs: deduplicatedAndSortedRecords((payload.netWageConfigs ?? []).map {
                VersionedRecord(key: netWageConfigKey(for: $0.monthStart), version: 1, value: $0)
            }),
            holidayDays: deduplicatedAndSortedRecords((payload.holidayDays ?? []).map {
                VersionedRecord(key: $0.key, version: 1, value: $0)
            }),
            userDefaults: payload.userDefaults.map { VersionedValue(version: 1, value: $0) }
        )
    }

    private static func convertLegacyV2ToV4(_ payload: LegacyCloudPayloadV2) -> CloudPayload {
        CloudPayload(
            settings: VersionedValue(version: 1, value: payload.settings),
            dayEntries: deduplicatedAndSortedRecords((payload.dayEntries ?? []).map {
                VersionedRecord(key: dayEntryKey(for: $0.date), version: 1, value: $0)
            }),
            netWageConfigs: [],
            holidayDays: [],
            userDefaults: nil
        )
    }

    private static func payloadFromLocalState(
        state: LocalSyncState,
        settingsSnapshot: SettingsCloudSnapshot,
        userDefaultsSnapshot: UserDefaultsCloudSnapshot,
        daySnapshotsByKey: [String: DayEntryCloudSnapshot],
        netConfigSnapshotsByKey: [String: NetWageMonthConfigCloudSnapshot],
        holidaySnapshotsByKey: [String: HolidayCalendarDayCloudSnapshot]
    ) -> CloudPayload {
        let dayRecords = deduplicatedAndSortedRecords(
            state.dayEntries.map { key, value in
                VersionedRecord(
                    key: key,
                    version: value.version,
                    value: value.isDeleted ? nil : daySnapshotsByKey[key]
                )
            }
        )

        let netConfigRecords = deduplicatedAndSortedRecords(
            state.netWageConfigs.map { key, value in
                VersionedRecord(
                    key: key,
                    version: value.version,
                    value: value.isDeleted ? nil : netConfigSnapshotsByKey[key]
                )
            }
        )

        let holidayRecords = deduplicatedAndSortedRecords(
            state.holidayDays.map { key, value in
                VersionedRecord(
                    key: key,
                    version: value.version,
                    value: value.isDeleted ? nil : holidaySnapshotsByKey[key]
                )
            }
        )

        return CloudPayload(
            settings: VersionedValue(
                version: state.settings?.version ?? max(1, state.clock),
                value: settingsSnapshot
            ),
            dayEntries: dayRecords,
            netWageConfigs: netConfigRecords,
            holidayDays: holidayRecords,
            userDefaults: state.userDefaults.map {
                VersionedValue(version: $0.version, value: userDefaultsSnapshot)
            }
        )
    }

    private static func merge(localPayload: CloudPayload, cloudPayload: CloudPayload?) -> CloudPayload {
        guard let cloudPayload else { return localPayload }

        let mergedSettings: VersionedValue<SettingsCloudSnapshot>
        if shouldPreferRecord(
            incomingVersion: localPayload.settings.version,
            incomingValue: localPayload.settings.value,
            existingVersion: cloudPayload.settings.version,
            existingValue: cloudPayload.settings.value
        ) {
            mergedSettings = localPayload.settings
        } else {
            mergedSettings = cloudPayload.settings
        }

        let mergedUserDefaults: VersionedValue<UserDefaultsCloudSnapshot>?
        switch (localPayload.userDefaults, cloudPayload.userDefaults) {
        case let (local?, cloud?):
            mergedUserDefaults = shouldPreferRecord(
                incomingVersion: local.version,
                incomingValue: local.value,
                existingVersion: cloud.version,
                existingValue: cloud.value
            ) ? local : cloud
        case let (local?, nil):
            mergedUserDefaults = local
        case let (nil, cloud?):
            mergedUserDefaults = cloud
        case (nil, nil):
            mergedUserDefaults = nil
        }

        return CloudPayload(
            settings: mergedSettings,
            dayEntries: mergeRecords(localPayload.dayEntries, cloudPayload.dayEntries),
            netWageConfigs: mergeRecords(localPayload.netWageConfigs, cloudPayload.netWageConfigs),
            holidayDays: mergeRecords(localPayload.holidayDays, cloudPayload.holidayDays),
            userDefaults: mergedUserDefaults
        )
    }

    private static func mergeRecords<Value: Codable & Equatable>(
        _ localRecords: [VersionedRecord<Value>],
        _ cloudRecords: [VersionedRecord<Value>]
    ) -> [VersionedRecord<Value>] {
        var merged = latestRecordsByKey(cloudRecords)

        for localRecord in localRecords {
            if let existing = merged[localRecord.key] {
                if shouldPreferRecord(
                    incomingVersion: localRecord.version,
                    incomingValue: localRecord.value,
                    existingVersion: existing.version,
                    existingValue: existing.value
                ) {
                    merged[localRecord.key] = localRecord
                }
            } else {
                merged[localRecord.key] = localRecord
            }
        }

        return merged.values.sorted(by: { $0.key < $1.key })
    }

    private static func applyCloudDayRecord(
        _ cloudRecord: VersionedRecord<DayEntryCloudSnapshot>,
        localVersion: Int64,
        localSnapshot: DayEntryCloudSnapshot?,
        localObject: DayEntry?,
        modelContext: ModelContext,
        stateUpdater: (_ version: Int64, _ isDeleted: Bool, _ snapshot: DayEntryCloudSnapshot?) -> Void
    ) {
        guard shouldApplyIncomingRecord(
            incomingVersion: cloudRecord.version,
            incomingValue: cloudRecord.value,
            localVersion: localVersion,
            localValue: localSnapshot
        ) else { return }

        if let snapshot = cloudRecord.value {
            if let localObject {
                apply(snapshot, to: localObject)
            } else {
                modelContext.insert(snapshot.makeDayEntry())
            }
            stateUpdater(cloudRecord.version, false, snapshot)
        } else {
            if let localObject {
                modelContext.delete(localObject)
            }
            stateUpdater(cloudRecord.version, true, nil)
        }
    }

    private static func applyCloudNetWageRecord(
        _ cloudRecord: VersionedRecord<NetWageMonthConfigCloudSnapshot>,
        localVersion: Int64,
        localSnapshot: NetWageMonthConfigCloudSnapshot?,
        localObject: NetWageMonthConfig?,
        modelContext: ModelContext,
        stateUpdater: (_ version: Int64, _ isDeleted: Bool, _ snapshot: NetWageMonthConfigCloudSnapshot?) -> Void
    ) {
        guard shouldApplyIncomingRecord(
            incomingVersion: cloudRecord.version,
            incomingValue: cloudRecord.value,
            localVersion: localVersion,
            localValue: localSnapshot
        ) else { return }

        if let snapshot = cloudRecord.value {
            if let localObject {
                apply(snapshot, to: localObject)
            } else {
                modelContext.insert(snapshot.makeNetWageMonthConfig())
            }
            stateUpdater(cloudRecord.version, false, snapshot)
        } else {
            if let localObject {
                modelContext.delete(localObject)
            }
            stateUpdater(cloudRecord.version, true, nil)
        }
    }

    private static func applyCloudHolidayRecord(
        _ cloudRecord: VersionedRecord<HolidayCalendarDayCloudSnapshot>,
        localVersion: Int64,
        localSnapshot: HolidayCalendarDayCloudSnapshot?,
        localObject: HolidayCalendarDay?,
        modelContext: ModelContext,
        stateUpdater: (_ version: Int64, _ isDeleted: Bool, _ snapshot: HolidayCalendarDayCloudSnapshot?) -> Void
    ) {
        guard shouldApplyIncomingRecord(
            incomingVersion: cloudRecord.version,
            incomingValue: cloudRecord.value,
            localVersion: localVersion,
            localValue: localSnapshot
        ) else { return }

        if let snapshot = cloudRecord.value {
            if let localObject {
                apply(snapshot, to: localObject)
            } else {
                modelContext.insert(snapshot.makeHolidayCalendarDay())
            }
            stateUpdater(cloudRecord.version, false, snapshot)
        } else {
            if let localObject {
                modelContext.delete(localObject)
            }
            stateUpdater(cloudRecord.version, true, nil)
        }
    }

    @discardableResult
    private static func captureLocalDayEntryChanges(
        into state: inout LocalSyncState,
        entries: [DayEntry]
    ) -> [String: DayEntryCloudSnapshot] {
        let snapshotsByKey = Dictionary(
            entries.map { entry in
                let snapshot = DayEntryCloudSnapshot(from: entry)
                return (dayEntryKey(for: snapshot.date), snapshot)
            },
            uniquingKeysWith: { _, newer in newer }
        )

        for (key, snapshot) in snapshotsByKey {
            let snapshotFingerprint = fingerprint(snapshot)
            if let existing = state.dayEntries[key] {
                if existing.isDeleted || existing.fingerprint != snapshotFingerprint {
                    state.dayEntries[key] = LocalEntityState(
                        version: nextClock(&state),
                        isDeleted: false,
                        fingerprint: snapshotFingerprint
                    )
                }
            } else {
                state.dayEntries[key] = LocalEntityState(
                    version: nextClock(&state),
                    isDeleted: false,
                    fingerprint: snapshotFingerprint
                )
            }
        }

        let knownKeys = Array(state.dayEntries.keys)
        for key in knownKeys where snapshotsByKey[key] == nil {
            if let existing = state.dayEntries[key], !existing.isDeleted {
                state.dayEntries[key] = LocalEntityState(
                    version: nextClock(&state),
                    isDeleted: true,
                    fingerprint: nil
                )
            }
        }

        return snapshotsByKey
    }

    @discardableResult
    private static func captureLocalNetWageConfigChanges(
        into state: inout LocalSyncState,
        configs: [NetWageMonthConfig]
    ) -> [String: NetWageMonthConfigCloudSnapshot] {
        let snapshotsByKey = Dictionary(
            configs.map { config in
                let snapshot = NetWageMonthConfigCloudSnapshot(from: config)
                return (netWageConfigKey(for: snapshot.monthStart), snapshot)
            },
            uniquingKeysWith: { _, newer in newer }
        )

        for (key, snapshot) in snapshotsByKey {
            let snapshotFingerprint = fingerprint(snapshot)
            if let existing = state.netWageConfigs[key] {
                if existing.isDeleted || existing.fingerprint != snapshotFingerprint {
                    state.netWageConfigs[key] = LocalEntityState(
                        version: nextClock(&state),
                        isDeleted: false,
                        fingerprint: snapshotFingerprint
                    )
                }
            } else {
                state.netWageConfigs[key] = LocalEntityState(
                    version: nextClock(&state),
                    isDeleted: false,
                    fingerprint: snapshotFingerprint
                )
            }
        }

        let knownKeys = Array(state.netWageConfigs.keys)
        for key in knownKeys where snapshotsByKey[key] == nil {
            if let existing = state.netWageConfigs[key], !existing.isDeleted {
                state.netWageConfigs[key] = LocalEntityState(
                    version: nextClock(&state),
                    isDeleted: true,
                    fingerprint: nil
                )
            }
        }

        return snapshotsByKey
    }

    @discardableResult
    private static func captureLocalHolidayChanges(
        into state: inout LocalSyncState,
        holidays: [HolidayCalendarDay]
    ) -> [String: HolidayCalendarDayCloudSnapshot] {
        let snapshotsByKey = Dictionary(
            holidays.map { holiday in
                let snapshot = HolidayCalendarDayCloudSnapshot(from: holiday)
                return (snapshot.key, snapshot)
            },
            uniquingKeysWith: { _, newer in newer }
        )

        for (key, snapshot) in snapshotsByKey {
            let snapshotFingerprint = fingerprint(snapshot)
            if let existing = state.holidayDays[key] {
                if existing.isDeleted || existing.fingerprint != snapshotFingerprint {
                    state.holidayDays[key] = LocalEntityState(
                        version: nextClock(&state),
                        isDeleted: false,
                        fingerprint: snapshotFingerprint
                    )
                }
            } else {
                state.holidayDays[key] = LocalEntityState(
                    version: nextClock(&state),
                    isDeleted: false,
                    fingerprint: snapshotFingerprint
                )
            }
        }

        let knownKeys = Array(state.holidayDays.keys)
        for key in knownKeys where snapshotsByKey[key] == nil {
            if let existing = state.holidayDays[key], !existing.isDeleted {
                state.holidayDays[key] = LocalEntityState(
                    version: nextClock(&state),
                    isDeleted: true,
                    fingerprint: nil
                )
            }
        }

        return snapshotsByKey
    }

    private static func captureLocalSettingsChange(
        into state: inout LocalSyncState,
        settingsSnapshot: SettingsCloudSnapshot
    ) {
        let snapshotFingerprint = fingerprint(settingsSnapshot)
        if let existing = state.settings {
            if existing.fingerprint != snapshotFingerprint {
                state.settings = LocalValueState(
                    version: nextClock(&state),
                    fingerprint: snapshotFingerprint
                )
            }
        } else {
            state.settings = LocalValueState(
                version: nextClock(&state),
                fingerprint: snapshotFingerprint
            )
        }
    }

    private static func captureLocalUserDefaultsChange(
        into state: inout LocalSyncState,
        userDefaultsSnapshot: UserDefaultsCloudSnapshot
    ) {
        let snapshotFingerprint = fingerprint(userDefaultsSnapshot)
        if let existing = state.userDefaults {
            if existing.fingerprint != snapshotFingerprint {
                state.userDefaults = LocalValueState(
                    version: nextClock(&state),
                    fingerprint: snapshotFingerprint
                )
            }
        } else {
            state.userDefaults = LocalValueState(
                version: nextClock(&state),
                fingerprint: snapshotFingerprint
            )
        }
    }

    private static func latestRecordsByKey<Value: Codable & Equatable>(
        _ records: [VersionedRecord<Value>]
    ) -> [String: VersionedRecord<Value>] {
        var map: [String: VersionedRecord<Value>] = [:]

        for record in records {
            if let existing = map[record.key] {
                if record.version > existing.version {
                    map[record.key] = record
                } else if record.version == existing.version,
                          existing.value == nil,
                          record.value != nil {
                    map[record.key] = record
                }
            } else {
                map[record.key] = record
            }
        }

        return map
    }

    private static func deduplicatedAndSortedRecords<Value: Codable & Equatable>(
        _ records: [VersionedRecord<Value>]
    ) -> [VersionedRecord<Value>] {
        latestRecordsByKey(records)
            .values
            .sorted(by: { $0.key < $1.key })
    }

    private static func shouldApplyIncomingRecord<Value: Encodable>(
        incomingVersion: Int64,
        incomingValue: Value?,
        localVersion: Int64,
        localValue: Value?
    ) -> Bool {
        shouldPreferRecord(
            incomingVersion: incomingVersion,
            incomingValue: incomingValue,
            existingVersion: localVersion,
            existingValue: localValue
        )
    }

    private static func shouldPreferRecord<Value: Encodable>(
        incomingVersion: Int64,
        incomingValue: Value?,
        existingVersion: Int64,
        existingValue: Value?
    ) -> Bool {
        if incomingVersion > existingVersion { return true }
        if incomingVersion < existingVersion { return false }
        return conflictRank(for: incomingValue) > conflictRank(for: existingValue)
    }

    private static func conflictRank<Value: Encodable>(for value: Value?) -> String {
        guard let value else { return "2" }
        return "1:\(fingerprint(value))"
    }

    private static func loadLocalSyncState() -> LocalSyncState {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        guard let data = defaults.data(forKey: localSyncStateKey),
              let state = try? decoder.decode(LocalSyncState.self, from: data) else {
            return .empty
        }

        return state
    }

    private static func saveLocalSyncState(_ state: LocalSyncState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: localSyncStateKey)
    }

    private static func nextClock(_ state: inout LocalSyncState) -> Int64 {
        state.clock += 1
        return state.clock
    }

    private static func maxVersion(in payload: CloudPayload) -> Int64 {
        var value = payload.settings.version

        if let userDefaultsVersion = payload.userDefaults?.version {
            value = max(value, userDefaultsVersion)
        }

        for record in payload.dayEntries {
            value = max(value, record.version)
        }

        for record in payload.netWageConfigs {
            value = max(value, record.version)
        }

        for record in payload.holidayDays {
            value = max(value, record.version)
        }

        return value
    }

    private static func dayEntryKey(for date: Date) -> String {
        String(Int(date.startOfDayLocal().timeIntervalSinceReferenceDate))
    }

    private static func netWageConfigKey(for monthStart: Date) -> String {
        String(Int(monthStart.startOfMonthLocal().timeIntervalSinceReferenceDate))
    }

    private static func fingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return data.base64EncodedString()
    }

    private static func apply(_ snapshot: DayEntryCloudSnapshot, to entry: DayEntry) {
        entry.date = snapshot.date.startOfDayLocal()
        entry.type = snapshot.type
        entry.notes = snapshot.notes
        entry.manualWorkedSeconds = snapshot.manualWorkedSeconds
        entry.creditedOverrideSeconds = snapshot.creditedOverrideSeconds
        entry.segments.removeAll()
        for segment in snapshot.segments {
            entry.segments.append(segment.makeTimeSegment())
        }
    }

    private static func apply(_ snapshot: NetWageMonthConfigCloudSnapshot, to config: NetWageMonthConfig) {
        config.monthStart = snapshot.monthStart.startOfMonthLocal()
        config.wageTaxPercent = snapshot.wageTaxPercent
        config.pensionPercent = snapshot.pensionPercent
        config.monthlyAllowanceEuro = snapshot.monthlyAllowanceEuro
        config.bonusesCSV = snapshot.bonusesCSV
    }

    private static func apply(_ snapshot: HolidayCalendarDayCloudSnapshot, to day: HolidayCalendarDay) {
        day.date = snapshot.date.startOfDayLocal()
        day.localName = snapshot.localName
        day.countryCode = snapshot.countryCode
        day.subdivisionCode = snapshot.subdivisionCode
        day.sourceYear = snapshot.sourceYear
        day.key = snapshot.key
    }
}

private struct CloudPayload: Codable {
    let settings: VersionedValue<SettingsCloudSnapshot>
    let dayEntries: [VersionedRecord<DayEntryCloudSnapshot>]
    let netWageConfigs: [VersionedRecord<NetWageMonthConfigCloudSnapshot>]
    let holidayDays: [VersionedRecord<HolidayCalendarDayCloudSnapshot>]
    let userDefaults: VersionedValue<UserDefaultsCloudSnapshot>?
}

private struct VersionedValue<Value: Codable>: Codable {
    let version: Int64
    let value: Value
}

private struct VersionedRecord<Value: Codable & Equatable>: Codable, Equatable {
    let key: String
    let version: Int64
    let value: Value?
}

private struct LocalSyncState: Codable {
    var clock: Int64
    var settings: LocalValueState?
    var userDefaults: LocalValueState?
    var dayEntries: [String: LocalEntityState]
    var netWageConfigs: [String: LocalEntityState]
    var holidayDays: [String: LocalEntityState]

    static var empty: LocalSyncState {
        LocalSyncState(
            clock: 0,
            settings: nil,
            userDefaults: nil,
            dayEntries: [:],
            netWageConfigs: [:],
            holidayDays: [:]
        )
    }
}

private struct LocalValueState: Codable {
    var version: Int64
    var fingerprint: String
}

private struct LocalEntityState: Codable {
    var version: Int64
    var isDeleted: Bool
    var fingerprint: String?
}

private struct LegacyCloudPayloadV3: Codable {
    let settings: SettingsCloudSnapshot
    let dayEntries: [DayEntryCloudSnapshot]?
    let netWageConfigs: [NetWageMonthConfigCloudSnapshot]?
    let holidayDays: [HolidayCalendarDayCloudSnapshot]?
    let userDefaults: UserDefaultsCloudSnapshot?
}

private struct LegacyCloudPayloadV2: Codable {
    let settings: SettingsCloudSnapshot
    let dayEntries: [DayEntryCloudSnapshot]?
}

private struct UserDefaultsCloudSnapshot: Codable, Equatable {
    let shiftShortcut1: String
    let shiftShortcut2: String
    let shiftShortcut3: String
    let shiftShortcutName1: String?
    let shiftShortcutName2: String?
    let shiftShortcutName3: String?

    static let shortcut1Key = "dayEditorShiftShortcut1"
    static let shortcut2Key = "dayEditorShiftShortcut2"
    static let shortcut3Key = "dayEditorShiftShortcut3"
    static let shortcutName1Key = "dayEditorShiftShortcutName1"
    static let shortcutName2Key = "dayEditorShiftShortcutName2"
    static let shortcutName3Key = "dayEditorShiftShortcutName3"

    static func fromLocalStore() -> UserDefaultsCloudSnapshot {
        let defaults = UserDefaults.standard
        return UserDefaultsCloudSnapshot(
            shiftShortcut1: defaults.string(forKey: shortcut1Key) ?? "",
            shiftShortcut2: defaults.string(forKey: shortcut2Key) ?? "",
            shiftShortcut3: defaults.string(forKey: shortcut3Key) ?? "",
            shiftShortcutName1: defaults.string(forKey: shortcutName1Key),
            shiftShortcutName2: defaults.string(forKey: shortcutName2Key),
            shiftShortcutName3: defaults.string(forKey: shortcutName3Key)
        )
    }

    func applyToLocalStore() {
        let defaults = UserDefaults.standard
        defaults.set(shiftShortcut1, forKey: Self.shortcut1Key)
        defaults.set(shiftShortcut2, forKey: Self.shortcut2Key)
        defaults.set(shiftShortcut3, forKey: Self.shortcut3Key)
        defaults.set(shiftShortcutName1 ?? "", forKey: Self.shortcutName1Key)
        defaults.set(shiftShortcutName2 ?? "", forKey: Self.shortcutName2Key)
        defaults.set(shiftShortcutName3 ?? "", forKey: Self.shortcutName3Key)
    }
}

private struct SettingsCloudSnapshot: Codable {
    let hasCompletedOnboarding: Bool
    let payMode: PayMode
    let hourlyRateCents: Int?
    let monthlySalaryCents: Int?
    let weeklyTargetSeconds: Int?
    let weekStart: WeekStart
    let vacationLookbackCount: Int
    let vacationCreditingMode: VacationCreditingMode?
    let vacationFixedSeconds: Int?
    let countMissingAsZero: Bool
    let strictHistoryRequired: Bool
    let holidayCreditingMode: HolidayCreditingMode
    let scheduledWorkdaysCount: Int
    let themeAccent: ThemeAccent
    let calendarCellDisplayMode: CalendarCellDisplayMode?
    let calendarHoursBreakMode: CalendarHoursBreakMode?
    let showCalendarWeekNumbers: Bool?
    let showCalendarWeekHours: Bool?
    let showCalendarWeekPay: Bool?
    let timelineMinMinute: Int?
    let timelineMaxMinute: Int?
    let holidayCountryCode: String?
    let holidaySubdivisionCode: String?
    let markPaidHolidays: Bool?
    let paidHolidayWeekdayMask: Int?
    let netWageTaxPercent: Double?
    let netPensionPercent: Double?
    let netMonthlyAllowanceEuro: Double?
    let netBonusesCSV: String?

    init(from settings: Settings) {
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        payMode = settings.payMode
        hourlyRateCents = settings.hourlyRateCents
        monthlySalaryCents = settings.monthlySalaryCents
        weeklyTargetSeconds = settings.weeklyTargetSeconds
        weekStart = settings.weekStart
        vacationLookbackCount = settings.vacationLookbackCount
        vacationCreditingMode = settings.vacationCreditingMode
        vacationFixedSeconds = settings.vacationFixedSeconds
        countMissingAsZero = settings.countMissingAsZero
        strictHistoryRequired = settings.strictHistoryRequired
        holidayCreditingMode = settings.holidayCreditingMode
        scheduledWorkdaysCount = settings.scheduledWorkdaysCount
        themeAccent = settings.themeAccent
        calendarCellDisplayMode = settings.calendarCellDisplayMode
        calendarHoursBreakMode = settings.calendarHoursBreakMode
        showCalendarWeekNumbers = settings.showCalendarWeekNumbers
        showCalendarWeekHours = settings.showCalendarWeekHours
        showCalendarWeekPay = settings.showCalendarWeekPay
        timelineMinMinute = settings.timelineMinMinute
        timelineMaxMinute = settings.timelineMaxMinute
        holidayCountryCode = settings.holidayCountryCode
        holidaySubdivisionCode = settings.holidaySubdivisionCode
        markPaidHolidays = settings.markPaidHolidays
        paidHolidayWeekdayMask = settings.paidHolidayWeekdayMask
        netWageTaxPercent = settings.netWageTaxPercent
        netPensionPercent = settings.netPensionPercent
        netMonthlyAllowanceEuro = settings.netMonthlyAllowanceEuro
        netBonusesCSV = settings.netBonusesCSV
    }

    func makeSettings() -> Settings {
        Settings(
            hasCompletedOnboarding: hasCompletedOnboarding,
            payMode: payMode,
            hourlyRateCents: hourlyRateCents,
            monthlySalaryCents: monthlySalaryCents,
            weeklyTargetSeconds: weeklyTargetSeconds,
            weekStart: weekStart,
            vacationLookbackCount: vacationLookbackCount,
            vacationCreditingMode: vacationCreditingMode ?? .lookback13Weeks,
            vacationFixedSeconds: vacationFixedSeconds,
            countMissingAsZero: countMissingAsZero,
            strictHistoryRequired: strictHistoryRequired,
            holidayCreditingMode: holidayCreditingMode,
            scheduledWorkdaysCount: scheduledWorkdaysCount,
            themeAccent: themeAccent,
            calendarCellDisplayMode: calendarCellDisplayMode,
            calendarHoursBreakMode: calendarHoursBreakMode ?? .withoutBreak,
            showCalendarWeekNumbers: showCalendarWeekNumbers ?? false,
            showCalendarWeekHours: showCalendarWeekHours ?? false,
            showCalendarWeekPay: showCalendarWeekPay ?? false,
            timelineMinMinute: timelineMinMinute,
            timelineMaxMinute: timelineMaxMinute,
            holidayCountryCode: holidayCountryCode,
            holidaySubdivisionCode: holidaySubdivisionCode,
            markPaidHolidays: markPaidHolidays ?? false,
            paidHolidayWeekdayMask: paidHolidayWeekdayMask,
            netWageTaxPercent: netWageTaxPercent,
            netPensionPercent: netPensionPercent,
            netMonthlyAllowanceEuro: netMonthlyAllowanceEuro,
            netBonusesCSV: netBonusesCSV
        )
    }

    func apply(to settings: Settings) {
        settings.hasCompletedOnboarding = hasCompletedOnboarding
        settings.payMode = payMode
        settings.hourlyRateCents = hourlyRateCents
        settings.monthlySalaryCents = monthlySalaryCents
        settings.weeklyTargetSeconds = weeklyTargetSeconds
        settings.weekStart = weekStart
        settings.vacationLookbackCount = vacationLookbackCount
        settings.vacationCreditingMode = vacationCreditingMode
        settings.vacationFixedSeconds = vacationFixedSeconds.map { max(0, $0) }
        settings.countMissingAsZero = countMissingAsZero
        settings.strictHistoryRequired = strictHistoryRequired
        settings.holidayCreditingMode = holidayCreditingMode
        settings.scheduledWorkdaysCount = min(max(scheduledWorkdaysCount, 1), 7)
        settings.themeAccent = themeAccent
        settings.calendarCellDisplayMode = calendarCellDisplayMode
        settings.calendarHoursBreakMode = calendarHoursBreakMode
        settings.showCalendarWeekNumbers = showCalendarWeekNumbers
        settings.showCalendarWeekHours = showCalendarWeekHours
        settings.showCalendarWeekPay = showCalendarWeekPay
        settings.timelineMinMinute = timelineMinMinute
        settings.timelineMaxMinute = timelineMaxMinute
        settings.holidayCountryCode = holidayCountryCode
        settings.holidaySubdivisionCode = holidaySubdivisionCode
        settings.markPaidHolidays = markPaidHolidays
        settings.paidHolidayWeekdayMask = paidHolidayWeekdayMask
        settings.netWageTaxPercent = netWageTaxPercent
        settings.netPensionPercent = netPensionPercent
        settings.netMonthlyAllowanceEuro = netMonthlyAllowanceEuro
        settings.netBonusesCSV = netBonusesCSV
    }
}

private struct DayEntryCloudSnapshot: Codable, Equatable {
    let date: Date
    let type: DayType
    let notes: String
    let manualWorkedSeconds: Int?
    let creditedOverrideSeconds: Int?
    let segments: [TimeSegmentCloudSnapshot]

    init(from entry: DayEntry) {
        date = entry.date.startOfDayLocal()
        type = entry.type
        notes = entry.notes
        manualWorkedSeconds = entry.manualWorkedSeconds
        creditedOverrideSeconds = entry.creditedOverrideSeconds
        segments = entry.segments
            .map { TimeSegmentCloudSnapshot(from: $0) }
            .sorted(by: { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.end != rhs.end { return lhs.end < rhs.end }
                return lhs.breakSeconds < rhs.breakSeconds
            })
    }

    func makeDayEntry() -> DayEntry {
        DayEntry(
            date: date,
            type: type,
            notes: notes,
            segments: segments.map { $0.makeTimeSegment() },
            manualWorkedSeconds: manualWorkedSeconds,
            creditedOverrideSeconds: creditedOverrideSeconds
        )
    }
}

private struct TimeSegmentCloudSnapshot: Codable, Equatable {
    let start: Date
    let end: Date
    let breakSeconds: Int

    init(from segment: TimeSegment) {
        start = segment.start
        end = segment.end
        breakSeconds = segment.breakSeconds
    }

    func makeTimeSegment() -> TimeSegment {
        TimeSegment(start: start, end: end, breakSeconds: breakSeconds)
    }
}

private struct NetWageMonthConfigCloudSnapshot: Codable, Equatable {
    let monthStart: Date
    let wageTaxPercent: Double?
    let pensionPercent: Double?
    let monthlyAllowanceEuro: Double?
    let bonusesCSV: String

    init(from config: NetWageMonthConfig) {
        monthStart = config.monthStart.startOfMonthLocal()
        wageTaxPercent = config.wageTaxPercent
        pensionPercent = config.pensionPercent
        monthlyAllowanceEuro = config.monthlyAllowanceEuro
        bonusesCSV = config.bonusesCSV
    }

    func makeNetWageMonthConfig() -> NetWageMonthConfig {
        NetWageMonthConfig(
            monthStart: monthStart,
            wageTaxPercent: wageTaxPercent,
            pensionPercent: pensionPercent,
            monthlyAllowanceEuro: monthlyAllowanceEuro,
            bonusesCSV: bonusesCSV
        )
    }
}

private struct HolidayCalendarDayCloudSnapshot: Codable, Equatable {
    let key: String
    let date: Date
    let localName: String
    let countryCode: String
    let subdivisionCode: String?
    let sourceYear: Int

    init(from day: HolidayCalendarDay) {
        key = day.key
        date = day.date.startOfDayLocal()
        localName = day.localName
        countryCode = day.countryCode
        subdivisionCode = day.subdivisionCode
        sourceYear = day.sourceYear
    }

    func makeHolidayCalendarDay() -> HolidayCalendarDay {
        HolidayCalendarDay(
            date: date,
            localName: localName,
            countryCode: countryCode,
            subdivisionCode: subdivisionCode,
            sourceYear: sourceYear
        )
    }
}

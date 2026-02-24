import Foundation
import SwiftData

struct HolidayImportService {
    enum HolidayImportError: LocalizedError {
        case invalidCountryCode
        case requestFailed(statusCode: Int?)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidCountryCode:
                return "Ungueltiger Laendercode (z. B. DE)."
            case .requestFailed(let statusCode):
                if let statusCode {
                    return "Feiertags-API antwortete mit HTTP \(statusCode)."
                }
                return "Feiertags-API ist aktuell nicht erreichbar."
            case .decodingFailed:
                return "Antwort der Feiertags-API konnte nicht gelesen werden."
            }
        }
    }

    private struct HolidayAPIItem: Decodable {
        let date: String
        let localName: String
        let global: Bool?
        let subdivisionCodes: [String]?

        private enum CodingKeys: String, CodingKey {
            case date
            case localName
            case name
            case global
            case counties
            case countyCodes
            case subdivisionCodes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            let decodedLocalName = try container.decodeIfPresent(String.self, forKey: .localName)
            let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
            localName = decodedLocalName ?? decodedName ?? "Holiday"
            global = try container.decodeIfPresent(Bool.self, forKey: .global)

            let fromCounties = try container.decodeIfPresent([String].self, forKey: .counties)
            let fromCountyCodes = try container.decodeIfPresent([String].self, forKey: .countyCodes)
            let fromSubdivisionCodes = try container.decodeIfPresent([String].self, forKey: .subdivisionCodes)
            subdivisionCodes = fromSubdivisionCodes ?? fromCountyCodes ?? fromCounties
        }
    }

    private static let plainDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoDateFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @MainActor
    func importHolidays(
        year: Int,
        countryCode: String?,
        subdivisionCode: String?,
        modelContext: ModelContext
    ) async throws -> Int {
        guard let normalizedCountry = normalize(countryCode), normalizedCountry.count == 2 else {
            throw HolidayImportError.invalidCountryCode
        }
        let normalizedSubdivision = normalize(subdivisionCode)
        let items = try await fetch(year: year, countryCode: normalizedCountry)
        let filtered = filter(items: items, countryCode: normalizedCountry, subdivisionCode: normalizedSubdivision)

        let existing = try modelContext.fetch(FetchDescriptor<HolidayCalendarDay>())
        for holiday in existing where holiday.sourceYear == year && holiday.countryCode == normalizedCountry {
            let oldSubdivision = normalize(holiday.subdivisionCode)
            if oldSubdivision == normalizedSubdivision {
                modelContext.delete(holiday)
            }
        }

        var insertedCount = 0
        var seenKeys = Set<String>()
        for item in filtered {
            guard let date = parse(dateString: item.date) else { continue }
            let key = HolidayCalendarDay.makeKey(
                date: date,
                countryCode: normalizedCountry,
                subdivisionCode: normalizedSubdivision
            )
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)
            modelContext.insert(
                HolidayCalendarDay(
                    date: date,
                    localName: item.localName,
                    countryCode: normalizedCountry,
                    subdivisionCode: normalizedSubdivision,
                    sourceYear: year
                )
            )
            insertedCount += 1
        }

        modelContext.persistIfPossible()
        return insertedCount
    }

    private func fetch(year: Int, countryCode: String) async throws -> [HolidayAPIItem] {
        let urls = [
            URL(string: "https://date.nager.at/api/v3/publicholidays/\(year)/\(countryCode)"),
            URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(countryCode)")
        ].compactMap { $0 }

        guard !urls.isEmpty else {
            throw HolidayImportError.requestFailed(statusCode: nil)
        }

        var lastError: Error?

        for (index, url) in urls.enumerated() {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw HolidayImportError.requestFailed(statusCode: nil)
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 404, index < urls.count - 1 {
                        continue
                    }
                    throw HolidayImportError.requestFailed(statusCode: httpResponse.statusCode)
                }

                do {
                    return try JSONDecoder().decode([HolidayAPIItem].self, from: data)
                } catch {
                    throw HolidayImportError.decodingFailed
                }
            } catch {
                lastError = error
                if index < urls.count - 1 {
                    continue
                }
            }
        }

        if let holidayError = lastError as? HolidayImportError {
            throw holidayError
        }
        throw HolidayImportError.requestFailed(statusCode: nil)
    }

    private func filter(items: [HolidayAPIItem], countryCode: String, subdivisionCode: String?) -> [HolidayAPIItem] {
        guard let subdivisionCode else {
            return items.filter { item in
                if let global = item.global {
                    return global
                }
                return item.subdivisionCodes == nil || item.subdivisionCodes?.isEmpty == true
            }
        }
        let normalizedTarget = normalizedSubdivisionCode(subdivisionCode, countryCode: countryCode)
        return items.filter { item in
            if item.global == true {
                return true
            }
            guard let subdivisionCodes = item.subdivisionCodes, !subdivisionCodes.isEmpty else {
                return item.global == nil
            }
            return subdivisionCodes.contains { code in
                normalizedSubdivisionCode(code, countryCode: countryCode) == normalizedTarget
            }
        }
    }

    private func parse(dateString: String) -> Date? {
        if let date = Self.plainDateFormatter.date(from: dateString) {
            return date.startOfDayLocal()
        }
        if let date = Self.isoDateFormatterFractional.date(from: dateString) ?? Self.isoDateFormatter.date(from: dateString) {
            return date.startOfDayLocal()
        }
        if dateString.count >= 10 {
            let prefix = String(dateString.prefix(10))
            if let date = Self.plainDateFormatter.date(from: prefix) {
                return date.startOfDayLocal()
            }
        }
        return nil
    }

    private func normalizedSubdivisionCode(_ value: String, countryCode: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedCountryPrefix = "\(countryCode.uppercased())-"
        if normalized.hasPrefix(normalizedCountryPrefix) {
            return String(normalized.dropFirst(normalizedCountryPrefix.count))
        }
        return normalized
    }

    private func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

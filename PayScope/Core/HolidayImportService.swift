import Foundation
import SwiftData

struct HolidayImportService {
    enum HolidayImportError: LocalizedError {
        case invalidCountryCode
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidCountryCode:
                return "Country code is missing."
            case .requestFailed:
                return "Holiday API request failed."
            }
        }
    }

    private struct HolidayAPIItem: Decodable {
        let date: String
        let localName: String
        let counties: [String]?
    }

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
        guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(countryCode)") else {
            throw HolidayImportError.requestFailed
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw HolidayImportError.requestFailed
        }
        return try JSONDecoder().decode([HolidayAPIItem].self, from: data)
    }

    private func filter(items: [HolidayAPIItem], countryCode: String, subdivisionCode: String?) -> [HolidayAPIItem] {
        guard let subdivisionCode else {
            return items.filter { $0.counties == nil || $0.counties?.isEmpty == true }
        }
        let normalizedPrefixed = "\(countryCode)-\(subdivisionCode)".uppercased()
        return items.filter { item in
            guard let counties = item.counties, !counties.isEmpty else { return true }
            return counties.contains { county in
                let normalizedCounty = county.uppercased()
                return normalizedCounty == subdivisionCode || normalizedCounty == normalizedPrefixed
            }
        }
    }

    private func parse(dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)?.startOfDayLocal()
    }

    private func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

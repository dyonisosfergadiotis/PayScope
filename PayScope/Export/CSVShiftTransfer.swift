import Foundation

struct ShiftCSVImportRowDraft: Identifiable, Equatable {
    let id = UUID()
    var dayType: DayType
    var categoryIcon: String
    var date: Date
    var startMinute: Int
    var endMinute: Int
    var endDayOffset: Int
    var breakMinutes: Int
    var isEditing: Bool

    init(
        dayType: DayType,
        categoryIcon: String,
        date: Date,
        startMinute: Int,
        endMinute: Int,
        endDayOffset: Int? = nil,
        breakMinutes: Int,
        isEditing: Bool = false
    ) {
        self.dayType = dayType
        self.categoryIcon = categoryIcon
        self.date = date.startOfDayLocal()
        self.startMinute = max(0, min(23 * 60 + 59, startMinute))
        self.endMinute = max(0, min(23 * 60 + 59, endMinute))
        self.endDayOffset = max(0, min(1, endDayOffset ?? (self.endMinute <= self.startMinute ? 1 : 0)))
        self.breakMinutes = max(0, breakMinutes)
        self.isEditing = isEditing
    }

    var endMinuteOffset: Int {
        if endDayOffset > 0 {
            return endMinute + (endDayOffset * ShiftTimeRange.minutesPerDay)
        }
        if endMinute <= startMinute {
            return endMinute + ShiftTimeRange.minutesPerDay
        }
        return endMinute
    }

    var effectiveEndDayOffset: Int {
        endMinuteOffset >= ShiftTimeRange.minutesPerDay ? 1 : 0
    }

    var hasValidTimeRange: Bool {
        ShiftTimeRange(startMinute: startMinute, endMinuteOffset: endMinuteOffset) != nil
    }
}

struct ShiftCSVImportParseResult {
    let rows: [ShiftCSVImportRowDraft]
    let skippedRows: Int
}

enum ShiftCSVTransfer {
    static let exportHeader = "categoryIcon,date,start,end,endDayOffset,breakMinutes,type,workedHours,workedPay,creditedHours,creditedPay,notes"

    static func exportColumns(for entry: DayEntry) -> (icon: String, date: String, start: String, end: String, endDayOffset: String, breakMinutes: String, type: String) {
        let icon = entry.type.icon
        let date = dayFormatter.string(from: entry.date)
        let type = entry.type.rawValue

        guard let shiftStart = entry.shiftStart, let shiftEnd = entry.shiftEnd, shiftEnd > shiftStart else {
            return (icon, date, "", "", "", "", type)
        }

        let start = timeFormatter.string(from: shiftStart)
        let end = timeFormatter.string(from: shiftEnd)
        let startDay = shiftStart.startOfDayLocal()
        let endDay = shiftEnd.startOfDayLocal()
        let offset = Calendar.current.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        let endDayOffset = String(max(0, min(1, offset)))
        let breakMinutes = String(max(0, (entry.breakSeconds ?? 0) / 60))
        return (icon, date, start, end, endDayOffset, breakMinutes, type)
    }

    static func parse(csv: String) -> ShiftCSVImportParseResult {
        let rawLines = csv
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        guard !rawLines.isEmpty else {
            return ShiftCSVImportParseResult(rows: [], skippedRows: 0)
        }

        let headerColumns = parseCSVLine(rawLines[0]).map(normalizeHeader)
        guard !headerColumns.isEmpty else {
            return ShiftCSVImportParseResult(rows: [], skippedRows: max(0, rawLines.count - 1))
        }

        var parsedRows: [ShiftCSVImportRowDraft] = []
        var skippedRows = 0

        for line in rawLines.dropFirst() {
            let values = parseCSVLine(line)
            guard !values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }

            guard let row = parseRow(values: values, headers: headerColumns) else {
                skippedRows += 1
                continue
            }
            parsedRows.append(row)
        }

        return ShiftCSVImportParseResult(rows: parsedRows, skippedRows: skippedRows)
    }

    private static func parseRow(values: [String], headers: [String]) -> ShiftCSVImportRowDraft? {
        func value(for aliases: [String]) -> String? {
            for alias in aliases {
                guard let idx = headers.firstIndex(of: alias), idx < values.count else { continue }
                let value = values[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        guard
            let dateText = value(for: ["date", "datum"]),
            let startText = value(for: ["start", "beginn"]),
            let endText = value(for: ["end", "ende"]),
            let date = parseDate(dateText),
            let startMinute = parseMinuteOfDay(startText),
            let endMinute = parseMinuteOfDay(endText)
        else {
            return nil
        }

        let explicitEndDayOffset = parseEndDayOffset(value(for: [
            "enddayoffset",
            "endday",
            "enddateoffset",
            "endoffset",
            "folgetag",
            "morgen"
        ]))
        let endTextDayOffset = parseEndDayOffset(endText)
        let endDayOffset = explicitEndDayOffset ?? endTextDayOffset ?? (endMinute <= startMinute ? 1 : 0)

        let typeText = value(for: ["type", "daytype", "kategorie", "category"])
        let iconText = value(for: ["categoryicon", "kategorieicon", "icon", "symbol", "category"])

        let dayType = parseDayType(typeText: typeText, iconText: iconText)
        let categoryIcon = iconText?.nilIfEmpty ?? dayType.icon

        let pauseText = value(for: ["breakminutes", "pause", "break", "pausenminuten", "pauseminuten"])
        let breakMinutes = max(0, parseBreakMinutes(pauseText) ?? 0)

        return ShiftCSVImportRowDraft(
            dayType: dayType,
            categoryIcon: categoryIcon,
            date: date,
            startMinute: startMinute,
            endMinute: endMinute,
            endDayOffset: endDayOffset,
            breakMinutes: breakMinutes,
            isEditing: false
        )
    }

    private static func parseDayType(typeText: String?, iconText: String?) -> DayType {
        if let rawType = typeText?.lowercased(), let dayType = DayType(rawValue: rawType) {
            return dayType
        }

        if let icon = iconText?.lowercased() {
            if let byIcon = DayType.allCases.first(where: { $0.icon.lowercased() == icon }) {
                return byIcon
            }

            switch icon {
            case "arbeit", "work": return .work
            case "urlaub", "vacation": return .vacation
            case "krank", "sick": return .sick
            case "feiertag", "holiday": return .holiday
            case "manuell", "manual": return .manual
            default: break
            }
        }

        return .work
    }

    private static func parseBreakMinutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let sanitized = value.replacingOccurrences(of: ",", with: ".")
        if let int = Int(sanitized) {
            return int
        }
        if let double = Double(sanitized) {
            return Int(double.rounded())
        }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = dayFormatter.date(from: value) {
            return date.startOfDayLocal()
        }
        if let date = germanDayFormatter.date(from: value) {
            return date.startOfDayLocal()
        }
        return nil
    }

    private static func parseMinuteOfDay(_ value: String) -> Int? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed
            .replacingOccurrences(of: "(+1)", with: "")
            .replacingOccurrences(of: "+1", with: "")
            .replacingOccurrences(of: "Morgen", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = [":", "."]
        for separator in separators {
            let parts = trimmed.split(separator: Character(separator), omittingEmptySubsequences: false)
            if parts.count == 2,
               let hours = Int(parts[0]),
               let minutes = Int(parts[1]),
               (0...23).contains(hours),
               (0...59).contains(minutes) {
                return (hours * 60) + minutes
            }
        }

        return nil
    }

    private static func parseEndDayOffset(_ value: String?) -> Int? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("+1") || normalized.contains("morgen") {
            return 1
        }
        switch normalized {
        case "1", "true", "yes", "ja", "y":
            return 1
        case "0", "false", "no", "nein", "n":
            return 0
        default:
            return Int(normalized).map { max(0, min(1, $0)) }
        }
    }

    private nonisolated static func normalizeHeader(_ header: String) -> String {
        header
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let nextIndex = line.index(after: index)
                if inQuotes, nextIndex < line.endIndex, line[nextIndex] == "\"" {
                    current.append("\"")
                    index = nextIndex
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        values.append(current)
        return values
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let germanDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = .current
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

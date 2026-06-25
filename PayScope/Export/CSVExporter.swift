import Foundation

struct CSVExporter {
    let service: CalculationService

    init(service: CalculationService = CalculationService()) {
        self.service = service
    }

    func csvForMonth(
        entries: [DayEntry],
        tips: [TipEntry] = [],
        month: Date,
        settings: Settings,
        options: MonthExportOptions = MonthExportOptions()
    ) -> String {
        guard
            let monthRange = Calendar.current.dateInterval(of: .month, for: month)
        else {
            return ""
        }

        let exportEntries = entries.filter(\.isRealTrackedDay)
        let filtered = exportEntries
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }
        let monthTips = tips
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }
        let tipSummaries = tipSummariesByLocalDay(from: monthTips)
        let tipAmountsByDay = Dictionary(
            uniqueKeysWithValues: tipSummaries.map { (localDayKey(for: $0.date), $0.amountCents) }
        )
        let entryDayKeys = Set(filtered.map { localDayKey(for: $0.date) })

        var lines: [String] = [csvHeader(options: options)]
        let entriesByDate = service.makeEntriesByDateLookup(from: exportEntries)
        for entry in filtered {
            let result = service.exportComputation(for: entry, entriesByDate: entriesByDate, settings: settings)
            let shiftColumns = ShiftCSVTransfer.exportColumns(for: entry)

            let workedSeconds: Int
            let workedPay: Int
            switch service.workedSeconds(for: entry, calculateBreaks: settings.effectiveCalculateBreaks) {
            case let .success(seconds):
                workedSeconds = seconds
                workedPay = service.payCents(for: seconds, settings: settings)
            case .failure:
                workedSeconds = 0
                workedPay = 0
            }

            let creditedSeconds: Int
            let creditedPay: Int
            switch result {
            case let .ok(seconds, cents), let .warning(seconds, cents, _):
                if entry.type == .vacation || entry.type == .sick || entry.type == .holiday {
                    creditedSeconds = seconds
                    creditedPay = cents
                } else {
                    creditedSeconds = 0
                    creditedPay = 0
                }
            case .error:
                creditedSeconds = 0
                creditedPay = 0
            }

            var fields = [
                shiftColumns.icon,
                shiftColumns.date
            ]
            if options.includeShiftTimes {
                fields.append(contentsOf: [
                    shiftColumns.start,
                    shiftColumns.end,
                    shiftColumns.endDayOffset
                ])
            }
            if options.includeBreaks {
                fields.append(shiftColumns.breakMinutes)
            }
            fields.append(contentsOf: [
                shiftColumns.type,
                String(format: "%.2f", Double(workedSeconds) / 3600)
            ])
            if options.includePay {
                fields.append(String(format: "%.2f", Double(workedPay) / 100))
            }
            fields.append(String(format: "%.2f", Double(creditedSeconds) / 3600))
            if options.includePay {
                fields.append(String(format: "%.2f", Double(creditedPay) / 100))
            }
            if options.includeTips {
                let tipAmountCents = tipAmountsByDay[localDayKey(for: entry.date)] ?? 0
                fields.append(tipAmountCents > 0 ? tipAmountText(cents: tipAmountCents) : "")
            }
            let row = fields.map(Self.csvField).joined(separator: ",")
            lines.append(row)
        }

        if options.includeTips {
            for summary in tipSummaries where !entryDayKeys.contains(localDayKey(for: summary.date)) {
                let row = tipFields(for: summary, options: options).map(Self.csvField).joined(separator: ",")
                lines.append(row)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func csvHeader(options: MonthExportOptions) -> String {
        var columns = [
            "categoryIcon",
            "date"
        ]
        if options.includeShiftTimes {
            columns.append(contentsOf: [
                "start",
                "end",
                "endDayOffset"
            ])
        }
        if options.includeBreaks {
            columns.append("breakMinutes")
        }
        columns.append(contentsOf: [
            "type",
            "workedHours"
        ])
        if options.includePay {
            columns.append("workedPay")
        }
        columns.append("creditedHours")
        if options.includePay {
            columns.append("creditedPay")
        }
        if options.includeTips {
            columns.append("tipAmount")
        }
        return columns.joined(separator: ",")
    }

    private func tipFields(for summary: DayTipSummary, options: MonthExportOptions) -> [String] {
        var fields = [
            "",
            PayScopeFormatters.isoDay.string(from: summary.date)
        ]
        if options.includeShiftTimes {
            fields.append(contentsOf: [
                "-",
                "-",
                "-"
            ])
        }
        if options.includeBreaks {
            fields.append("-")
        }
        fields.append(contentsOf: [
            "-",
            "-"
        ])
        if options.includePay {
            fields.append("-")
        }
        fields.append("-")
        if options.includePay {
            fields.append("-")
        }
        fields.append(tipAmountText(cents: summary.amountCents))
        return fields
    }

    private struct DayTipSummary {
        let date: Date
        let amountCents: Int
    }

    private func tipSummariesByLocalDay(from tips: [TipEntry]) -> [DayTipSummary] {
        var totals: [String: DayTipSummary] = [:]

        for tip in tips where tip.amountCents > 0 {
            let day = tip.date.startOfDayLocal()
            let key = localDayKey(for: day)
            let currentAmount = totals[key]?.amountCents ?? 0
            totals[key] = DayTipSummary(date: day, amountCents: currentAmount + tip.amountCents)
        }

        return totals.values.sorted { $0.date < $1.date }
    }

    private func localDayKey(for date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private func tipAmountText(cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100)
    }

    private nonisolated static func csvField(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n") else {
            return normalized
        }
        return "\"\(normalized.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

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

        let filtered = entries
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }
        let monthTips = tips
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }

        var lines: [String] = [csvHeader(options: options)]
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
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
                fields.append("")
            }
            let row = fields.map(Self.csvField).joined(separator: ",")
            lines.append(row)
        }

        if options.includeTips {
            for tip in monthTips {
                let row = tipFields(for: tip, options: options).map(Self.csvField).joined(separator: ",")
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

    private func tipFields(for tip: TipEntry, options: MonthExportOptions) -> [String] {
        var fields = [
            "eurosign.circle.fill",
            PayScopeFormatters.isoDay.string(from: tip.date)
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
            "tip",
            "0.00"
        ])
        if options.includePay {
            fields.append("")
        }
        fields.append("0.00")
        if options.includePay {
            fields.append("")
        }
        fields.append(String(format: "%.2f", Double(tip.amountCents) / 100))
        return fields
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

import Foundation

struct CSVExporter {
    let service: CalculationService

    init(service: CalculationService = CalculationService()) {
        self.service = service
    }

    func csvForMonth(entries: [DayEntry], month: Date, settings: Settings) -> String {
        guard
            let monthRange = Calendar.current.dateInterval(of: .month, for: month)
        else {
            return ""
        }

        let filtered = entries
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }

        var lines: [String] = ["date,type,workedHours,workedPay,creditedHours,creditedPay,notes"]
        for entry in filtered {
            let result = service.dayComputation(for: entry, allEntries: entries, settings: settings)

            let workedSeconds: Int
            let workedPay: Int
            switch service.workedSeconds(for: entry) {
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

            let row = [
                PayScopeFormatters.isoDay.string(from: entry.date),
                entry.type.rawValue,
                String(format: "%.2f", Double(workedSeconds) / 3600),
                String(format: "%.2f", Double(workedPay) / 100),
                String(format: "%.2f", Double(creditedSeconds) / 3600),
                String(format: "%.2f", Double(creditedPay) / 100),
                entry.notes.replacingOccurrences(of: ",", with: " ")
            ].joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }
}

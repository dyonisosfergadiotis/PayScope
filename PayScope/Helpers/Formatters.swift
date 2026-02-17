import Foundation

enum WageWiseFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale.current
        return formatter
    }()

    static func hoursString(seconds: Int) -> String {
        let hours = Double(seconds) / 3600.0
        return String(format: "%.2f h", hours)
    }

    static func hhmmString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    static func currencyString(cents: Int) -> String {
        let amount = Decimal(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: amount as NSDecimalNumber) ?? "-"
    }
}

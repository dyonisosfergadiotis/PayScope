import Foundation
import UIKit

struct MonthExportOptions: Equatable {
    var includeShiftTimes: Bool
    var includePay: Bool
    var includeTips: Bool
    var includeNotesAndWarnings: Bool

    init(
        includeShiftTimes: Bool = true,
        includePay: Bool = true,
        includeTips: Bool = true,
        includeNotesAndWarnings: Bool = true
    ) {
        self.includeShiftTimes = includeShiftTimes
        self.includePay = includePay
        self.includeTips = includeTips
        self.includeNotesAndWarnings = includeNotesAndWarnings
    }
}

fileprivate enum ShiftMonthlyExportStatusKind {
    case warning
    case error
}

fileprivate struct ShiftMonthlyExportReport {
    let month: Date
    let rows: [ShiftMonthlyExportRow]
    let tipRows: [ShiftMonthlyTipExportRow]
    let tipCents: Int
    let totalSeconds: Int
    let totalCents: Int
    let warningCount: Int
    let errorCount: Int

    var totalIncludingTipsCents: Int {
        totalCents + tipCents
    }
}

fileprivate struct ShiftMonthlyTipExportRow {
    let dateText: String
    let amountText: String
    let amountCents: Int
}

fileprivate struct ShiftMonthlyExportRow {
    let entry: DayEntry
    let dateText: String
    let typeText: String
    let timeText: String
    let breakText: String
    let hoursText: String
    let payText: String
    let notesText: String
    let statusText: String?
    let statusKind: ShiftMonthlyExportStatusKind?
    let valueSeconds: Int
    let valueCents: Int
    let result: ComputationResult
}

struct ShiftTextExporter {
    private let calendar: Calendar
    private let service: CalculationService

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.service = CalculationService(calendar: calendar)
    }

    func textForMonth(
        entries: [DayEntry],
        tips: [TipEntry],
        month: Date,
        settings: Settings,
        options: MonthExportOptions = MonthExportOptions()
    ) -> String {
        let report = reportForMonth(entries: entries, tips: tips, month: month, settings: settings)
        var lines: [String] = [
            "PayScope Export \(Self.monthFormatter.string(from: month))",
            ""
        ]

        if report.rows.isEmpty {
            lines.append("Keine Schichten.")
        } else {
            for row in report.rows {
                lines.append(line(for: row, options: options))
            }
        }

        if options.includeTips && !report.tipRows.isEmpty {
            lines.append("")
            lines.append("Trinkgeld")
            for row in report.tipRows {
                lines.append("\(row.dateText) | Trinkgeld | \(row.amountText)")
            }
        }

        lines.append("")
        lines.append("Gesamt")
        lines.append("Stunden: \(PayScopeFormatters.hhmmString(seconds: report.totalSeconds)) h")
        if options.includePay {
            lines.append("Lohn: \(PayScopeFormatters.currencyString(cents: report.totalCents))")
        }
        if options.includeTips {
            lines.append("Trinkgeld: \(PayScopeFormatters.currencyString(cents: report.tipCents))")
        }
        if options.includePay && options.includeTips {
            lines.append("Gesamt inkl. Trinkgeld: \(PayScopeFormatters.currencyString(cents: report.totalIncludingTipsCents))")
        }

        if options.includeNotesAndWarnings && (report.warningCount > 0 || report.errorCount > 0) {
            lines.append("Hinweise: \(report.warningCount) Warnungen, \(report.errorCount) nicht berechenbare Tage")
        }

        return lines.joined(separator: "\n")
    }

    fileprivate func reportForMonth(
        entries: [DayEntry],
        tips: [TipEntry],
        month: Date,
        settings: Settings
    ) -> ShiftMonthlyExportReport {
        let interval = monthInterval(for: month)
        let monthEntries = entries
            .filter { isDate($0.date, in: interval) }
            .sorted { $0.date < $1.date }
        let monthTips = tips
            .filter { isDate($0.date, in: interval) }
            .sorted { $0.date < $1.date }
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        let rows = monthEntries.map { row(for: $0, entriesByDate: entriesByDate, settings: settings) }
        let tipRows = monthTips.map { tip in
            ShiftMonthlyTipExportRow(
                dateText: PayScopeFormatters.day.string(from: tip.date),
                amountText: PayScopeFormatters.currencyString(cents: tip.amountCents),
                amountCents: tip.amountCents
            )
        }

        return ShiftMonthlyExportReport(
            month: month,
            rows: rows,
            tipRows: tipRows,
            tipCents: tipRows.reduce(0) { $0 + $1.amountCents },
            totalSeconds: rows.reduce(0) { $0 + $1.valueSeconds },
            totalCents: rows.reduce(0) { $0 + $1.valueCents },
            warningCount: rows.filter { $0.statusKind == .warning }.count,
            errorCount: rows.filter { $0.statusKind == .error }.count
        )
    }

    private func row(
        for entry: DayEntry,
        entriesByDate: [Date: DayEntry],
        settings: Settings
    ) -> ShiftMonthlyExportRow {
        let result = service.exportComputation(for: entry, entriesByDate: entriesByDate, settings: settings)
        let status = status(for: result)
        let valueSeconds = result.valueSecondsOrZero
        let valueCents = result.valueCentsOrZero

        return ShiftMonthlyExportRow(
            entry: entry,
            dateText: PayScopeFormatters.day.string(from: entry.date),
            typeText: entry.type.label,
            timeText: timeText(for: entry),
            breakText: breakText(for: entry),
            hoursText: "\(PayScopeFormatters.hhmmString(seconds: valueSeconds)) h",
            payText: PayScopeFormatters.currencyString(cents: valueCents),
            notesText: compact(entry.notes),
            statusText: status.text,
            statusKind: status.kind,
            valueSeconds: valueSeconds,
            valueCents: valueCents,
            result: result
        )
    }

    private func line(for row: ShiftMonthlyExportRow, options: MonthExportOptions) -> String {
        var parts = [
            row.dateText,
            row.typeText
        ]

        if options.includeShiftTimes {
            parts.append(row.timeText)
        }

        parts.append("Stunden \(row.hoursText)")

        if options.includePay {
            parts.append("Lohn \(row.payText)")
        }

        if options.includeShiftTimes && row.breakText != "-" {
            parts.append("Pause \(row.breakText)")
        }

        if options.includeNotesAndWarnings, let statusText = row.statusText {
            parts.append(statusText)
        }

        if options.includeNotesAndWarnings && !row.notesText.isEmpty {
            parts.append("Notiz: \(row.notesText)")
        }

        return parts.joined(separator: " | ")
    }

    private func timeText(for entry: DayEntry) -> String {
        if let shiftStart = entry.shiftStart, let shiftEnd = entry.shiftEnd, shiftEnd > shiftStart {
            return ShiftTimeRange.displayRange(start: shiftStart, end: shiftEnd, calendar: calendar)
        }

        if entry.type == .manual {
            return "manuell"
        }

        if entry.creditedOverrideSeconds != nil {
            return "angepasst"
        }

        if entry.type == .vacation || entry.type == .holiday || entry.type == .sick,
           entry.manualWorkedSeconds != nil {
            return "gespeichert"
        }

        return "ganztägig"
    }

    private func breakText(for entry: DayEntry) -> String {
        guard entry.type == .work else { return "-" }
        let breakMinutes = max(0, (entry.breakSeconds ?? 0) / 60)
        return breakMinutes > 0 ? "\(breakMinutes) min" : "-"
    }

    private func status(for result: ComputationResult) -> (text: String?, kind: ShiftMonthlyExportStatusKind?) {
        switch result {
        case let .warning(_, _, message):
            return ("Hinweis: \(compact(message))", .warning)
        case let .error(message, _):
            return ("Nicht berechenbar: \(compact(message))", .error)
        case .ok:
            return (nil, nil)
        }
    }

    private func monthInterval(for month: Date) -> DateInterval {
        let start = month.startOfMonthLocal(calendar: calendar)
        let endExclusive = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingDays(31, calendar: calendar)
        return DateInterval(start: start, end: endExclusive.addingTimeInterval(-1))
    }

    private func isDate(_ date: Date, in interval: DateInterval) -> Bool {
        let day = date.startOfDayLocal(calendar: calendar)
        return day >= interval.start.startOfDayLocal(calendar: calendar) &&
            day <= interval.end.startOfDayLocal(calendar: calendar)
    }

    private func compact(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()
}

struct ShiftPDFExporter {
    private let textExporter: ShiftTextExporter

    init(textExporter: ShiftTextExporter = ShiftTextExporter()) {
        self.textExporter = textExporter
    }

    func pdfURLForMonth(
        entries: [DayEntry],
        tips: [TipEntry],
        month: Date,
        settings: Settings,
        options: MonthExportOptions = MonthExportOptions()
    ) throws -> URL {
        let report = textExporter.reportForMonth(entries: entries, tips: tips, month: month, settings: settings)
        let fileName = "PayScope-\(Self.fileMonthFormatter.string(from: month)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)

        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let margin: CGFloat = 34
        let footerHeight: CGFloat = 30
        let contentWidth = pageBounds.width - (margin * 2)
        let contentBottom = pageBounds.height - margin - footerHeight

        let paperColor = UIColor(red: 0.973, green: 0.976, blue: 0.984, alpha: 1)
        let cardColor = UIColor.white
        let inkColor = UIColor(red: 0.075, green: 0.09, blue: 0.125, alpha: 1)
        let mutedColor = UIColor(red: 0.39, green: 0.42, blue: 0.48, alpha: 1)
        let lineColor = UIColor(red: 0.84, green: 0.86, blue: 0.90, alpha: 1)
        let accentColor = UIColor(red: 0.05, green: 0.32, blue: 0.74, alpha: 1)
        let greenColor = UIColor(red: 0.04, green: 0.48, blue: 0.31, alpha: 1)
        let warningColor = UIColor(red: 0.72, green: 0.39, blue: 0.05, alpha: 1)
        let errorColor = UIColor(red: 0.72, green: 0.11, blue: 0.14, alpha: 1)

        let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 10.5, weight: .medium)
        let cardLabelFont = UIFont.systemFont(ofSize: 8.2, weight: .semibold)
        let cardValueFont = UIFont.systemFont(ofSize: 15.5, weight: .bold)
        let tableHeaderFont = UIFont.systemFont(ofSize: 8.2, weight: .bold)
        let rowFont = UIFont.systemFont(ofSize: 8.5, weight: .regular)
        let rowBoldFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let smallFont = UIFont.systemFont(ofSize: 7.5, weight: .regular)

        let dateColumnID = 0
        let typeColumnID = 1
        let timeColumnID = 2
        let hoursColumnID = 3
        let payColumnID = 4
        let infoColumnID = 5

        var baseColumns: [(id: Int, title: String, width: CGFloat)] = [
            (dateColumnID, "Datum", 68),
            (typeColumnID, "Typ", 70)
        ]
        if options.includeShiftTimes {
            baseColumns.append((timeColumnID, "Zeit", 74))
        }
        baseColumns.append((hoursColumnID, "Stunden", 54))
        if options.includePay {
            baseColumns.append((payColumnID, "Lohn", 68))
        }

        let fixedWidth = baseColumns.reduce(CGFloat(0)) { $0 + $1.width }
        let usesInfoColumn = options.includeNotesAndWarnings || options.includeShiftTimes
        let columns: [(id: Int, title: String, width: CGFloat)] = {
            guard usesInfoColumn else {
                let extraWidth = max(0, contentWidth - fixedWidth)
                let extraPerColumn = extraWidth / CGFloat(max(1, baseColumns.count))
                return baseColumns.map { ($0.id, $0.title, $0.width + extraPerColumn) }
            }

            var result = baseColumns
            let infoWidth = max(72, contentWidth - fixedWidth)
            let infoTitle = options.includeNotesAndWarnings ? "Info" : "Pause"
            result.append((infoColumnID, infoTitle, infoWidth))
            return result
        }()

        try renderer.writePDF(to: url) { context in
            var y = margin
            var pageNumber = 0

            func paragraph(
                alignment: NSTextAlignment = .left,
                lineBreak: NSLineBreakMode = .byWordWrapping
            ) -> NSMutableParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                style.lineBreakMode = lineBreak
                return style
            }

            func attributes(
                font: UIFont,
                color: UIColor,
                alignment: NSTextAlignment = .left,
                lineBreak: NSLineBreakMode = .byWordWrapping
            ) -> [NSAttributedString.Key: Any] {
                [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph(alignment: alignment, lineBreak: lineBreak)
                ]
            }

            func drawText(
                _ text: String,
                in rect: CGRect,
                font: UIFont,
                color: UIColor,
                alignment: NSTextAlignment = .left,
                lineBreak: NSLineBreakMode = .byWordWrapping
            ) {
                (text as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes(font: font, color: color, alignment: alignment, lineBreak: lineBreak),
                    context: nil
                )
            }

            func measuredHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
                guard !text.isEmpty else { return 0 }
                let rect = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes(font: font, color: inkColor),
                    context: nil
                )
                return ceil(rect.height)
            }

            func fillRoundedRect(_ rect: CGRect, color: UIColor, radius: CGFloat = 8) {
                color.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            }

            func strokeRoundedRect(_ rect: CGRect, color: UIColor, radius: CGFloat = 8, width: CGFloat = 0.8) {
                color.setStroke()
                let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
                path.lineWidth = width
                path.stroke()
            }

            func columnX(_ index: Int) -> CGFloat {
                margin + columns.prefix(index).reduce(CGFloat(0)) { $0 + $1.width }
            }

            func drawFooter() {
                let footerY = pageBounds.height - margin - 12
                lineColor.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: footerY - 10))
                path.addLine(to: CGPoint(x: pageBounds.width - margin, y: footerY - 10))
                path.lineWidth = 0.6
                path.stroke()
                drawText(
                    "PayScope",
                    in: CGRect(x: margin, y: footerY - 4, width: 160, height: 12),
                    font: smallFont,
                    color: mutedColor
                )
                drawText(
                    "Seite \(pageNumber)",
                    in: CGRect(x: pageBounds.width - margin - 90, y: footerY - 4, width: 90, height: 12),
                    font: smallFont,
                    color: mutedColor,
                    alignment: .right
                )
            }

            func beginPage(continuation: Bool) {
                context.beginPage()
                pageNumber += 1
                paperColor.setFill()
                context.fill(pageBounds)
                drawFooter()
                y = margin

                guard continuation else { return }
                drawText(
                    "PayScope · \(Self.displayMonthFormatter.string(from: report.month))",
                    in: CGRect(x: margin, y: y, width: contentWidth, height: 16),
                    font: subtitleFont,
                    color: mutedColor
                )
                y += 24
            }

            func drawHeader() {
                let monthText = Self.displayMonthFormatter.string(from: report.month)
                let generatedText = "Erstellt am \(Self.generatedFormatter.string(from: Date()))"
                fillRoundedRect(
                    CGRect(x: margin, y: y, width: 5, height: 58),
                    color: accentColor,
                    radius: 2.5
                )
                drawText(
                    "PayScope",
                    in: CGRect(x: margin + 16, y: y - 1, width: 220, height: 30),
                    font: titleFont,
                    color: inkColor
                )
                drawText(
                    "Monatsreport \(monthText)",
                    in: CGRect(x: margin + 17, y: y + 31, width: 250, height: 16),
                    font: subtitleFont,
                    color: mutedColor
                )
                drawText(
                    generatedText,
                    in: CGRect(x: pageBounds.width - margin - 190, y: y + 3, width: 190, height: 14),
                    font: subtitleFont,
                    color: mutedColor,
                    alignment: .right
                )

                if options.includeNotesAndWarnings && (report.warningCount > 0 || report.errorCount > 0) {
                    let statusText = "\(report.warningCount) Hinweise · \(report.errorCount) offen"
                    let statusColor = report.errorCount > 0 ? errorColor : warningColor
                    let statusRect = CGRect(x: pageBounds.width - margin - 128, y: y + 25, width: 128, height: 24)
                    fillRoundedRect(statusRect, color: statusColor.withAlphaComponent(0.10), radius: 6)
                    drawText(
                        statusText,
                        in: statusRect.insetBy(dx: 8, dy: 6),
                        font: smallFont,
                        color: statusColor,
                        alignment: .center
                    )
                }

                y += 76
            }

            func drawSummaryCards() {
                let gap: CGFloat = 9
                let cardHeight: CGFloat = 56
                var values: [(label: String, value: String, color: UIColor)] = [
                    ("STUNDEN", "\(PayScopeFormatters.hhmmString(seconds: report.totalSeconds)) h", accentColor)
                ]
                if options.includePay {
                    values.append(("LOHN", PayScopeFormatters.currencyString(cents: report.totalCents), greenColor))
                }
                if options.includeTips {
                    values.append(("TRINKGELD", PayScopeFormatters.currencyString(cents: report.tipCents), warningColor))
                }
                if options.includePay && options.includeTips {
                    values.append(("GESAMT", PayScopeFormatters.currencyString(cents: report.totalIncludingTipsCents), inkColor))
                }

                let gapTotal = gap * CGFloat(max(0, values.count - 1))
                let cardWidth = (contentWidth - gapTotal) / CGFloat(max(1, values.count))

                for (index, item) in values.enumerated() {
                    let x = margin + CGFloat(index) * (cardWidth + gap)
                    let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
                    fillRoundedRect(rect, color: cardColor, radius: 8)
                    strokeRoundedRect(rect, color: lineColor, radius: 8)
                    fillRoundedRect(
                        CGRect(x: x, y: y, width: 4, height: cardHeight),
                        color: item.color,
                        radius: 2
                    )
                    drawText(
                        item.label,
                        in: CGRect(x: x + 13, y: y + 11, width: cardWidth - 22, height: 10),
                        font: cardLabelFont,
                        color: mutedColor,
                        lineBreak: .byTruncatingTail
                    )
                    drawText(
                        item.value,
                        in: CGRect(x: x + 13, y: y + 28, width: cardWidth - 22, height: 19),
                        font: cardValueFont,
                        color: item.color,
                        lineBreak: .byTruncatingTail
                    )
                }

                y += cardHeight + 22
            }

            func drawTableHeader() {
                let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: 24)
                fillRoundedRect(headerRect, color: inkColor, radius: 7)

                for (index, column) in columns.enumerated() {
                    drawText(
                        column.title,
                        in: CGRect(x: columnX(index) + 8, y: y + 7, width: column.width - 12, height: 11),
                        font: tableHeaderFont,
                        color: .white,
                        lineBreak: .byTruncatingTail
                    )
                }

                y += 28
            }

            func categoryColor(for type: DayType) -> UIColor {
                switch type {
                case .work: return accentColor
                case .manual: return UIColor(red: 0.42, green: 0.25, blue: 0.74, alpha: 1)
                case .vacation: return greenColor
                case .holiday: return warningColor
                case .sick: return errorColor
                }
            }

            func statusColor(for kind: ShiftMonthlyExportStatusKind?) -> UIColor {
                switch kind {
                case .some(.warning): return warningColor
                case .some(.error): return errorColor
                case .none: return mutedColor
                }
            }

            func drawEmptyState() {
                let rect = CGRect(x: margin, y: y, width: contentWidth, height: 78)
                fillRoundedRect(rect, color: cardColor, radius: 8)
                strokeRoundedRect(rect, color: lineColor, radius: 8)
                drawText(
                    "Keine Schichten im gewählten Monat.",
                    in: rect.insetBy(dx: 18, dy: 28),
                    font: rowBoldFont,
                    color: mutedColor,
                    alignment: .center
                )
                y += 92
            }

            func columnIndex(for id: Int) -> Int? {
                columns.firstIndex { $0.id == id }
            }

            func columnFrame(
                for id: Int,
                rowY: CGFloat,
                rowHeight: CGFloat,
                xInset: CGFloat = 8,
                yInset: CGFloat = 10
            ) -> CGRect? {
                guard let index = columnIndex(for: id) else { return nil }
                let column = columns[index]
                return CGRect(
                    x: columnX(index) + xInset,
                    y: rowY + yInset,
                    width: column.width - (xInset + 5),
                    height: rowHeight - (yInset + 4)
                )
            }

            func infoItems(for row: ShiftMonthlyExportRow) -> [(text: String, color: UIColor)] {
                var items: [(text: String, color: UIColor)] = []
                if options.includeShiftTimes && row.breakText != "-" {
                    items.append(("Pause \(row.breakText)", mutedColor))
                }
                if options.includeNotesAndWarnings && !row.notesText.isEmpty {
                    items.append((row.notesText, inkColor))
                }
                if options.includeNotesAndWarnings, let statusText = row.statusText {
                    items.append((statusText, statusColor(for: row.statusKind)))
                }
                return items
            }

            func drawRow(_ row: ShiftMonthlyExportRow, index: Int) {
                let infoIndex = columnIndex(for: infoColumnID)
                let infoWidth = infoIndex.map { max(40, columns[$0].width - 16) } ?? 0
                let infoHeight = infoItems(for: row).reduce(CGFloat(0)) { partial, item in
                    partial + measuredHeight(item.text, width: infoWidth, font: smallFont) + 2
                }
                let rowHeight = min(max(38, max(16, infoHeight) + 18), 82)

                if y + rowHeight > contentBottom {
                    beginPage(continuation: true)
                    drawTableHeader()
                }

                let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
                let rowBackground = index.isMultiple(of: 2)
                    ? cardColor
                    : UIColor(red: 0.945, green: 0.952, blue: 0.966, alpha: 1)
                fillRoundedRect(rowRect, color: rowBackground, radius: 6)
                strokeRoundedRect(rowRect, color: lineColor.withAlphaComponent(0.75), radius: 6, width: 0.5)

                let category = categoryColor(for: row.entry.type)
                fillRoundedRect(
                    CGRect(x: margin, y: y, width: 3.5, height: rowHeight),
                    color: category,
                    radius: 2
                )

                if let dateFrame = columnFrame(for: dateColumnID, rowY: y, rowHeight: rowHeight) {
                    drawText(
                        row.dateText,
                        in: dateFrame,
                        font: rowFont,
                        color: inkColor,
                        lineBreak: .byTruncatingTail
                    )
                }

                if let typeIndex = columnIndex(for: typeColumnID) {
                    let typeColumn = columns[typeIndex]
                    let chipRect = CGRect(x: columnX(typeIndex) + 7, y: y + 8, width: typeColumn.width - 14, height: 18)
                    fillRoundedRect(chipRect, color: category.withAlphaComponent(0.11), radius: 5)
                    drawText(
                        row.typeText,
                        in: chipRect.insetBy(dx: 5, dy: 4),
                        font: smallFont,
                        color: category,
                        alignment: .center,
                        lineBreak: .byTruncatingTail
                    )
                }

                if let timeFrame = columnFrame(for: timeColumnID, rowY: y, rowHeight: rowHeight) {
                    drawText(
                        row.timeText,
                        in: timeFrame,
                        font: rowFont,
                        color: inkColor,
                        lineBreak: .byTruncatingTail
                    )
                }

                if let hoursFrame = columnFrame(for: hoursColumnID, rowY: y, rowHeight: rowHeight) {
                    drawText(
                        row.hoursText,
                        in: hoursFrame,
                        font: rowBoldFont,
                        color: inkColor,
                        lineBreak: .byTruncatingTail
                    )
                }

                if let payFrame = columnFrame(for: payColumnID, rowY: y, rowHeight: rowHeight) {
                    drawText(
                        row.payText,
                        in: payFrame,
                        font: rowBoldFont,
                        color: greenColor,
                        lineBreak: .byTruncatingTail
                    )
                }

                if let infoIndex {
                    let noteX = columnX(infoIndex) + 8
                    var noteY = y + 8
                    let items = infoItems(for: row)
                    if items.isEmpty {
                        drawText(
                            " ",
                            in: CGRect(x: noteX, y: noteY + 3, width: infoWidth, height: 12),
                            font: smallFont,
                            color: mutedColor,
                            lineBreak: .byTruncatingTail
                        )
                    } else {
                        for item in items {
                            guard noteY < y + rowHeight - 8 else { break }
                            let remainingHeight = y + rowHeight - 8 - noteY
                            let itemHeight = min(
                                measuredHeight(item.text, width: infoWidth, font: smallFont),
                                remainingHeight
                            )

                            drawText(
                                item.text,
                                in: CGRect(x: noteX, y: noteY, width: infoWidth, height: itemHeight),
                                font: smallFont,
                                color: item.color,
                                lineBreak: .byTruncatingTail
                            )
                            noteY += itemHeight + 2
                        }
                    }
                }

                y += rowHeight + 5
            }

            beginPage(continuation: false)
            drawHeader()
            drawSummaryCards()
            drawTableHeader()

            if report.rows.isEmpty {
                drawEmptyState()
            } else {
                for (index, row) in report.rows.enumerated() {
                    drawRow(row, index: index)
                }
            }
        }

        return url
    }

    private static let fileMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let displayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    private static let generatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

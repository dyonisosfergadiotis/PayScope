import SwiftUI

struct DayDetailView: View {
    let date: Date
    let entry: DayEntry?
    let accentColor: Color
    let computedSeconds: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            categoryIcon
            shiftInfoCard
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var categoryIcon: some View {
        Image(systemName: entry?.type.icon ?? "calendar.badge.clock")
            .font(.title3.weight(.semibold))
            .foregroundStyle(categoryColor)
            .frame(width: 22)
    }

    private var categoryColor: Color {
        guard let entry else { return .secondary }
        return entry.type == .work ? accentColor : entry.type.tint
    }

    private var shiftInfoCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                //infoField(icon: "calendar", value: dayDateString())
                infoField(icon: "clock.badge.checkmark", value: totalValueString())
                infoField(icon: "play.fill", value: startTimeString())
                infoField(icon: "stop.fill", value: endTimeString())
                infoField(icon: "cup.and.saucer.fill", value: pauseString())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    infoField(icon: "calendar", value: dayDateString())
                    infoField(icon: "clock.badge.checkmark", value: totalValueString())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    infoField(icon: "play.fill", value: startTimeString())
                    infoField(icon: "stop.fill", value: endTimeString())
                    infoField(icon: "cup.and.saucer.fill", value: pauseString())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func infoField(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.88)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM."
        return formatter.string(from: date)
    }

    private func startTimeString() -> String {
        guard let entry else { return "-" }
        let start = entry.shiftStart ?? entry.segments.map(\.start).min()
        guard let start else { return "-" }
        return timeString(start)
    }

    private func endTimeString() -> String {
        guard let entry else { return "-" }
        let end = entry.shiftEnd ?? entry.segments.map(\.end).max()
        guard let end else { return "-" }
        let suffix = entry.shiftStart.map { Calendar.current.isDate($0, inSameDayAs: end) ? "" : " +1" } ?? ""
        return "\(timeString(end))\(suffix)"
    }

    private func pauseString() -> String {
        guard let entry else { return "-" }
        let breakSeconds = entry.breakSeconds ?? entry.segments.reduce(0) { $0 + $1.breakSeconds }
        return Formatters.hhmmString(seconds: max(0, breakSeconds))
    }

    private func totalValueString() -> String {
        if let entry {
            if entry.type == .vacation || entry.type == .holiday || entry.type == .sick {
                if let overrideSeconds = entry.creditedOverrideSeconds {
                    return Formatters.hhmmString(seconds: max(0, overrideSeconds))
                }
                if let computedSeconds {
                    return Formatters.hhmmString(seconds: max(0, computedSeconds))
                }
                if let cached = entry.manualWorkedSeconds {
                    return Formatters.hhmmString(seconds: max(0, cached))
                }
                return "-"
            }

            if let overrideSeconds = entry.creditedOverrideSeconds, overrideSeconds > 0 {
                return Formatters.hhmmString(seconds: overrideSeconds)
            }
            if let manual = entry.manualWorkedSeconds, manual > 0 {
                return Formatters.hhmmString(seconds: manual)
            }

            if let start = entry.shiftStart, let end = entry.shiftEnd, end > start {
                let raw = Int(end.timeIntervalSince(start))
                let breakSeconds = max(0, entry.breakSeconds ?? 0)
                return Formatters.hhmmString(seconds: max(0, raw - breakSeconds))
            }

            let segmentSeconds = entry.segments.reduce(0) { sum, segment in
                let raw = Int(segment.end.timeIntervalSince(segment.start))
                return sum + max(0, raw - segment.breakSeconds)
            }
            if segmentSeconds > 0 {
                return Formatters.hhmmString(seconds: segmentSeconds)
            }
        }
        if let computedSeconds, computedSeconds > 0 {
            return Formatters.hhmmString(seconds: computedSeconds)
        }
        return "-"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    let sampleSegment1 = TimeSegment(start: Date().addingTimeInterval(-4.5 * 3600), end: Date().addingTimeInterval(-2 * 3600), breakSeconds: 900)
    let sampleSegment2 = TimeSegment(start: Date().addingTimeInterval(-1.5 * 3600), end: Date(), breakSeconds: 0)
    let sampleEntry = DayEntry(date: Date(), type: .work, notes: "Normalarbeitstag", segments: [sampleSegment1, sampleSegment2])

    DayDetailView(date: Date(), entry: sampleEntry, accentColor: .green, computedSeconds: nil)
        .padding()
}

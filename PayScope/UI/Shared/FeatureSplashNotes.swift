import SwiftUI

struct FeatureSplashCard: Identifiable {
    let id: String
    let title: String
    let rows: [FeatureSplashRow]
}

struct FeatureSplashRow: Identifiable {
    let id: String
    let symbolSystemName: String
    let title: String
    let description: String

    init(symbolSystemName: String, title: String, description: String) {
        self.id = "\(symbolSystemName)-\(title)"
        self.symbolSystemName = symbolSystemName
        self.title = title
        self.description = description
    }
}

enum FeatureSplashNotes {
    static let version = "payscope-feature-splash-v1"
    static let storageKey = "payscope.featureSplash.v1.seen"

    static let cards: [FeatureSplashCard] = [
        FeatureSplashCard(
            id: "shifts",
            title: "Schichten hinzufügen",
            rows: [
                FeatureSplashRow(
                    symbolSystemName: "calendar.badge.plus",
                    title: "Tag antippen",
                    description: "Öffne einen Kalendertag und trage Start, Ende, Pause und Kategorie ein."
                ),
                FeatureSplashRow(
                    symbolSystemName: "pencil",
                    title: "Schnell bearbeiten",
                    description: "Bestehende Einträge lassen sich direkt aus der Tagesansicht ändern."
                ),
                FeatureSplashRow(
                    symbolSystemName: "trash",
                    title: "Gezielt löschen",
                    description: "Löschen sitzt im Tagesblatt, damit versehentliche Long-Press-Aktionen wegfallen."
                )
            ]
        ),
        FeatureSplashCard(
            id: "stats",
            title: "Statistiken",
            rows: [
                FeatureSplashRow(
                    symbolSystemName: "chart.bar.xaxis",
                    title: "Monat im Blick",
                    description: "Wechsle den Monat und vergleiche Stunden, Lohn und Tagestypen."
                ),
                FeatureSplashRow(
                    symbolSystemName: "calendar",
                    title: "Gleicher Monatsregler",
                    description: "Kalender und Statistik teilen sich dieselbe Monatsauswahl."
                ),
                FeatureSplashRow(
                    symbolSystemName: "eurosign.circle",
                    title: "Lohnwerte prüfen",
                    description: "Die Auswertungen nutzen dieselben Regeln wie deine Tagesberechnung."
                )
            ]
        ),
        FeatureSplashCard(
            id: "tips",
            title: "Trinkgeld",
            rows: [
                FeatureSplashRow(
                    symbolSystemName: "eurosign.circle.fill",
                    title: "Monatssumme öffnen",
                    description: "Der Trinkgeld-Button im Kalender führt zur Monatsliste."
                ),
                FeatureSplashRow(
                    symbolSystemName: "plus",
                    title: "Beträge hinzufügen",
                    description: "Erfasse Trinkgeld pro Tag und passe Einträge später wieder an."
                ),
                FeatureSplashRow(
                    symbolSystemName: "square.and.arrow.up",
                    title: "Export inklusive",
                    description: "Bei Monatsauswertungen kann Trinkgeld mit ausgegeben werden."
                )
            ]
        ),
        FeatureSplashCard(
            id: "today",
            title: "Heute",
            rows: [
                FeatureSplashRow(
                    symbolSystemName: "sun.max.fill",
                    title: "Aktuelle Schicht",
                    description: "Die Heute-Ansicht zeigt Fortschritt, verbleibende Zeit und laufenden Lohn."
                ),
                FeatureSplashRow(
                    symbolSystemName: "timer",
                    title: "Live aktualisiert",
                    description: "Während einer Schicht werden Zeit und Fortschritt automatisch nachgeführt."
                ),
                FeatureSplashRow(
                    symbolSystemName: "target",
                    title: "Sollzeit vergleichen",
                    description: "Tages- und Wochenwerte zeigen, wo du gerade stehst."
                )
            ]
        ),
        FeatureSplashCard(
            id: "widgets",
            title: "Widgets",
            rows: [
                FeatureSplashRow(
                    symbolSystemName: "rectangle.on.rectangle",
                    title: "Lock Screen",
                    description: "Widgets zeigen Status, nächste Schicht und Ganztagseinstellungen."
                ),
                FeatureSplashRow(
                    symbolSystemName: "livephoto",
                    title: "Live Activity",
                    description: "Geplante Schichten können automatisch als Live Activity starten."
                ),
                FeatureSplashRow(
                    symbolSystemName: "arrow.clockwise",
                    title: "Sofort aktualisieren",
                    description: "In den Einstellungen kannst du Widgets manuell neu laden."
                )
            ]
        )
    ]
}

struct FeatureSplashSheetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let cards: [FeatureSplashCard]
    let accent: Color
    let onDone: () -> Void

    @State private var currentPage = 0
    @State private var pageDirection = 1

    private let cardAnimation = Animation.easeInOut(duration: 0.18)

    private var currentCard: FeatureSplashCard? {
        guard cards.indices.contains(currentPage) else { return nil }
        return cards[currentPage]
    }

    private var isLastPage: Bool {
        currentPage >= cards.count - 1
    }

    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(pageDirection) * 18, y: 0)),
            removal: .opacity.combined(with: .offset(x: CGFloat(pageDirection) * -10, y: 0))
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                pageIndicator

                ZStack(alignment: .top) {
                    if let currentCard {
                        FeatureSplashCardView(card: currentCard, accent: accent)
                            .id(currentCard.id)
                            .transition(cardTransition)
                    }
                }
                .animation(cardAnimation, value: currentPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                controls
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .navigationTitle("Neu in PayScope")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        finish()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .payScopeBackground(accent: accent)
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(cards.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentPage ? accent.opacity(0.78) : Color.secondary.opacity(0.28))
                    .frame(width: index == currentPage ? 18 : 7, height: 7)
            }
        }
        .frame(height: 12)
        .animation(cardAnimation, value: currentPage)
        .accessibilityLabel("Seite \(currentPage + 1) von \(cards.count)")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if currentPage > 0 {
                Button {
                    go(to: currentPage - 1)
                } label: {
                    Label("Zurück", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.payScopeSecondary(accent: accent))
            }

            Button {
                if isLastPage {
                    finish()
                } else {
                    go(to: currentPage + 1)
                }
            } label: {
                Label(isLastPage ? "Loslegen" : "Weiter", systemImage: isLastPage ? "checkmark" : "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(accent)
        }
    }

    private func go(to page: Int) {
        guard cards.indices.contains(page), page != currentPage else { return }
        pageDirection = page > currentPage ? 1 : -1
        withAnimation(cardAnimation) {
            currentPage = page
        }
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

private struct FeatureSplashCardView: View {
    let card: FeatureSplashCard
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: card.rows.first?.symbolSystemName ?? "sparkles")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .payScopeLiquidGlassIcon(accent: accent, tintOpacity: 0.12, shadowOpacity: 0.06)

                Text(card.title)
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            VStack(spacing: 12) {
                ForEach(card.rows) { row in
                    FeatureSplashRowView(row: row, accent: accent)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .payScopeGlassSurface(
            accent: accent,
            cornerRadius: PayScopeModalGeometry.sheet.innerCornerRadius,
            tintOpacity: 0.052,
            shadowOpacity: 0.06,
            isInteractive: false
        )
    }
}

private struct FeatureSplashRowView: View {
    let row: FeatureSplashRow
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.symbolSystemName)
                .font(.system(.subheadline, design: .rounded).weight(.black))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.11))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)

                Text(row.description)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

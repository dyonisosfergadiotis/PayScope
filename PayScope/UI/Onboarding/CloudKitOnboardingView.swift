import CloudKit
import SwiftUI

struct CloudKitOnboardingView: View {
    @StateObject private var viewModel = CloudKitViewModel()
    @State private var accountStatusAlertShown = false
    @State private var showLoadingSpinner = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("iCloud-Synchronisierung")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Synchronisiere deine Daten zwischen all deinen Geräten und erstelle Backups in der Cloud.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                if showLoadingSpinner {
                    ProgressView()
                        .frame(height: 40)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                        Text(statusText)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)

            Spacer()

            Button {
                Task {
                    showLoadingSpinner = true
                    await viewModel.fetchAccountStatus()
                    showLoadingSpinner = false

                    if viewModel.isAccountAvailable() {
                        dismiss()
                    } else {
                        accountStatusAlertShown = true
                    }
                }
            } label: {
                Text("Fortfahren")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(showLoadingSpinner)

            Button(role: .close) {
                dismiss()
            } label: {
                Text("Überspringen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .alert("iCloud nicht verfügbar", isPresented: $accountStatusAlertShown) {
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Später", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Bitte melde dich in den Einstellungen bei iCloud an oder aktiviere iCloud Drive, um die Synchronisierung zu nutzen.")
        }
        .task {
            await viewModel.fetchAccountStatus()
        }
    }

    private var statusText: String {
        switch viewModel.accountStatus {
        case .available:
            return "iCloud verfügbar"
        case .restricted:
            return "iCloud eingeschränkt"
        case .noAccount:
            return "Kein iCloud-Konto angemeldet"
        case .temporarilyUnavailable:
            return "iCloud vorübergehend nicht verfügbar"
        case .couldNotDetermine:
            return "Status wird überprüft..."
        @unknown default:
            return "Unbekannter Status"
        }
    }

    private var statusIcon: String {
        switch viewModel.accountStatus {
        case .available:
            return "checkmark.circle.fill"
        case .restricted, .noAccount:
            return "exclamationmark.circle.fill"
        case .temporarilyUnavailable:
            return "clock.badge.exclamationmark"
        case .couldNotDetermine:
            return "hourglass"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch viewModel.accountStatus {
        case .available:
            return .green
        case .restricted, .noAccount:
            return .orange
        case .temporarilyUnavailable:
            return .yellow
        case .couldNotDetermine:
            return .gray
        @unknown default:
            return .gray
        }
    }
}

#Preview {
    NavigationStack {
        CloudKitOnboardingView()
    }
}

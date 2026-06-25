import SwiftUI

#if os(iOS)
import UIKit

enum AppIconManager {
    static func applyIcon(for accent: ThemeAccent) {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let iconName = accent.alternateAppIconName
        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error {
                print("Failed to update app icon: \(error.localizedDescription)")
            }
        }
    }
}

private extension ThemeAccent {
    var alternateAppIconName: String? {
        switch self {
        case .blue: return nil
        case .green: return "gruen"
        case .purple: return "lila"
        case .orange: return "orange"
        case .pink: return "pink"
        case .teal: return "turkis"
        case .red: return "rot"
        case .indigo: return "indigo"
        }
    }
}
#endif

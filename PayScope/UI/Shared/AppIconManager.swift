import SwiftUI

#if os(iOS)
import UIKit

enum AppIconManager {
    static func applyIcon(for _: ThemeAccent) {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        guard UIApplication.shared.alternateIconName != nil else { return }

        UIApplication.shared.setAlternateIconName(nil) { error in
            if let error {
                print("Failed to reset app icon: \(error.localizedDescription)")
            }
        }
    }
}
#endif

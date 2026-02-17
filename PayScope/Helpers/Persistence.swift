import Foundation
import SwiftData

extension ModelContext {
    func persistIfPossible() {
        do {
            try save()
        } catch {
            #if DEBUG
            print("ModelContext save failed: \(error)")
            #endif
        }
    }
}

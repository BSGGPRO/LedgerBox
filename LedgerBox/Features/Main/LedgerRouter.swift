import Foundation
import SwiftUI

/// App-level sheet routing. Kept separate from views so the bottom FAB,
/// Home empty states and the image flow all open exactly one presentation.
@MainActor
final class LedgerRouter: ObservableObject {
    enum Sheet: String, Identifiable {
        case manual
        case image
        case profile

        var id: String { rawValue }
    }

    @Published var selection: MainTab = .home
    @Published var sheet: Sheet?

    func open(_ sheet: Sheet) {
        self.sheet = sheet
    }

    func close() {
        sheet = nil
    }
}

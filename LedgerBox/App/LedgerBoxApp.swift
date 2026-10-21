import SwiftUI

@main
struct LedgerBoxApp: App {
    private let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(
                    \.managedObjectContext,
                    persistenceController.container.viewContext
                )
                .environmentObject(themeManager)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        let theme = themeManager.theme(for: systemColorScheme)

        MainTabView()
            .environment(\.ledgerTheme, theme)
            .tint(theme.accent)
            .preferredColorScheme(themeManager.preferredColorScheme)
    }
}

#Preview {
    RootView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environmentObject(ThemeManager())
}

import SwiftUI

@main
struct iJecnaApp: App {
    /// Maketa startuje rovnou přihlášená, aby šlo klikat po obrazovkách.
    /// Přihlašovací obrazovka je dostupná přes odhlášení v Nastavení.
    @State private var model = AppModel(service: MockJecnaService(startLoggedIn: true))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // Rozhraní je zatím jen česky, ale `Text(date, format: .relative(…))`
                // se řídí locale zařízení — bez tohohle by na anglickém telefonu
                // vedle českých popisků svítilo „2 days ago“.
                // Až přibude katalog řetězců s angličtinou, půjde locale odvodit
                // od skutečného jazyka rozhraní.
                .environment(\.locale, Locale(identifier: "cs_CZ"))
                .task {
                    if await model.service.isLoggedIn() {
                        model.session = .signedIn(username: MockJecnaService.demoUsername)
                        await model.loadEssentials()
                    }
                }
        }
    }
}

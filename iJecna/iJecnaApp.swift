import SwiftUI
import UserNotifications

@main
struct iJecnaApp: App {
    /// Aplikace normálně chodí na skutečný školní web. Maketa se dá zapnout
    /// proměnnou prostředí, když se ladí vzhled bez připojení:
    /// `SIMCTL_CHILD_USE_MOCK=1 xcrun simctl launch booted mytrofanov.iJecna`
    @State private var model = AppModel(
        service: ProcessInfo.processInfo.environment["USE_MOCK"] == "1"
            ? MockJecnaService(startLoggedIn: true)
            : WebJecnaService()
    )

    /// Úkoly a testy jsou čistě lokální data — vlastní úložiště nezávislé na školním webu.
    @State private var tasks: StudyTaskStore

    /// Bez delegáta by se upozornění při otevřené aplikaci nezobrazilo.
    private let notificationPresenter = NotificationPresenter()

    init() {
        let scheduler = NotificationScheduler()
        _tasks = State(initialValue: StudyTaskStore(scheduler: scheduler))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(tasks)
                // Rozhraní je zatím jen česky, ale `Text(date, format: .relative(…))`
                // se řídí locale zařízení — bez tohohle by na anglickém telefonu
                // vedle českých popisků svítilo „2 days ago“.
                // Až přibude katalog řetězců s angličtinou, půjde locale odvodit
                // od skutečného jazyka rozhraní.
                .environment(\.locale, Locale(identifier: "cs_CZ"))
                .task {
                    UNUserNotificationCenter.current().delegate = notificationPresenter

                    await model.restoreSession()

                    tasks.seedIfEmpty()
                    tasks.setQuietHours(model.settings.quietHoursEnabled)
                    // Systém si drží naplánované požadavky sám; po startu je srovnáme
                    // se skutečným stavem úkolů, ať nezůstanou viset zrušené termíny.
                    tasks.rescheduleAll()
                }
        }
    }
}

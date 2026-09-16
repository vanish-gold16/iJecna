import Foundation
import BackgroundTasks
import UIKit

/// Plánování kontroly na pozadí.
///
/// Tohle je jediná cesta, jak se aplikace dozví o nové známce, aniž by ji
/// student otevřel. Má ale svoje meze, se kterými se musí počítat:
///
/// - Systém si sám rozhoduje, kdy úlohu spustí. `earliestBeginDate` je prosba,
///   ne příkaz; při nečinnosti aplikace může být probuzení i jednou za den.
/// - Na práci je zhruba třicet sekund. Proto se stahuje jen to nejnutnější
///   a úloha musí umět skončit, když ji systém přeruší.
///
/// Okamžité doručení by vyžadovalo server, který by držel školní hesla
/// studentů a web obcházel za ně. To tahle aplikace dělat nechce.
enum BackgroundRefresh {

    static let taskIdentifier = "mytrofanov.iJecna.refresh"

    /// Jak brzy nejdřív si přejeme další probuzení.
    ///
    /// Hodina je kompromis: známky přibývají během vyučování a systém si stejně
    /// interval protáhne podle toho, jak aplikaci používáš.
    static let preferredInterval: TimeInterval = 60 * 60

    /// Požádá systém o další probuzení.
    ///
    /// Volá se po startu aplikace, při odchodu na pozadí a na konci každé
    /// kontroly — jinak by po prvním běhu už nikdy žádný další nepřišel.
    static func schedule(after interval: TimeInterval = preferredInterval) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Na simulátoru a při vypnutém obnovování na pozadí tohle selže;
            // není to důvod cokoli hlásit uživateli.
            #if DEBUG
            print("Úlohu na pozadí se nepodařilo naplánovat: \(error.localizedDescription)")
            #endif
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    /// Stav obnovování na pozadí v systému. Uživatel ho může mít vypnuté
    /// celosystémově nebo jen pro tuhle aplikaci — pak žádná kontrola nepřijde
    /// a nemá smysl tvářit se, že upozornění fungují.
    @MainActor
    static var systemStatus: UIBackgroundRefreshStatus {
        UIApplication.shared.backgroundRefreshStatus
    }
}

extension UIBackgroundRefreshStatus {
    var explanation: String {
        switch self {
        case .available: "Povoleno"
        case .denied: "Vypnuto v Nastavení"
        case .restricted: "Omezeno systémem"
        @unknown default: "Neznámý stav"
        }
    }

    var isUsable: Bool { self == .available }
}

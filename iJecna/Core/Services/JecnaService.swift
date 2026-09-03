import Foundation

/// Chyby, které umí vzniknout při komunikaci s Ječnou.
///
/// Web nevrací JSON ani stavové kódy chyb — přihlášení se pozná podle redirectu,
/// takže `invalidCredentials` a `sessionExpired` jsou rozlišené záměrně:
/// první znamená „zeptej se uživatele“, druhé „zkus tiše znovu přihlásit“.
enum JecnaError: LocalizedError, Equatable, Sendable {
    case invalidCredentials
    case sessionExpired
    case network(String)
    /// Web se změnil a parser mu přestal rozumět.
    case parsing(String)
    /// Stránka existuje, ale tenhle student na ni nemá právo (např. výuční listy mimo 4. ročník).
    case notAvailable
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Nesprávné jméno nebo heslo."
        case .sessionExpired: "Přihlášení vypršelo."
        case .network(let detail): "Nepodařilo se spojit se školním webem. \(detail)"
        case .parsing: "Školní web vrátil něco neočekávaného."
        case .notAvailable: "Tahle stránka pro tebe není dostupná."
        case .offline: "Nejsi připojený k internetu."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials: "Zkontroluj přihlašovací údaje a zkus to znovu."
        case .sessionExpired: "Přihlas se prosím znovu."
        case .network, .offline: "Zkus to za chvíli znovu."
        case .parsing: "Nejspíš se změnil školní web. Zkus aktualizovat aplikaci."
        case .notAvailable: nil
        }
    }

    var symbolName: String {
        switch self {
        case .invalidCredentials, .sessionExpired: "person.badge.key"
        case .network, .offline: "wifi.exclamationmark"
        case .parsing: "exclamationmark.triangle"
        case .notAvailable: "lock"
        }
    }
}

/// Rozhraní ke školním datům.
///
/// Makety i budoucí skutečný scraper spsejecna.cz implementují tenhle protokol,
/// takže UI se při přechodu na ostrá data nemění.
protocol JecnaService: Sendable {
    func logIn(username: String, password: String) async throws
    func logOut() async
    func isLoggedIn() async -> Bool

    func grades(year: SchoolYear, half: SchoolYearHalf) async throws -> GradesPage
    func timetable(year: SchoolYear, periodId: Int?) async throws -> TimetablePage
    func news() async throws -> [Article]
    func teachers() async throws -> [TeacherRef]
    func teacher(tag: String) async throws -> Teacher
    func rooms() async throws -> [Room]
    func profile() async throws -> Student
    func locker() async throws -> Locker?
    func notifications() async throws -> [SchoolNotification]
}

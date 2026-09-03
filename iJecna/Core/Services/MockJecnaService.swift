import Foundation

/// Maketa školního webu.
///
/// Umí simulovat latenci i chyby, aby šly odladit stavy načítání a selhání —
/// u scraperu se s nimi počítá mnohem víc než u JSON API.
actor MockJecnaService: JecnaService {

    /// Co má služba předstírat, že se pokazilo. Přepíná se v nastavení aplikace.
    enum FailureMode: String, CaseIterable, Sendable {
        case none = "Bez chyb"
        case network = "Výpadek sítě"
        case sessionExpired = "Vypršelá relace"
        case parsing = "Změněný web (parser selže)"
        case slow = "Velmi pomalá odezva"
    }

    private var loggedIn: Bool
    private var failureMode: FailureMode = .none

    /// Přihlašovací údaje, které maketa přijme. Cokoli jiného vrátí `invalidCredentials`.
    static let demoUsername = "novotny"
    static let demoPassword = "jecna"

    init(startLoggedIn: Bool = false) {
        self.loggedIn = startLoggedIn
    }

    func setFailureMode(_ mode: FailureMode) {
        failureMode = mode
    }

    // MARK: - Přihlášení

    func logIn(username: String, password: String) async throws {
        try await delay(0.9)
        if failureMode == .network { throw JecnaError.network("Časový limit vypršel.") }

        // Ječna nerozlišuje velikost písmen v uživatelském jméně a bere i plný e-mail.
        let normalized = username
            .lowercased()
            .replacingOccurrences(of: "@spsejecna.cz", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard normalized == Self.demoUsername, password == Self.demoPassword else {
            throw JecnaError.invalidCredentials
        }
        loggedIn = true
    }

    func logOut() async {
        loggedIn = false
    }

    func isLoggedIn() async -> Bool { loggedIn }

    // MARK: - Data

    func grades(year: SchoolYear, half: SchoolYearHalf) async throws -> GradesPage {
        try await guarded(0.7) { MockData.gradesPage(year: year, half: half) }
    }

    func timetable(year: SchoolYear, periodId: Int?) async throws -> TimetablePage {
        try await guarded(0.6) { MockData.timetablePage(year: year, periodId: periodId) }
    }

    func news() async throws -> [Article] {
        try await guarded(0.5) { MockData.news }
    }

    func teachers() async throws -> [TeacherRef] {
        try await guarded(0.4) { MockData.teacherRefs }
    }

    func teacher(tag: String) async throws -> Teacher {
        try await guarded(0.5) {
            guard let teacher = MockData.teacherDetails[tag] else {
                // Učitelé bez ručně dopsaného detailu dostanou rozumný základ.
                guard let ref = MockData.teacher(tag) else { throw JecnaError.notAvailable }
                return Teacher(
                    tag: ref.tag,
                    fullName: ref.fullName,
                    username: ref.tag.lowercased(),
                    schoolMail: "\(ref.tag.lowercased())@spsejecna.cz",
                    phoneNumbers: [],
                    cabinet: nil,
                    tutorOfClass: nil,
                    consultationHours: nil
                )
            }
            return teacher
        }
    }

    func rooms() async throws -> [Room] {
        try await guarded(0.4) { MockData.rooms }
    }

    func profile() async throws -> Student {
        try await guarded(0.5) { MockData.student }
    }

    func locker() async throws -> Locker? {
        try await guarded(0.3) { MockData.locker }
    }

    func notifications() async throws -> [SchoolNotification] {
        try await guarded(0.4) { MockData.notifications }
    }

    // MARK: - Pomocné

    private func guarded<T: Sendable>(
        _ seconds: Double,
        _ produce: () throws -> T
    ) async throws -> T {
        guard loggedIn else { throw JecnaError.sessionExpired }
        try await delay(seconds)

        switch failureMode {
        case .none, .slow: break
        case .network: throw JecnaError.network("Server neodpovídá.")
        case .sessionExpired:
            loggedIn = false
            throw JecnaError.sessionExpired
        case .parsing: throw JecnaError.parsing("Nenalezen očekávaný element tabulky.")
        }

        return try produce()
    }

    private func delay(_ seconds: Double) async throws {
        let multiplier: Double = failureMode == .slow ? 5 : 1
        try? await Task.sleep(for: .seconds(seconds * multiplier))
    }
}

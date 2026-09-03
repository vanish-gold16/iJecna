import Foundation

/// Skutečný přístup ke školnímu webu.
///
/// Spojuje přenosovou vrstvu s parsery a naplňuje stejný protokol jako maketa,
/// takže obrazovky se přechodem na ostrá data nemění.
///
/// Je to aktér záměrně: parsování HTML je synchronní práce a nesmí běžet
/// na hlavním vlákně, jinak by se při každém načtení seklo rolování.
actor WebJecnaService: JecnaService {

    private let client: JecnaHTTPClient
    private let credentialStore: CredentialStore

    /// Uživatelské jméno je potřeba do adresy profilu, ne jen k přihlášení.
    private var username: String?

    init(
        client: JecnaHTTPClient = JecnaHTTPClient(),
        credentialStore: CredentialStore = CredentialStore()
    ) {
        self.client = client
        self.credentialStore = credentialStore
    }

    // MARK: - Přihlášení

    func logIn(username: String, password: String) async throws {
        let credentials = JecnaCredentials(username: username, password: password)
        try await client.logIn(credentials)

        self.username = credentials.username
        // Heslo se ukládá až po úspěšném přihlášení, ať v Klíčence neleží nepoužitelný údaj.
        try? credentialStore.save(credentials)
    }

    func logOut() async {
        await client.logOut()
        credentialStore.delete()
        username = nil
    }

    /// Po startu aplikace relace neexistuje — pokusíme se ji obnovit z Klíčenky.
    func signedInUsername() async -> String? {
        guard let credentials = credentialStore.load() else { return nil }

        if await client.isLoggedIn() {
            username = credentials.username
            return credentials.username
        }

        do {
            try await client.logIn(credentials)
            username = credentials.username
            return credentials.username
        } catch {
            // Neplatné uložené heslo nemá smysl zkoušet pořád dokola.
            if case JecnaError.invalidCredentials = error { credentialStore.delete() }
            return nil
        }
    }

    // MARK: - Data

    func grades(year: SchoolYear, half: SchoolYearHalf) async throws -> GradesPage {
        let html = try await client.html(.grades(year: year, half: half))
        return try parse { try GradesPageParser.parse(html, fallbackYear: year, fallbackHalf: half) }
    }

    func timetable(year: SchoolYear, periodId: Int?) async throws -> TimetablePage {
        let html = try await client.html(.timetable(year: year, periodId: periodId))
        return try parse { try TimetablePageParser.parse(html, fallbackYear: year) }
    }

    func news() async throws -> [Article] {
        let html = try await client.html(.news)
        return try parse { try NewsPageParser.parse(html) }
    }

    func teachers() async throws -> [TeacherRef] {
        let html = try await client.html(.teachers)
        return try parse { try TeachersPageParser.parse(html) }
    }

    func notifications() async throws -> [SchoolNotification] {
        let html = try await client.html(.notifications)
        return try parse { try NotificationsPageParser.parse(html) }
    }

    func profile() async throws -> Student {
        // Adresu profilu tvoří uživatelské jméno; bez přihlášení ho neznáme.
        guard let username = username ?? credentialStore.load()?.username else {
            throw JecnaError.sessionExpired
        }
        let html = try await client.html(.student(username: username))
        return try parse { try StudentProfileParser.parse(html, username: username) }
    }

    func teacher(tag: String) async throws -> Teacher {
        let html = try await client.html(.teacher(tag: tag))
        return try parse { try TeacherParser.parse(html, tag: tag) }
    }

    func rooms() async throws -> [Room] {
        let html = try await client.html(.rooms)
        return try parse { try RoomsPageParser.parse(html) }
    }

    func locker() async throws -> Locker? {
        let html = try await client.html(.locker)
        return try parse { try LockerPageParser.parse(html) }
    }

    // MARK: - Pomocné

    /// Chyby parsování převádí na typ, se kterým pracuje zbytek aplikace.
    private func parse<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as HTMLParseError {
            throw error.asJecnaError
        } catch let error as JecnaError {
            throw error
        } catch {
            throw JecnaError.parsing(error.localizedDescription)
        }
    }
}

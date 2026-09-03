import Foundation
import Observation
import SwiftUI

/// Kdo je přihlášený.
enum SessionState: Equatable {
    case signedOut
    case signingIn
    case signedIn(username: String)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

/// Jediný zdroj pravdy pro celou aplikaci.
///
/// V maketě drží mock službu; při přechodu na ostrá data se vymění jen `service`.
@MainActor
@Observable
final class AppModel {

    // MARK: - Závislosti

    let service: JecnaService

    // MARK: - Relace

    var session: SessionState = .signedOut
    var signInError: JecnaError?

    // MARK: - Výběr období

    var selectedYear: SchoolYear = .current {
        didSet { guard oldValue != selectedYear else { return }; invalidatePeriodScopedData() }
    }
    var selectedHalf: SchoolYearHalf = .current {
        didSet { guard oldValue != selectedHalf else { return }; invalidatePeriodScopedData() }
    }
    var selectedTimetablePeriodId: Int?

    var isViewingCurrentPeriod: Bool {
        selectedYear == .current && selectedHalf == .current
    }

    // MARK: - Data

    var grades: LoadState<GradesPage> = .idle
    var timetable: LoadState<TimetablePage> = .idle
    var news: LoadState<[Article]> = .idle
    var teachers: LoadState<[TeacherRef]> = .idle
    var rooms: LoadState<[Room]> = .idle
    var profile: LoadState<Student> = .idle
    var locker: LoadState<Locker?> = .idle
    var notifications: LoadState<[SchoolNotification]> = .idle

    // MARK: - Nastavení

    var settings = AppSettings()

    /// Sleduje, které známky už uživatel viděl — základ pro upozornění.
    var newGrades = NewGradesTracker()

    /// Maketa: po prvním úspěšném načtení označí několik posledních známek
    /// za nepřečtené, aby šlo vidět, jak vypadá upozornění na nové známky.
    /// V ostré verzi tohle zmizí, rozdíl bude vycházet ze skutečných dat.
    var simulatesFreshGrades = true

    /// Běžíme na maketě? Ovlivňuje jen ladicí nástroje v nastavení.
    let isUsingMockData: Bool

    init(service: JecnaService) {
        self.service = service
        self.isUsingMockData = service is MockJecnaService
        // Předstírat nové známky má smysl jen u makety; u skutečných dat
        // rozdíl vychází z toho, co student opravdu ještě neviděl.
        self.simulatesFreshGrades = isUsingMockData
    }

    /// Obnoví relaci po startu aplikace — heslo je v Klíčence.
    func restoreSession() async {
        guard let username = await service.signedInUsername() else {
            session = .signedOut
            return
        }
        session = .signedIn(username: username)
        await loadEssentials()
    }

    // MARK: - Přihlášení

    func signIn(username: String, password: String) async {
        session = .signingIn
        signInError = nil
        do {
            try await service.logIn(username: username, password: password)
            session = .signedIn(username: await service.signedInUsername() ?? username)
            Haptics.notify(.success)
            await loadEssentials()
        } catch let error as JecnaError {
            signInError = error
            session = .signedOut
            Haptics.notify(.error)
        } catch {
            signInError = .network(error.localizedDescription)
            session = .signedOut
        }
    }

    func signOut() async {
        await service.logOut()
        session = .signedOut
        grades = .idle
        timetable = .idle
        news = .idle
        teachers = .idle
        rooms = .idle
        profile = .idle
        locker = .idle
        notifications = .idle
    }

    /// Co se načítá hned po přihlášení — jen to, co je vidět na první obrazovce.
    func loadEssentials() async {
        async let gradesTask: Void = loadGrades()
        async let timetableTask: Void = loadTimetable()
        async let profileTask: Void = loadProfile()
        _ = await (gradesTask, timetableTask, profileTask)
    }

    // MARK: - Načítání

    func loadGrades(force: Bool = false) async {
        guard force || grades.isIdle else { return }
        grades.markRefreshing()
        let year = selectedYear
        let half = selectedHalf
        do {
            let page = try await service.grades(year: year, half: half)
            // Nová data mohla dorazit po přepnutí období — starou odpověď zahodíme.
            guard year == selectedYear, half == selectedHalf else { return }
            grades = .loaded(page)
            if isViewingCurrentPeriod {
                newGrades.register(page)
                if simulatesFreshGrades {
                    simulatesFreshGrades = false
                    newGrades.simulateNewGrades(from: page)
                }
            }
        } catch let error as JecnaError {
            handle(error, into: &grades)
        } catch {
            grades = .failed(.network(error.localizedDescription))
        }
    }

    func loadTimetable(force: Bool = false) async {
        guard force || timetable.isIdle else { return }
        timetable.markRefreshing()
        do {
            let page = try await service.timetable(year: selectedYear, periodId: selectedTimetablePeriodId)
            timetable = .loaded(page)
            // Server sám určí, kterou variantu ukázal; bez toho by přepínač
            // po načtení neukazoval, co je na obrazovce.
            if selectedTimetablePeriodId == nil {
                selectedTimetablePeriodId = page.periodOptions.first(where: \.isSelected)?.id
            }
        } catch let error as JecnaError {
            handle(error, into: &timetable)
        } catch {
            timetable = .failed(.network(error.localizedDescription))
        }
    }

    func loadNews(force: Bool = false) async {
        guard force || news.isIdle else { return }
        news.markRefreshing()
        do { news = .loaded(try await service.news()) }
        catch let error as JecnaError { handle(error, into: &news) }
        catch { news = .failed(.network(error.localizedDescription)) }
    }

    func loadTeachers(force: Bool = false) async {
        guard force || teachers.isIdle else { return }
        teachers.markRefreshing()
        do { teachers = .loaded(try await service.teachers()) }
        catch let error as JecnaError { handle(error, into: &teachers) }
        catch { teachers = .failed(.network(error.localizedDescription)) }
    }

    func loadRooms(force: Bool = false) async {
        guard force || rooms.isIdle else { return }
        rooms.markRefreshing()
        do { rooms = .loaded(try await service.rooms()) }
        catch let error as JecnaError { handle(error, into: &rooms) }
        catch { rooms = .failed(.network(error.localizedDescription)) }
    }

    func loadProfile(force: Bool = false) async {
        guard force || profile.isIdle else { return }
        profile.markRefreshing()
        do { profile = .loaded(try await service.profile()) }
        catch let error as JecnaError { handle(error, into: &profile) }
        catch { profile = .failed(.network(error.localizedDescription)) }
    }

    func loadLocker(force: Bool = false) async {
        guard force || locker.isIdle else { return }
        locker.markRefreshing()
        do { locker = .loaded(try await service.locker()) }
        catch let error as JecnaError { handle(error, into: &locker) }
        catch { locker = .failed(.network(error.localizedDescription)) }
    }

    func loadNotifications(force: Bool = false) async {
        guard force || notifications.isIdle else { return }
        notifications.markRefreshing()
        do { notifications = .loaded(try await service.notifications()) }
        catch let error as JecnaError { handle(error, into: &notifications) }
        catch { notifications = .failed(.network(error.localizedDescription)) }
    }

    /// Obnova gestem stažení dolů na hlavní obrazovce.
    func refreshDashboard() async {
        async let gradesTask: Void = loadGrades(force: true)
        async let timetableTask: Void = loadTimetable(force: true)
        _ = await (gradesTask, timetableTask)
    }

    // MARK: - Odvozená data

    /// Předměty seřazené podle nastaveného pravidla.
    func sortedSubjects(_ page: GradesPage) -> [Subject] {
        switch settings.subjectSorting {
        case .alphabetical:
            page.subjects.sorted { $0.name.full.localizedStandardCompare($1.name.full) == .orderedAscending }
        case .worstAverage:
            page.subjects.sorted { ($0.average ?? -1) > ($1.average ?? -1) }
        case .recentActivity:
            page.subjects.sorted { ($0.latestGradeDate ?? .distantPast) > ($1.latestGradeDate ?? .distantPast) }
        }
    }

    /// Aktuální nebo nejbližší hodina — pro hlavní obrazovku i pro pruh nad tab barem.
    var currentMoment: LessonMoment? {
        guard let page = timetable.value else { return nil }
        return page.timetable.moment(group: profile.value?.primaryGroup)
    }

    /// Poslední známky napříč předměty, nejnovější první.
    func recentGrades(limit: Int = 6) -> [(subject: Subject, grade: Grade)] {
        guard let page = grades.value else { return [] }
        return page.subjects
            .flatMap { subject in subject.allGrades.map { (subject, $0) } }
            .sorted { ($0.1.receivedAt ?? .distantPast) > ($1.1.receivedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Chyby

    private func handle<T>(_ error: JecnaError, into state: inout LoadState<T>) {
        state = .failed(error)
        // Vypršelá relace je jediná chyba, která má vrátit uživatele na přihlášení.
        if error == .sessionExpired {
            session = .signedOut
        }
    }

    private func invalidatePeriodScopedData() {
        grades = .idle
        timetable = .idle
        selectedTimetablePeriodId = nil
        Task { await loadGrades(); await loadTimetable() }
    }
}

// MARK: - Nastavení

@Observable
final class AppSettings {
    enum SubjectSorting: String, CaseIterable, Identifiable {
        case alphabetical, worstAverage, recentActivity

        var id: String { rawValue }

        var title: String {
            switch self {
            case .alphabetical: "Podle abecedy"
            case .worstAverage: "Podle nejhoršího průměru"
            case .recentActivity: "Podle poslední známky"
            }
        }
    }

    var subjectSorting: SubjectSorting = .recentActivity
    var notifyOnNewGrade = true
    var notifyOnNewNotification = true
    var notifyOnTimetableChange = false
    var notifyOnNews = false
    /// Upozornění se posílají jen ve školních hodinách, ať telefon nepíská v noci.
    var quietHoursEnabled = true
    var backgroundRefreshEnabled = true
    var showNSymbolInAverages = false
    var simulatedFailure: MockJecnaService.FailureMode = .none
}

// MARK: - Sledování nových známek

/// Pamatuje si, které známky uživatel už viděl.
///
/// Tohle je jádro upozornění na nové známky: aplikace na pozadí stáhne stránku
/// se známkami, porovná id s uloženými a rozdíl ohlásí lokální notifikací.
/// Ječna žádné „přečteno“ nezná, takže si stav musíme držet sami.
@Observable
final class NewGradesTracker {
    private static let storageKey = "seenGradeIds"

    private(set) var seenIds: Set<Int>
    /// Známky, které přibyly od posledního potvrzení uživatelem.
    private(set) var unseenIds: Set<Int> = []

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.array(forKey: Self.storageKey) as? [Int] ?? []
        seenIds = Set(stored)
    }

    var hasUnseen: Bool { !unseenIds.isEmpty }
    var unseenCount: Int { unseenIds.count }

    func isNew(_ grade: Grade) -> Bool { unseenIds.contains(grade.id) }

    /// Porovná čerstvě načtenou stránku s uloženým stavem.
    func register(_ page: GradesPage) {
        let ids = Set(page.subjects.flatMap { $0.allGrades.map(\.id) })

        // První spuštění: všechno bereme jako viděné, jinak by uživatele zavalilo.
        guard !seenIds.isEmpty else {
            seenIds = ids
            persist()
            return
        }

        unseenIds.formUnion(ids.subtracting(seenIds))
    }

    /// Uživatel si známky prohlédl.
    func markAllSeen() {
        seenIds.formUnion(unseenIds)
        unseenIds.removeAll()
        persist()
    }

    func markSeen(_ grade: Grade) {
        unseenIds.remove(grade.id)
        seenIds.insert(grade.id)
        persist()
    }

    private func persist(defaults: UserDefaults = .standard) {
        defaults.set(Array(seenIds), forKey: Self.storageKey)
    }

    /// Jen pro maketu — nasimuluje, že tři nejnovější známky jsou nové.
    func simulateNewGrades(from page: GradesPage, count: Int = 3) {
        let newest = page.subjects
            .flatMap(\.allGrades)
            .sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
            .prefix(count)
            .map(\.id)
        unseenIds = Set(newest)
        seenIds.subtract(unseenIds)
    }
}

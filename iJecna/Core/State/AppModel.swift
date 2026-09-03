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
    /// Mimořádný rozvrh z cizí služby. Výpadek nesmí shodit řádný rozvrh,
    /// proto se chyba nikde nevnucuje — jen se změny neukážou.
    var substitutions: LoadState<SubstitutionSchedule> = .idle

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

        // Suplování se ptá až po profilu — potřebuje znát třídu.
        await loadSubstitutions()
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

    /// Načte mimořádný rozvrh.
    ///
    /// Chyba se drží stranou: cizí služba může být kdykoli mimo provoz
    /// a řádný rozvrh na ní nesmí být závislý.
    func loadSubstitutions(force: Bool = false) async {
        guard settings.substitutionsEnabled else {
            substitutions = .idle
            return
        }
        guard force || substitutions.isIdle else { return }

        // Maketa nesmí chodit na síť.
        if isUsingMockData {
            substitutions = .loaded(MockData.substitutionSchedule)
            return
        }

        guard let className = profile.value?.className else { return }

        substitutions.markRefreshing()
        let service = SubstitutionService(provider: settings.substitutionProviderURL)
        do {
            substitutions = .loaded(try await service.schedule(for: className))
        } catch let error as SubstitutionError {
            substitutions = .failed(.network(error.errorDescription ?? "neznámá chyba"))
        } catch {
            substitutions = .failed(.network(error.localizedDescription))
        }
    }

    /// Změny pro daný den, pokud je funkce zapnutá a data dorazila.
    func substitutionDay(on date: Date) -> SubstitutionDay? {
        guard settings.substitutionsEnabled else { return nil }
        return substitutions.value?.day(on: date)
    }

    /// Obnova gestem stažení dolů na hlavní obrazovce.
    func refreshDashboard() async {
        async let gradesTask: Void = loadGrades(force: true)
        async let timetableTask: Void = loadTimetable(force: true)
        _ = await (gradesTask, timetableTask)
        await loadSubstitutions(force: true)
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

/// Uživatelská nastavení.
///
/// Ukládají se do `UserDefaults`; nic z toho není citlivé a po restartu se to
/// hodí mít. Heslo je jinde, v Klíčence.
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

    var subjectSorting: SubjectSorting { didSet { save() } }
    var notifyOnNewGrade: Bool { didSet { save() } }
    var notifyOnNewNotification: Bool { didSet { save() } }
    var notifyOnTimetableChange: Bool { didSet { save() } }
    var notifyOnNews: Bool { didSet { save() } }
    /// Upozornění se posílají jen ve školních hodinách, ať telefon nepíská v noci.
    var quietHoursEnabled: Bool { didSet { save() } }
    var backgroundRefreshEnabled: Bool { didSet { save() } }
    var showNSymbolInAverages: Bool { didSet { save() } }

    /// Mimořádný rozvrh se tahá z cizí služby, proto jde vypnout.
    var substitutionsEnabled: Bool { didSet { save() } }
    /// Vlastní adresa poskytovatele; prázdná znamená výchozí.
    var substitutionProvider: String { didSet { save() } }

    /// Jen pro maketu, neukládá se.
    @ObservationIgnored var simulatedFailure: MockJecnaService.FailureMode = .none

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        subjectSorting = SubjectSorting(rawValue: defaults.string(forKey: Key.subjectSorting) ?? "")
            ?? .recentActivity
        notifyOnNewGrade = defaults.bool(forKey: Key.notifyOnNewGrade, default: true)
        notifyOnNewNotification = defaults.bool(forKey: Key.notifyOnNewNotification, default: true)
        notifyOnTimetableChange = defaults.bool(forKey: Key.notifyOnTimetableChange, default: false)
        notifyOnNews = defaults.bool(forKey: Key.notifyOnNews, default: false)
        quietHoursEnabled = defaults.bool(forKey: Key.quietHours, default: true)
        backgroundRefreshEnabled = defaults.bool(forKey: Key.backgroundRefresh, default: true)
        showNSymbolInAverages = defaults.bool(forKey: Key.showN, default: false)
        substitutionsEnabled = defaults.bool(forKey: Key.substitutionsEnabled, default: true)
        substitutionProvider = defaults.string(forKey: Key.substitutionProvider) ?? ""

        isLoading = false
    }

    /// Adresa poskytovatele, se kterou se má pracovat.
    var substitutionProviderURL: URL {
        let trimmed = substitutionProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else {
            return SubstitutionService.defaultProvider
        }
        return url
    }

    private func save() {
        // V `init` se hodnoty nastavují jedna po druhé; zapisovat je zpátky
        // by bylo zbytečné.
        guard !isLoading else { return }

        defaults.set(subjectSorting.rawValue, forKey: Key.subjectSorting)
        defaults.set(notifyOnNewGrade, forKey: Key.notifyOnNewGrade)
        defaults.set(notifyOnNewNotification, forKey: Key.notifyOnNewNotification)
        defaults.set(notifyOnTimetableChange, forKey: Key.notifyOnTimetableChange)
        defaults.set(notifyOnNews, forKey: Key.notifyOnNews)
        defaults.set(quietHoursEnabled, forKey: Key.quietHours)
        defaults.set(backgroundRefreshEnabled, forKey: Key.backgroundRefresh)
        defaults.set(showNSymbolInAverages, forKey: Key.showN)
        defaults.set(substitutionsEnabled, forKey: Key.substitutionsEnabled)
        defaults.set(substitutionProvider, forKey: Key.substitutionProvider)
    }

    private enum Key {
        static let subjectSorting = "settings.subjectSorting"
        static let notifyOnNewGrade = "settings.notifyOnNewGrade"
        static let notifyOnNewNotification = "settings.notifyOnNewNotification"
        static let notifyOnTimetableChange = "settings.notifyOnTimetableChange"
        static let notifyOnNews = "settings.notifyOnNews"
        static let quietHours = "settings.quietHours"
        static let backgroundRefresh = "settings.backgroundRefresh"
        static let showN = "settings.showNSymbolInAverages"
        static let substitutionsEnabled = "settings.substitutionsEnabled"
        static let substitutionProvider = "settings.substitutionProvider"
    }
}

private extension UserDefaults {
    /// `bool(forKey:)` vrací `false` i pro nenastavený klíč, což se plete
    /// s přepínačem, který má být ve výchozím stavu zapnutý.
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
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

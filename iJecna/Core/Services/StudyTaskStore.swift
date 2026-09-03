import Foundation
import Observation
import UserNotifications

/// Úložiště úkolů a testů.
///
/// Data existují jen na tomhle zařízení — ukládají se do JSON souboru v Application Support.
/// Za školní rok jich vznikne řádově stovky, takže se celá kolekce drží v paměti;
/// SwiftData by sem přinesl schéma a migrace, aniž by co získal.
@MainActor
@Observable
final class StudyTaskStore {

    private(set) var tasks: [StudyTask] = []
    private(set) var lastError: String?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let scheduler: NotificationScheduler
    @ObservationIgnored private var quietHours: Bool

    init(scheduler: NotificationScheduler, quietHours: Bool = true, directory: URL? = nil) {
        self.scheduler = scheduler
        self.quietHours = quietHours

        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iJecna", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("study-tasks.json")

        load()
    }

    // MARK: - Dotazy

    /// Záznamy pro daný den, seřazené podle hodiny v rozvrhu.
    func tasks(on date: Date) -> [StudyTask] {
        let day = Date.startOfSchoolDay(date)
        return tasks
            .filter { $0.dueDate == day }
            .sorted { lhs, rhs in
                // Nezařazené (bez hodiny) až za těmi navázanými na konkrétní hodinu.
                (lhs.periodNumber ?? Int.max, lhs.createdAt) < (rhs.periodNumber ?? Int.max, rhs.createdAt)
            }
    }

    /// Záznamy navázané na konkrétní hodinu daného dne.
    func tasks(on date: Date, periodNumber: Int) -> [StudyTask] {
        tasks(on: date).filter { $0.periodNumber == periodNumber }
    }

    /// Záznamy pro hodinový blok, který se táhne přes víc hodin.
    func tasks(on date: Date, periodRange: ClosedRange<Int>) -> [StudyTask] {
        tasks(on: date).filter { task in
            guard let period = task.periodNumber else { return false }
            return periodRange.contains(period)
        }
    }

    /// Nesplněné záznamy po termínu, od nejstaršího.
    var overdue: [StudyTask] {
        tasks.filter { $0.isOverdue() }.sorted { $0.dueDate < $1.dueDate }
    }

    /// Nesplněné záznamy na dnešek.
    var dueToday: [StudyTask] {
        tasks.filter { !$0.isDone && $0.isDueToday() }
    }

    /// Nadcházející testy, nejbližší první.
    var upcomingTests: [StudyTask] {
        tasks
            .filter { $0.kind == .test && !$0.isDone && $0.daysUntilDue() >= 0 }
            .sorted { $0.dueDate < $1.dueDate }
    }

    /// Co je potřeba udělat v nejbližších dnech — podklad pro hlavní obrazovku.
    func dueSoon(withinDays days: Int = 7) -> [StudyTask] {
        tasks
            .filter { !$0.isDone && (0...days).contains($0.daysUntilDue()) }
            .sorted { ($0.dueDate, $0.periodNumber ?? Int.max) < ($1.dueDate, $1.periodNumber ?? Int.max) }
    }

    /// Číslo na záložce: co je po termínu nebo na dnešek.
    var badgeCount: Int {
        overdue.count + dueToday.count
    }

    func task(id: UUID) -> StudyTask? {
        tasks.first { $0.id == id }
    }

    // MARK: - Změny

    func add(_ task: StudyTask) {
        var task = task
        task.reminderDate = resolvedReminderDate(for: task)
        tasks.append(task)
        persist()
        Task { await scheduler.sync(task, quietHours: quietHours) }
    }

    func update(_ task: StudyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var task = task
        task.reminderDate = resolvedReminderDate(for: task)
        tasks[index] = task
        persist()
        Task { await scheduler.sync(task, quietHours: quietHours) }
    }

    func delete(_ task: StudyTask) {
        tasks.removeAll { $0.id == task.id }
        persist()
        scheduler.cancel(task.id)
    }

    func delete(ids: Set<UUID>) {
        tasks.removeAll { ids.contains($0.id) }
        persist()
        for id in ids { scheduler.cancel(id) }
    }

    func toggleDone(_ task: StudyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
        tasks[index].completedAt = tasks[index].isDone ? .now : nil
        persist()

        let updated = tasks[index]
        // Splněný úkol už nemá o čem upozorňovat; odškrtnutý se naplánuje zpět.
        Task { await scheduler.sync(updated, quietHours: quietHours) }
    }

    /// Smaže splněné záznamy starší než zadaný počet dní.
    func clearCompleted(olderThanDays days: Int = 0) {
        let cutoff = Calendar.prague.date(byAdding: .day, value: -days, to: .now) ?? .now
        let removed = tasks.filter { $0.isDone && ($0.completedAt ?? .distantPast) <= cutoff }
        tasks.removeAll { task in removed.contains { $0.id == task.id } }
        persist()
        for task in removed { scheduler.cancel(task.id) }
    }

    // MARK: - Nastavení

    /// Změna tichých hodin musí přeplánovat všechna čekající upozornění.
    func setQuietHours(_ enabled: Bool) {
        guard quietHours != enabled else { return }
        quietHours = enabled
        Task { await scheduler.syncAll(tasks, quietHours: enabled) }
    }

    /// Po startu aplikace: systém si pamatuje jen naplánované požadavky,
    /// takže je po smazání aplikace nebo změně dat srovnáme se skutečností.
    func rescheduleAll() {
        Task { await scheduler.syncAll(tasks, quietHours: quietHours) }
    }

    // MARK: - Oprávnění

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await scheduler.authorizationStatus()
    }

    /// Zeptá se na oprávnění a rovnou naplánuje, co je potřeba.
    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        let granted = await scheduler.requestAuthorization()
        if granted { rescheduleAll() }
        return granted
    }

    func pendingNotificationCount() async -> Int {
        await scheduler.pendingCount()
    }

    // MARK: - Upozornění

    /// U přednastavených hodnot čas dopočítáme, u vlastního času necháme zadaný.
    private func resolvedReminderDate(for task: StudyTask) -> Date? {
        switch task.reminderPreset {
        case .none:
            return nil
        case .custom:
            return task.reminderDate
        default:
            let lessonStart = task.periodNumber.flatMap { number in
                MockData.lessonPeriods.first { $0.number == number }?.from
            }
            return task.reminderPreset.reminderDate(forDueDate: task.dueDate, lessonStart: lessonStart)
        }
    }

    // MARK: - Trvalé uložení

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            tasks = try Self.decoder.decode([StudyTask].self, from: data)
        } catch {
            // Poškozený soubor nesmí shodit aplikaci — raději začneme s prázdným seznamem
            // a chybu ukážeme v nastavení.
            lastError = "Uložené úkoly se nepodařilo načíst: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            let data = try Self.encoder.encode(tasks)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Úkoly se nepodařilo uložit: \(error.localizedDescription)"
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Ukázková data

extension StudyTaskStore {
    /// Naplní úložiště ukázkovými záznamy, aby maketa nebyla prázdná.
    /// Volá se jen když uživatel ještě nic nezaložil.
    func seedIfEmpty() {
        guard tasks.isEmpty else { return }

        let today = Date.startOfSchoolDay()
        func day(_ offset: Int) -> Date {
            Calendar.prague.date(byAdding: .day, value: offset, to: today) ?? today
        }

        let samples: [StudyTask] = [
            StudyTask(
                kind: .homework,
                title: "Příklady 3.12 – 3.18",
                details: "Goniometrické rovnice, do sešitu.",
                subjectName: "Matematika",
                subjectShort: "MAT",
                dueDate: day(1),
                periodNumber: 3,
                reminderPreset: .eveningBefore
            ),
            StudyTask(
                kind: .test,
                title: "Písemka — střídavé obvody",
                details: "Kapitoly 5 a 6, včetně fázorových diagramů.",
                subjectName: "Základy elektrotechniky",
                subjectShort: "ZEL",
                dueDate: day(4),
                periodNumber: 1,
                reminderPreset: .threeDaysBefore
            ),
            StudyTask(
                kind: .project,
                title: "Semestrálka — 2. odevzdání",
                details: "Přidat perzistenci a testy.",
                subjectName: "Programové vybavení",
                subjectShort: "PVY",
                dueDate: day(6),
                periodNumber: 1,
                reminderPreset: .eveningBefore
            ),
            StudyTask(
                kind: .homework,
                title: "Přečíst kapitolu o romantismu",
                details: "",
                subjectName: "Český jazyk a literatura",
                subjectShort: "CJL",
                dueDate: day(-1),
                periodNumber: 2,
                reminderPreset: .none
            ),
            StudyTask(
                kind: .homework,
                title: "Slovíčka unit 5",
                details: "",
                subjectName: "Anglický jazyk",
                subjectShort: "ANJ",
                dueDate: today,
                periodNumber: 4,
                isDone: true,
                completedAt: .now,
                reminderPreset: .none
            ),
        ]

        for sample in samples {
            add(sample)
        }
    }
}

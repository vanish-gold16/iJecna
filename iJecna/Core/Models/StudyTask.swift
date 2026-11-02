import Foundation

/// Druh záznamu, který si student založí sám. Tahle data nepocházejí z Ječné —
/// škola žádné úkoly ani termíny testů nezveřejňuje, takže si je vedeme lokálně.
enum StudyTaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case homework
    case test
    case project
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homework: "Úkol"
        case .test: "Test"
        case .project: "Projekt"
        case .note: "Poznámka"
        }
    }

    var symbolName: String {
        switch self {
        case .homework: "pencil.and.list.clipboard"
        case .test: "exclamationmark.triangle"
        case .project: "hammer"
        case .note: "note.text"
        }
    }

    /// Počet slovy se správným tvarem: „1 test“, „3 testy“, „5 testů“.
    func countLabel(_ count: Int) -> String {
        let forms: (one: String, few: String, many: String) = switch self {
        case .homework: ("úkol", "úkoly", "úkolů")
        case .test: ("test", "testy", "testů")
        case .project: ("projekt", "projekty", "projektů")
        case .note: ("poznámka", "poznámky", "poznámek")
        }
        let word = switch count {
        case 1: forms.one
        case 2...4: forms.few
        default: forms.many
        }
        return "\(count) \(word)"
    }

    /// Pořadí podle důležitosti — test se nesmí ztratit za poznámkou.
    static let byImportance: [StudyTaskKind] = [.test, .project, .homework, .note]

    /// Testy chceme připomenout s předstihem, úkoly stačí večer předtím.
    var defaultReminder: ReminderPreset {
        switch self {
        case .test: .threeDaysBefore
        case .homework, .project: .eveningBefore
        case .note: .none
        }
    }
}

/// Přednastavené časy upozornění. Počítají se vůči dni, na který je záznam navázaný.
enum ReminderPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case eveningBefore
    case morningOf
    case hourBeforeLesson
    case threeDaysBefore
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Bez upozornění"
        case .eveningBefore: "Večer předem (18:00)"
        case .morningOf: "Ráno v den (7:00)"
        case .hourBeforeLesson: "Hodinu před vyučováním"
        case .threeDaysBefore: "Tři dny předem (18:00)"
        case .custom: "Vlastní čas"
        }
    }

    /// Vypočítá čas upozornění.
    ///
    /// - Parameters:
    ///   - dueDate: den, na který je záznam navázaný (začátek dne).
    ///   - lessonStart: začátek konkrétní vyučovací hodiny, pokud je známý.
    func reminderDate(
        forDueDate dueDate: Date,
        lessonStart: TimeOfDay?,
        calendar: Calendar = .prague
    ) -> Date? {
        switch self {
        case .none, .custom:
            return nil
        case .eveningBefore:
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dueDate) else { return nil }
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay)
        case .morningOf:
            return calendar.date(bySettingHour: 7, minute: 0, second: 0, of: dueDate)
        case .hourBeforeLesson:
            // Bez konkrétní hodiny nemá „hodinu předem“ smysl — spadneme na ráno v den.
            guard let lessonStart else {
                return calendar.date(bySettingHour: 7, minute: 0, second: 0, of: dueDate)
            }
            let start = calendar.date(
                bySettingHour: lessonStart.hour,
                minute: lessonStart.minute,
                second: 0,
                of: dueDate
            )
            return start.flatMap { calendar.date(byAdding: .hour, value: -1, to: $0) }
        case .threeDaysBefore:
            guard let day = calendar.date(byAdding: .day, value: -3, to: dueDate) else { return nil }
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)
        }
    }
}

/// Úkol, test nebo poznámka navázaná na konkrétní den a případně i na konkrétní
/// vyučovací hodinu v rozvrhu.
///
/// Ukládá se jen na tomhle zařízení. Ječna o těchhle datech neví a nikam se neodesílají.
struct StudyTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: StudyTaskKind
    var title: String
    var details: String
    /// Plný název předmětu. Kotva nezávislá na rozvrhu — přežije i změnu rozvrhu.
    var subjectName: String
    var subjectShort: String?
    /// Den, ke kterému se záznam váže. Vždy začátek dne v pražském čase.
    var dueDate: Date
    /// Číslo vyučovací hodiny, pokud je záznam navázaný na konkrétní hodinu.
    var periodNumber: Int?
    var isDone: Bool
    var completedAt: Date?
    var createdAt: Date
    var reminderPreset: ReminderPreset
    /// Konkrétní čas upozornění. U přednastavených hodnot dopočítaný, u `.custom` zadaný ručně.
    var reminderDate: Date?

    init(
        id: UUID = UUID(),
        kind: StudyTaskKind = .homework,
        title: String = "",
        details: String = "",
        subjectName: String = "",
        subjectShort: String? = nil,
        dueDate: Date = Date.startOfSchoolDay(),
        periodNumber: Int? = nil,
        isDone: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        reminderPreset: ReminderPreset = .eveningBefore,
        reminderDate: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.details = details
        self.subjectName = subjectName
        self.subjectShort = subjectShort
        self.dueDate = dueDate
        self.periodNumber = periodNumber
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.reminderPreset = reminderPreset
        self.reminderDate = reminderDate
    }

    var displaySubject: String {
        subjectShort ?? subjectName
    }

    var hasReminder: Bool {
        reminderPreset != .none && reminderDate != nil
    }

    /// Upozornění, které už proběhlo, nemá smysl plánovat znovu.
    var hasPendingReminder: Bool {
        guard let reminderDate, !isDone else { return false }
        return reminderDate > .now
    }

    func isOverdue(now: Date = .now) -> Bool {
        !isDone && dueDate < Date.startOfSchoolDay(now)
    }

    func isDueToday(now: Date = .now) -> Bool {
        dueDate == Date.startOfSchoolDay(now)
    }

    func daysUntilDue(now: Date = .now, calendar: Calendar = .prague) -> Int {
        calendar.dateComponents([.day], from: Date.startOfSchoolDay(now), to: dueDate).day ?? 0
    }

    /// Lidsky čitelný termín: „dnes“, „zítra“, „za 3 dny“, „po termínu“.
    func dueDescription(now: Date = .now) -> String {
        let days = daysUntilDue(now: now)
        switch days {
        case ..<0: return days == -1 ? "včera" : "před \(-days) dny"
        case 0: return "dnes"
        case 1: return "zítra"
        case 2...4: return "za \(days) dny"
        default: return "za \(days) dnů"
        }
    }
}

/// Co student na daný den má nesplněného. Podklad pro tečky u dnů
/// a souhrn v nadpisech — aby šlo na první pohled poznat, kdy je test.
struct DayTaskSummary: Hashable, Sendable {
    private let counts: [StudyTaskKind: Int]

    init(tasks: [StudyTask]) {
        counts = tasks.filter { !$0.isDone }.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    func count(of kind: StudyTaskKind) -> Int { counts[kind] ?? 0 }

    var total: Int { counts.values.reduce(0, +) }
    var isEmpty: Bool { total == 0 }
    var hasTest: Bool { count(of: .test) > 0 }

    /// Druhy, které ten den jsou, od nejdůležitějšího.
    var kinds: [StudyTaskKind] { StudyTaskKind.byImportance.filter { count(of: $0) > 0 } }

    /// „1 test, 2 úkoly“ — pro VoiceOver a popisky.
    var description: String {
        isEmpty ? "nic" : kinds.map { $0.countLabel(count(of: $0)) }.joined(separator: ", ")
    }
}

extension Date {
    /// Začátek dne v pražském čase. Školní den se řídí školou, ne nastavením telefonu.
    static func startOfSchoolDay(_ date: Date = .now, calendar: Calendar = .prague) -> Date {
        calendar.startOfDay(for: date)
    }

    /// O kolik dní je tenhle den od dneška (zítra = 1, včera = −1).
    func schoolDaysFromToday(now: Date = .now, calendar: Calendar = .prague) -> Int {
        calendar.dateComponents(
            [.day],
            from: Date.startOfSchoolDay(now, calendar: calendar),
            to: Date.startOfSchoolDay(self, calendar: calendar)
        ).day ?? 0
    }

    /// „Dnes“, „Zítra“, „Včera“, jinak název dne („Čtvrtek“).
    func relativeDayName(now: Date = .now, calendar: Calendar = .prague) -> String {
        switch schoolDaysFromToday(now: now, calendar: calendar) {
        case 0: "Dnes"
        case 1: "Zítra"
        case -1: "Včera"
        default: DateFormatter.jecnaWeekday.string(from: self).capitalizedFirst
        }
    }

    /// Patří den do příštího týdne? V rozvrhu se pak hodí dopsat „příští týden“,
    /// jinak by se ve čtvrtek pondělí četlo jako to, které už bylo.
    func isInNextWeek(now: Date = .now, calendar: Calendar = .prague) -> Bool {
        guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now) else { return false }
        return calendar.isDate(self, equalTo: nextWeek, toGranularity: .weekOfYear)
    }

    /// Den v měsíci, „12.“
    func dayOfMonthLabel(calendar: Calendar = .prague) -> String {
        "\(calendar.component(.day, from: self))."
    }

    /// Dvoupísmenná zkratka dne včetně víkendu: „Po“ … „Ne“.
    func shortWeekdayName(calendar: Calendar = .prague) -> String {
        let weekday = calendar.component(.weekday, from: self)
        if let schoolDay = Weekday.from(calendarWeekday: weekday) { return schoolDay.shortName }
        return weekday == 1 ? "Ne" : "So"
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

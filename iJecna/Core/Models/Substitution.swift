import Foundation

/// Mimořádný rozvrh — suplování, které škola vede v tabulce mimo web Ječné.
///
/// Data nepocházejí ze `spsejecna.cz`. Tabulka leží na školním SharePointu
/// za přihlášením Microsoftem a aplikace na ni nemá jak dosáhnout. Čte se
/// proto z veřejné služby, která tabulku převádí na JSON.
/// Adresa služby jde v nastavení změnit.
struct SubstitutionStatus: Hashable, Codable, Sendable {
    /// Čas poslední aktualizace tak, jak ho služba uvádí (např. „19:00“).
    let lastUpdated: String
    /// Jak často se tabulka obnovuje, v minutách.
    let currentUpdateSchedule: Int
}

/// Změna v jedné vyučovací hodině. Text je buňka tabulky, např. `TV He(Lc)+`
/// = tělocvik, supluje He za Lc.
struct SubstitutionChange: Hashable, Codable, Sendable {
    let text: String
    let backgroundColor: String?
    let foregroundColor: String?
    /// Změna je ohlášená, ale ještě se upřesní.
    let willBeSpecified: Bool?

    /// Text bez koncového „+“, kterým tabulka značí potvrzenou změnu.
    var displayText: String {
        text.hasSuffix("+") ? String(text.dropLast()).trimmingCharacters(in: .whitespaces) : text
    }

    var isConfirmed: Bool { text.hasSuffix("+") }
}

/// Nepřítomný učitel a rozsah jeho absence.
struct TeacherAbsence: Hashable, Decodable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case wholeDay, single, range, exkurze, zastoupen, invalid
    }

    /// Rozsah hodin. Tabulka ho uvádí buď jako jedno číslo, nebo jako rozmezí.
    enum Hours: Hashable, Sendable {
        case single(Int)
        case range(from: Int, to: Int)

        var description: String {
            switch self {
            case .single(let hour): "\(hour). hodinu"
            case .range(let from, let to): "\(from).–\(to). hodinu"
            }
        }
    }

    let kind: Kind
    let teacher: String?
    let teacherCode: String
    let hours: Hours?
    /// Kdo za něj učí, když je to v tabulce uvedené.
    let substituteCode: String?
    let substituteTeacher: String?

    var id: String { "\(teacherCode)-\(kind.rawValue)-\(hours?.description ?? "")" }

    var displayName: String { teacher ?? teacherCode }

    var scopeDescription: String {
        switch kind {
        case .wholeDay: "celý den"
        case .exkurze: "exkurze"
        case .zastoupen: substituteCode.map { "zastupuje \($0)" } ?? "zastoupen"
        case .single, .range: hours?.description ?? "část dne"
        case .invalid: "neurčeno"
        }
    }
}

/// Oznámení k danému dni.
struct SubstitutionAnnouncement: Hashable, Codable, Sendable, Identifiable {
    let id: Int
    let author: String
    let createdAt: String
    let startDate: String
    let endDate: String
    let textContent: String?
    let classes: [String]

    /// Oznámení bez uvedených tříd platí pro celou školu.
    func applies(to className: String) -> Bool {
        classes.isEmpty || classes.contains { $0.caseInsensitiveCompare(className) == .orderedSame }
    }
}

/// Suplování pro jeden den.
struct SubstitutionDay: Hashable, Sendable, Identifiable {
    let date: Date
    /// Učí se ten den vůbec? Ředitelské volno má `false`.
    let isSchoolDay: Bool
    /// Změny po vyučovacích hodinách. Index odpovídá pořadí hodin od první.
    let changes: [SubstitutionChange?]
    let absences: [TeacherAbsence]
    /// Volný text ke dni, například kde se píše maturita.
    let note: String?
    let announcements: [SubstitutionAnnouncement]

    var id: Date { date }

    var hasAnything: Bool {
        changes.contains { $0 != nil } || note != nil || !announcements.isEmpty || !isSchoolDay
    }

    /// Změna pro hodinu podle jejího čísla v rozvrhu (první hodina = 1).
    func change(forPeriod number: Int) -> SubstitutionChange? {
        let index = number - 1
        guard changes.indices.contains(index) else { return nil }
        return changes[index]
    }

    /// Změna kdekoli v bloku, který se táhne přes víc hodin.
    func change(forPeriods range: ClosedRange<Int>) -> SubstitutionChange? {
        range.compactMap { change(forPeriod: $0) }.first
    }
}

/// Suplování pro konkrétní třídu.
struct SubstitutionSchedule: Hashable, Sendable {
    let status: SubstitutionStatus
    let days: [SubstitutionDay]

    func day(on date: Date, calendar: Calendar = .prague) -> SubstitutionDay? {
        let target = Date.startOfSchoolDay(date, calendar: calendar)
        return days.first { Date.startOfSchoolDay($0.date, calendar: calendar) == target }
    }

    var today: SubstitutionDay? { day(on: .now) }

    /// Dny, ke kterým je co ukázat, od nejbližšího.
    var upcoming: [SubstitutionDay] {
        let today = Date.startOfSchoolDay()
        return days
            .filter { Date.startOfSchoolDay($0.date) >= today && $0.hasAnything }
            .sorted { $0.date < $1.date }
    }
}

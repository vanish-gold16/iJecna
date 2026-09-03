import Foundation

/// Název předmětu / učitele. Ječna vrací plný název i zkratku.
struct DisplayName: Hashable, Codable, Sendable {
    let full: String
    let short: String?

    init(_ full: String, short: String? = nil) {
        self.full = full
        self.short = short
    }

    /// Zkratka, nebo iniciály odvozené z plného názvu.
    var abbreviation: String {
        if let short, !short.isEmpty { return short }
        let words = full.split(separator: " ").prefix(3)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Jedna známka.
///
/// `value` je 0…5, kde **0 znamená „N“** (nepsal/nebyl). N se nezapočítává do průměru.
/// `isSmall` je váha: malá známka = 1, velká = 2.
struct Grade: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let value: Int
    let isSmall: Bool
    let teacher: DisplayName?
    let detail: String?
    let receivedAt: Date?
    /// Část předmětu, ze které známka pochází (Teorie / Cvičení). `nil` = předmět se nedělí.
    let subjectPart: String?

    var weight: Int { isSmall ? 1 : 2 }
    var isNotWritten: Bool { value == 0 }
    var countsTowardAverage: Bool { !isNotWritten }
    var label: String { isNotWritten ? "N" : String(value) }

    var weightDescription: String { isSmall ? "malá známka" : "velká známka" }
}

/// Uzavřená známka na konci pololetí, nebo varování.
enum FinalGrade: Hashable, Codable, Sendable {
    case grade(Int)
    /// Nedostatečný prospěch.
    case gradesWarning
    /// Málo známek kvůli absenci.
    case absenceWarning
    case gradesAndAbsenceWarning
    /// Uvolněn z předmětu (U).
    case excused

    var label: String {
        switch self {
        case .grade(let value): String(value)
        case .gradesWarning: "!"
        case .absenceWarning: "?"
        case .gradesAndAbsenceWarning: "!?"
        case .excused: "U"
        }
    }

    var explanation: String {
        switch self {
        case .grade(let value): "Uzavřeno známkou \(value)"
        case .gradesWarning: "Varování — nedostatečný prospěch"
        case .absenceWarning: "Varování — málo podkladů kvůli absenci"
        case .gradesAndAbsenceWarning: "Varování — prospěch i absence"
        case .excused: "Uvolněn z předmětu"
        }
    }

    var isWarning: Bool {
        switch self {
        case .grade, .excused: false
        default: true
        }
    }
}

/// Skupina známek v rámci jedné části předmětu.
struct SubjectPart: Identifiable, Hashable, Codable, Sendable {
    /// `nil` když se předmět nedělí na části.
    let title: String?
    let grades: [Grade]

    var id: String { title ?? "__default" }
    var average: Double? { Grade.weightedAverage(of: grades) }
    var hasTitle: Bool { title != nil }
}

struct Subject: Identifiable, Hashable, Codable, Sendable {
    let name: DisplayName
    let parts: [SubjectPart]
    let finalGrade: FinalGrade?
    /// Doplněk u výsledné známky, např. „Napomenutí za neklasifikace“.
    /// Web ho přidává do popisku za slovní hodnocení.
    var finalGradeNote: String? = nil

    var id: String { name.full }
    var allGrades: [Grade] { parts.flatMap(\.grades) }
    var gradeCount: Int { allGrades.count }
    var isEmpty: Bool { allGrades.isEmpty }
    var average: Double? { Grade.weightedAverage(of: allGrades) }
    var isSplit: Bool { parts.count > 1 || parts.contains(where: \.hasTitle) }

    var latestGradeDate: Date? {
        allGrades.compactMap(\.receivedAt).max()
    }

    /// Známky seřazené od nejnovější — pro dashboard a detail.
    var gradesNewestFirst: [Grade] {
        allGrades.sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
    }
}

/// Řádek „Chování“ v tabulce známek.
struct Behaviour: Hashable, Codable, Sendable {
    let finalGrade: FinalGrade?
    let notificationIds: [Int]

    /// Tímhle názvem web označuje řádek chování v tabulce známek.
    static let subjectName = "Chování"
}

/// Celá stránka `/score/student`.
struct GradesPage: Hashable, Codable, Sendable {
    let subjects: [Subject]
    let behaviour: Behaviour
    let schoolYear: SchoolYear
    let half: SchoolYearHalf

    /// Průměr přes všechny známky všech předmětů. Není to totéž co průměr průměrů —
    /// Ječna žádný celkový průměr neposkytuje, počítáme si ho sami.
    var overallAverage: Double? {
        Grade.weightedAverage(of: subjects.flatMap(\.allGrades))
    }

    /// Nevážený průměr předmětových průměrů — blíž tomu, co student vnímá jako „vysvědčení“.
    var averageOfSubjectAverages: Double? {
        let averages = subjects.compactMap(\.average)
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    var totalGradeCount: Int { subjects.reduce(0) { $0 + $1.gradeCount } }

    func subject(named name: String) -> Subject? {
        subjects.first { $0.name.full == name }
    }
}

extension Grade {
    /// Vážený průměr: Σ(hodnota × váha) / Σváha. Známky „N“ se vynechávají.
    static func weightedAverage(of grades: [Grade]) -> Double? {
        var weightedSum = 0
        var weightSum = 0
        for grade in grades where grade.countsTowardAverage {
            weightedSum += grade.value * grade.weight
            weightSum += grade.weight
        }
        guard weightSum > 0 else { return nil }
        return Double(weightedSum) / Double(weightSum)
    }

    /// Průměr po přidání hypotetické známky — pro predikci „co když dostanu…“.
    static func weightedAverage(of grades: [Grade], adding value: Int, isSmall: Bool) -> Double? {
        var weightedSum = 0
        var weightSum = 0
        for grade in grades where grade.countsTowardAverage {
            weightedSum += grade.value * grade.weight
            weightSum += grade.weight
        }
        let weight = isSmall ? 1 : 2
        weightedSum += value * weight
        weightSum += weight
        guard weightSum > 0 else { return nil }
        return Double(weightedSum) / Double(weightSum)
    }
}

extension Double {
    /// Průměr se na Ječné píše na dvě desetinná místa.
    var averageFormatted: String { String(format: "%.2f", self) }

    /// Známka, na kterou by se průměr zaokrouhlil.
    var roundedGrade: Int { min(5, max(1, Int((self).rounded()))) }
}

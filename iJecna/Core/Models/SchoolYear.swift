import Foundation

/// Školní rok, např. 2025/2026.
///
/// Ječna kóduje rok do query parametru `schoolYearId`, kde rok 2008/2009 má id 0.
/// Viz `JecnaPeriodEncoder` v JecnaAPI.
struct SchoolYear: Hashable, Identifiable, Comparable, Codable, Sendable {
    let firstCalendarYear: Int

    init(_ firstCalendarYear: Int) {
        self.firstCalendarYear = firstCalendarYear
    }

    var secondCalendarYear: Int { firstCalendarYear + 1 }
    var id: Int { firstCalendarYear }

    /// Hodnota query parametru `schoolYearId`.
    var jecnaId: Int { firstCalendarYear - 2008 }

    var displayName: String { "\(firstCalendarYear)/\(secondCalendarYear)" }
    var shortDisplayName: String { "\(firstCalendarYear)/\(secondCalendarYear % 100)" }

    /// Prázdniny se počítají do končícího školního roku.
    static func containing(_ date: Date, calendar: Calendar = .prague) -> SchoolYear {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2026
        let month = parts.month ?? 1
        return SchoolYear(month >= 9 ? year : year - 1)
    }

    static var current: SchoolYear { containing(.now) }

    static func < (lhs: SchoolYear, rhs: SchoolYear) -> Bool {
        lhs.firstCalendarYear < rhs.firstCalendarYear
    }

    /// Roky nabízené v přepínači — od aktuálního zpět po nástup na školu.
    static func recent(count: Int = 5) -> [SchoolYear] {
        let now = current.firstCalendarYear
        return (0..<count).map { SchoolYear(now - $0) }
    }
}

/// Pololetí. Raw hodnota je přímo `schoolYearHalfId` z Ječné.
enum SchoolYearHalf: Int, CaseIterable, Identifiable, Codable, Sendable {
    case first = 21
    case second = 22

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .first: "1. pololetí"
        case .second: "2. pololetí"
        }
    }

    var shortName: String {
        switch self {
        case .first: "1. pol."
        case .second: "2. pol."
        }
    }

    /// Pololetí, ve kterém se právě nacházíme (přelom je konec ledna).
    static func containing(_ date: Date, calendar: Calendar = .prague) -> SchoolYearHalf {
        let month = calendar.component(.month, from: date)
        return (month >= 9 || month == 1) ? .first : .second
    }

    static var current: SchoolYearHalf { containing(.now) }
}

extension Calendar {
    /// Škola žije v pražském čase bez ohledu na nastavení telefonu.
    static let prague: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
        calendar.locale = Locale(identifier: "cs_CZ")
        calendar.firstWeekday = 2
        return calendar
    }()
}

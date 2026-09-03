import Foundation
import SwiftSoup

/// Chyba parsování s dost konkrétním popisem, aby šlo z hlášení poznat,
/// která část stránky se změnila.
struct HTMLParseError: LocalizedError {
    let page: String
    let detail: String

    var errorDescription: String? { "Stránku „\(page)“ se nepodařilo přečíst: \(detail)" }

    /// Převede chybu na `JecnaError`, se kterým už pracuje zbytek aplikace.
    var asJecnaError: JecnaError { .parsing("\(page): \(detail)") }
}

/// Společné nástroje pro všechny parsery stránek Ječné.
enum HTML {

    static func document(_ html: String, page: String) throws -> Document {
        do {
            return try SwiftSoup.parse(html)
        } catch {
            throw HTMLParseError(page: page, detail: "neplatné HTML (\(error))")
        }
    }

    /// První prvek odpovídající selektoru, jinak srozumitelná chyba.
    static func require(_ element: Element, _ selector: String, page: String) throws -> Element {
        guard let result = first(element, selector) else {
            throw HTMLParseError(page: page, detail: "chybí prvek „\(selector)“")
        }
        return result
    }

    static func first(_ element: Element, _ selector: String) -> Element? {
        guard let elements = try? element.select(selector) else { return nil }
        return elements.first()
    }

    static func all(_ element: Element, _ selector: String) -> [Element] {
        guard let elements = try? element.select(selector) else { return [] }
        return elements.array()
    }
}

extension Element {

    /// Text prvku s normalizovanými mezerami.
    ///
    /// Web sype `&nbsp;` mezi jméno a příjmení i do popisků, a v názvech předmětů
    /// se objevují zdvojené mezery („Tělesná  výchova“). Bez téhle normalizace
    /// by se stejná hodnota z různých stránek neshodla.
    var normalizedText: String {
        ((try? text()) ?? "").normalizedWhitespace
    }

    /// Hodnota atributu s normalizovanými mezerami, nebo `nil` když chybí či je prázdná.
    func attribute(_ name: String) -> String? {
        guard let value = try? attr(name) else { return nil }
        let normalized = value.normalizedWhitespace
        return normalized.isEmpty ? nil : normalized
    }

    /// Poslední složka cesty odkazu — tagy učitelů (`/ucitel/BC`) i kódy učeben (`/ucebna/18a`).
    func hrefLastComponent() -> String? {
        guard let href = attribute("href") else { return nil }
        return href.split(separator: "/").last.map(String.init)
    }

    /// Hodnota query parametru v odkazu, např. `userStudentRecordId`.
    func hrefQueryValue(_ name: String) -> String? {
        guard let href = attribute("href"),
              let components = URLComponents(string: href) else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }
}

extension String {
    /// Sjednotí všechny druhy bílých znaků včetně pevné mezery na jednu obyčejnou.
    var normalizedWhitespace: String {
        replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Názvy s krátkou zkratkou

extension DisplayName {
    /// Rozloží „Databázové systémy (DS)“ na plný název a zkratku.
    ///
    /// Zkratka je v závorce na konci; když tam není, zůstane `nil`.
    static func parsingParenthesizedShort(_ raw: String) -> DisplayName {
        let text = raw.normalizedWhitespace
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else {
            return DisplayName(text)
        }
        let full = text[..<open].trimmingCharacters(in: .whitespaces)
        let short = text[text.index(after: open)..<text.index(before: text.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        guard !full.isEmpty, !short.isEmpty else { return DisplayName(text) }
        return DisplayName(full, short: short)
    }
}

// MARK: - Data a časy

/// Převod českých datumů z webu na `Date`.
///
/// Web používá tři různé zápisy a žádný z nich není ISO, takže si je rozebíráme sami.
/// Všechno se počítá v pražském čase, ne v časové zóně telefonu.
enum JecnaDate {

    private static let calendar = Calendar.prague

    /// `30.1.2025` nebo `01.09.2026`
    static func fromNumeric(_ raw: String) -> Date? {
        let parts = raw.normalizedWhitespace
            .replacingOccurrences(of: " ", with: "")
            .split(separator: ".")
        guard parts.count == 3,
              let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]) else { return nil }
        return date(day: day, month: month, year: year)
    }

    /// `3.září` — den a český název měsíce bez roku.
    ///
    /// Rok web neuvádí, takže ho odvozujeme: datum patří do posledních dvanácti měsíců.
    /// Bez toho by zářijová novinka viděná v lednu vyšla o rok dopředu.
    static func fromDayAndCzechMonth(_ raw: String, now: Date = .now) -> Date? {
        let text = raw.normalizedWhitespace.replacingOccurrences(of: " ", with: "")
        guard let dot = text.firstIndex(of: "."),
              let day = Int(text[..<dot]) else { return nil }

        let monthName = String(text[text.index(after: dot)...]).lowercased()
        guard let month = czechMonths[monthName] else { return nil }

        let currentYear = calendar.component(.year, from: now)
        guard let candidate = date(day: day, month: month, year: currentYear) else { return nil }

        // Datum víc než měsíc v budoucnu patří ve skutečnosti do loňska.
        if let limit = calendar.date(byAdding: .month, value: 1, to: now), candidate > limit {
            return date(day: day, month: month, year: currentYear - 1)
        }
        return candidate
    }

    private static func date(day: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)
    }

    /// `7:30 - 8:15` → dvojice časů.
    static func timeRange(_ raw: String) -> (from: TimeOfDay, to: TimeOfDay)? {
        let parts = raw.normalizedWhitespace.components(separatedBy: "-")
        guard parts.count == 2,
              let from = time(parts[0]), let to = time(parts[1]) else { return nil }
        return (from, to)
    }

    /// `7:30`
    static func time(_ raw: String) -> TimeOfDay? {
        let parts = raw.normalizedWhitespace.replacingOccurrences(of: " ", with: "").split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return TimeOfDay(hour, minute)
    }

    /// Web píše měsíce v prvním pádě i bez diakritiky, proto obě podoby.
    private static let czechMonths: [String: Int] = [
        "leden": 1, "ledna": 1,
        "únor": 2, "února": 2, "unor": 2, "unora": 2,
        "březen": 3, "března": 3, "brezen": 3, "brezna": 3,
        "duben": 4, "dubna": 4,
        "květen": 5, "května": 5, "kveten": 5, "kvetna": 5,
        "červen": 6, "června": 6, "cerven": 6, "cervna": 6,
        "červenec": 7, "července": 7, "cervenec": 7, "cervence": 7,
        "srpen": 8, "srpna": 8,
        "září": 9, "zari": 9,
        "říjen": 10, "října": 10, "rijen": 10, "rijna": 10,
        "listopad": 11, "listopadu": 11,
        "prosinec": 12, "prosince": 12,
    ]
}

// MARK: - Dny v týdnu

extension Weekday {
    /// Zkratky, jak je web píše v rozvrhu. Pátek je tam bez diakritiky („Pa“).
    static func fromJecnaAbbreviation(_ raw: String) -> Weekday? {
        switch raw.normalizedWhitespace.lowercased() {
        case "po": .monday
        case "út", "ut": .tuesday
        case "st": .wednesday
        case "čt", "ct": .thursday
        case "pá", "pa": .friday
        default: nil
        }
    }
}

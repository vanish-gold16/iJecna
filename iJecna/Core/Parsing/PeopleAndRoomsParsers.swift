import Foundation
import SwiftSoup

/// Čte stránku `/ucitel/{tag}` — profil jednoho učitele.
enum TeacherParser {

    private static let page = "Profil učitele"

    static func parse(_ html: String, tag: String) throws -> Teacher {
        let document = try HTML.document(html, page: page)
        let profile = UserProfileTable(document)

        // Jméno stojí v nadpisu i v tabulce; nadpis je spolehlivější,
        // protože tam je vždycky, i kdyby se tabulka změnila.
        let fullName = HTML.first(document, "h1 span.label")?.normalizedText.nilIfEmpty
            ?? profile.value("Jméno")

        guard let fullName else {
            throw HTMLParseError(page: page, detail: "na stránce není jméno učitele")
        }

        return Teacher(
            tag: profile.value("Zkratka") ?? tag,
            fullName: fullName,
            username: profile.value("Uživatelské jméno") ?? tag.lowercased(),
            schoolMail: profile.value("E-mail", "Email") ?? "",
            phoneNumbers: [profile.value("Telefon")].compactMap { $0 },
            cabinet: profile.value("Kabinet"),
            tutorOfClass: profile.value("Třídní učitel", "Třídnictví", "Třída"),
            consultationHours: profile.value("Konzultační hodiny"),
            details: profile.rows
        )
    }
}

/// Čte stránku `/ucebna` — seznam učeben.
///
/// Popisek má tvar `Učebna 5 (C2c, Ing. Jana Šedová)` u kmenových učeben
/// a `Učebna 5a (Správce: Mgr. Marie Kmoníčková)` u ostatních.
enum RoomsPageParser {

    private static let page = "Učebny"

    static func parse(_ html: String) throws -> [Room] {
        let document = try HTML.document(html, page: page)
        let items = HTML.all(document, "ul.list a.item")

        guard !items.isEmpty else {
            throw HTMLParseError(page: page, detail: "seznam učeben je prázdný")
        }

        return items.compactMap { item in
            guard let code = item.hrefLastComponent() else { return nil }
            let label = HTML.first(item, "span.label")?.normalizedText ?? item.normalizedText
            let parsed = parseLabel(label)

            return Room(
                roomCode: code,
                name: parsed.name,
                // Patro seznam neuvádí, je až na detailu učebny.
                floor: nil,
                homeroomOf: parsed.homeroom,
                manager: parsed.manager
            )
        }
    }

    static func parseLabel(_ label: String) -> (name: String, homeroom: String?, manager: String?) {
        let text = label.normalizedWhitespace
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else {
            return (text, nil, nil)
        }

        let name = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])

        // „Správce: Jméno“ znamená, že učebna není ničí kmenová.
        if let range = inside.range(of: "Správce:") {
            let manager = String(inside[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (name, nil, manager.nilIfEmpty)
        }

        let fields = inside.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (
            name,
            fields.first?.nilIfEmpty,
            fields.count > 1 ? fields.dropFirst().joined(separator: ", ").nilIfEmpty : nil
        )
    }
}

/// Čte stránku `/locker/student` — přidělenou skříňku.
///
/// Celý údaj je jedna věta:
/// `Příjmení Jméno skříňka č. 469 (1. patro - mezi učebnou 2 a 3) od 1.9.2024 do současnosti`
enum LockerPageParser {

    private static let page = "Skříňka"

    static func parse(_ html: String) throws -> Locker? {
        let document = try HTML.document(html, page: page)

        guard HTML.first(document, "main") != nil else {
            throw HTMLParseError(page: page, detail: "chybí obsah stránky")
        }

        // Student bez přidělené skříňky je běžný stav, ne chyba.
        guard let label = HTML.first(document, "ul.list .item span.label")?.normalizedText,
              label.contains("skříňka") else { return nil }

        return parseLabel(label)
    }

    static func parseLabel(_ label: String) -> Locker? {
        let text = label.normalizedWhitespace

        guard let numberRange = text.range(of: "č.") else { return nil }
        let afterNumber = text[numberRange.upperBound...]

        // Číslo končí závorkou s umístěním, jinak koncem věty.
        let numberEnd = afterNumber.firstIndex(of: "(") ?? afterNumber.endIndex
        let number = afterNumber[..<numberEnd].trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return nil }

        var location = ""
        if let open = afterNumber.firstIndex(of: "("),
           let close = afterNumber.firstIndex(of: ")"), open < close {
            location = String(afterNumber[afterNumber.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
        }

        let tail = afterNumber.firstIndex(of: ")").map { String(afterNumber[afterNumber.index(after: $0)...]) } ?? ""

        return Locker(
            number: number,
            location: location,
            assignedFrom: date(after: "od", in: tail),
            // „do současnosti“ znamená, že skříňka je pořád přidělená.
            assignedUntil: date(after: "do", in: tail)
        )
    }

    private static func date(after keyword: String, in text: String) -> Date? {
        guard let range = text.range(of: "\(keyword) ") else { return nil }
        let candidate = text[range.upperBound...]
            .split(separator: " ")
            .first
            .map(String.init)
        return candidate.flatMap(JecnaDate.fromNumeric)
    }
}

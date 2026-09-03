import Foundation
import SwiftSoup

/// Čte stránku `/ucitel` — seznam učitelů rozdělený do dvou sloupců.
enum TeachersPageParser {

    private static let page = "Pedagogický sbor"

    static func parse(_ html: String) throws -> [TeacherRef] {
        let document = try HTML.document(html, page: page)
        let links = HTML.all(document, "a[href^=/ucitel/]")

        let teachers = links.compactMap { link -> TeacherRef? in
            guard let tag = link.hrefLastComponent(), !tag.isEmpty else { return nil }
            let name = link.normalizedText
            guard !name.isEmpty else { return nil }
            return TeacherRef(tag: tag, fullName: name)
        }

        guard !teachers.isEmpty else {
            throw HTMLParseError(page: page, detail: "seznam učitelů je prázdný")
        }

        // Sloupce se čtou zvlášť, takže se učitel může objevit dvakrát;
        // rozhoduje první výskyt.
        var seen = Set<String>()
        return teachers.filter { seen.insert($0.tag).inserted }
    }
}

/// Čte stránku `/user-student/record-list` — poznámky, pochvaly a úřední sdělení.
///
/// Seznam nese jen souhrn; podrobný text je až na detailu záznamu.
enum NotificationsPageParser {

    private static let page = "Sdělení rodičům"

    static func parse(_ html: String) throws -> [SchoolNotification] {
        let document = try HTML.document(html, page: page)

        // Prázdný seznam je běžný stav — student prostě nic nemá.
        guard HTML.first(document, "main") != nil else {
            throw HTMLParseError(page: page, detail: "chybí obsah stránky")
        }

        return HTML.all(document, "ul.list a.item").compactMap(parseItem)
    }

    private static func parseItem(_ link: Element) -> SchoolNotification? {
        guard let recordId = Int(link.hrefQueryValue("userStudentRecordId") ?? "") else { return nil }

        let label = HTML.first(link, "span.label")?.normalizedText ?? link.normalizedText
        let fields = parseLabel(label)
        guard let date = fields.date else { return nil }

        return SchoolNotification(
            id: recordId,
            kind: kind(for: fields.type, iconClass: HTML.first(link, "span[class*=sprite-icon]")?.attribute("class")),
            exactType: fields.type,
            message: fields.type,
            date: date,
            issuedBy: nil,
            caseNumber: fields.caseNumber
        )
    }

    /// Popisek má tvar `30.1.2025, č.j. SPSE/00179/2025, Pochvala tř. učitele`.
    /// Číslo jednací je nepovinné a druh sdělení může sám obsahovat čárky.
    static func parseLabel(_ label: String) -> (date: Date?, caseNumber: String?, type: String) {
        var fields = label.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !fields.isEmpty else { return (nil, nil, label) }

        let date = JecnaDate.fromNumeric(fields.removeFirst())

        var caseNumber: String?
        if let first = fields.first, first.lowercased().hasPrefix("č.j.") {
            caseNumber = String(first.dropFirst("č.j.".count)).trimmingCharacters(in: .whitespaces).nilIfEmpty
            fields.removeFirst()
        }

        return (date, caseNumber, fields.joined(separator: ", ").nilIfEmpty ?? label)
    }

    /// Druh se pozná ze slova v popisku; ikona slouží jen jako záloha,
    /// protože její název se může kdykoli změnit s grafikou webu.
    private static func kind(for type: String, iconClass: String?) -> SchoolNotification.Kind {
        let text = type.lowercased()
        if text.contains("pochval") { return .good }
        if text.contains("napomenut") || text.contains("důtka") || text.contains("poznámk") { return .bad }

        guard let iconClass = iconClass?.lowercased() else { return .info }
        if iconClass.contains("tick") { return .good }
        if iconClass.contains("exclamation") || iconClass.contains("cross") || iconClass.contains("error") {
            return .bad
        }
        return .info
    }
}

import Foundation
import SwiftSoup

/// Tabulka `table.userprofile`, kterou web používá pro profily lidí.
///
/// Je to prostý seznam dvojic popisek → hodnota. Hodnota bývá v `span.value`,
/// ale u e-mailu nebo kabinetu je to odkaz — proto se bere text celé buňky,
/// který pokryje obojí.
struct UserProfileTable {

    private let values: [String: String]
    /// Odkazy v hodnotách, aby šlo z kabinetu vyčíst kód učebny.
    private let links: [String: String]

    /// Všechny řádky v pořadí, v jakém je stránka uvádí.
    ///
    /// Vyhledávání podle popisku je křehké: stačí, aby škola pojmenovala
    /// položku jinak, a údaj zmizí. Proto se vedle toho drží celý obsah
    /// tabulky — obrazovka pak ukáže i to, co jsme nepojmenovali dopředu.
    let rows: [ProfileField]

    init(_ container: Element) {
        var values: [String: String] = [:]
        var links: [String: String] = [:]
        var rows: [ProfileField] = []

        for row in Self.rows(in: container) {
            guard let label = HTML.first(row, "th")?.normalizedText.nilIfEmpty,
                  let cell = HTML.first(row, "td"),
                  let value = cell.normalizedText.nilIfEmpty else { continue }

            let key = Self.normalizeKey(label)
            let href = HTML.first(cell, "a")?.attribute("href")

            values[key] = value
            if let href { links[key] = href }
            rows.append(ProfileField(label: label, value: value, link: href))
        }

        self.values = values
        self.links = links
        self.rows = rows
    }

    /// Řádky tabulky profilu.
    ///
    /// Profil učitele má `table.userprofile`, ale šablona se stránku od stránky
    /// liší, takže se jako záloha vezme kterákoli tabulka dvojic v obsahu.
    /// Rozvrh a známky se musí vynechat — mají také `th` a `td`, ale popisky
    /// to nejsou.
    private static func rows(in container: Element) -> [Element] {
        let named = HTML.all(container, "table.userprofile")
        let tables = named.isEmpty
            ? HTML.all(container, "main table").filter {
                !$0.hasClass("timetable") && !$0.hasClass("score")
            }
            : named

        return tables.flatMap { HTML.all($0, "tr") }
    }

    /// Popisky se liší diakritikou i velikostí písmen podle šablony,
    /// tak je srovnáme na společný tvar.
    private static func normalizeKey(_ label: String) -> String {
        label
            .trimmingCharacters(in: CharacterSet(charactersIn: ": \t"))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .normalizedWhitespace
    }

    /// Hodnota pro první z uvedených popisků, který se na stránce vyskytne.
    func value(_ labels: String...) -> String? {
        for label in labels {
            if let value = values[Self.normalizeKey(label)] { return value }
        }
        return nil
    }

    func link(_ labels: String...) -> String? {
        for label in labels {
            if let link = links[Self.normalizeKey(label)] { return link }
        }
        return nil
    }

    var isEmpty: Bool { values.isEmpty }
}

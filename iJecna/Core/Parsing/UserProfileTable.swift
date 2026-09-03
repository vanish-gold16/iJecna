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

    init(_ container: Element) {
        var values: [String: String] = [:]
        var links: [String: String] = [:]

        for row in HTML.all(container, "table.userprofile tr") {
            guard let label = HTML.first(row, "th")?.normalizedText.nilIfEmpty,
                  let cell = HTML.first(row, "td") else { continue }

            let key = Self.normalizeKey(label)
            if let value = cell.normalizedText.nilIfEmpty {
                values[key] = value
            }
            if let href = HTML.first(cell, "a")?.attribute("href") {
                links[key] = href
            }
        }

        self.values = values
        self.links = links
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

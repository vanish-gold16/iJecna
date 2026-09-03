import Foundation
import SwiftSoup

/// Čte stránku `/akce`.
///
/// Každá novinka je `div.event` s nadpisem, textem a patičkou, ve které stojí
/// datum, autor a případně poznámka, že je článek jen pro školu.
enum NewsPageParser {

    private static let page = "Aktuality"

    static func parse(_ html: String, now: Date = .now) throws -> [Article] {
        let document = try HTML.document(html, page: page)
        let events = HTML.all(document, "div.event")

        guard !events.isEmpty else {
            // Prázdná stránka novinek je legitimní stav; chybějící kontejner není.
            guard HTML.first(document, "main") != nil else {
                throw HTMLParseError(page: page, detail: "chybí obsah stránky")
            }
            return []
        }

        return events.compactMap { parseArticle($0, now: now) }
    }

    private static func parseArticle(_ event: Element, now: Date) -> Article? {
        guard let link = HTML.first(event, "div.name a"),
              let id = Int(link.hrefLastComponent() ?? "") else { return nil }

        let footer = parseFooter(HTML.first(event, "div.footer")?.normalizedText ?? "", now: now)
        let textElement = HTML.first(event, "div.text")

        return Article(
            id: id,
            title: link.normalizedText,
            content: textElement?.normalizedText ?? "",
            date: footer.date ?? now,
            author: footer.author ?? "",
            schoolOnly: footer.schoolOnly,
            attachments: parseAttachments(event)
        )
    }

    /// Patička má tvar `3.září | Hana Budská | Pouze pro školu`.
    /// Poslední část je nepovinná.
    private static func parseFooter(
        _ text: String,
        now: Date
    ) -> (date: Date?, author: String?, schoolOnly: Bool) {
        let fields = text
            .components(separatedBy: "|")
            .map { $0.normalizedWhitespace }
            .filter { !$0.isEmpty }

        guard let first = fields.first else { return (nil, nil, false) }

        return (
            JecnaDate.fromDayAndCzechMonth(first, now: now),
            fields.count > 1 ? fields[1] : nil,
            fields.contains { $0.lowercased().contains("pouze pro školu") }
        )
    }

    /// Přílohy stojí ve vlastním seznamu `ul.files` vedle textu, ale odkaz na
    /// soubor může být i přímo v textu článku — bereme obojí.
    private static func parseAttachments(_ event: Element) -> [ArticleAttachment] {
        var seen = Set<String>()

        return HTML.all(event, "a[href^=/download/]").compactMap { link in
            guard let path = link.attribute("href"), seen.insert(path).inserted else { return nil }

            // U položek v `ul.files` je název v popisku, u odkazů v textu
            // je názvem samotný text odkazu.
            let label = (HTML.first(link, "span.label")?.normalizedText).flatMap { $0.nilIfEmpty }
                ?? link.normalizedText.nilIfEmpty
                ?? path.split(separator: "/").last
                    .map(String.init)
                    .flatMap { $0.removingPercentEncoding ?? $0 }
                ?? "Příloha"

            return ArticleAttachment(label: label, downloadPath: path)
        }
    }
}

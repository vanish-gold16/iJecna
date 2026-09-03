import Foundation
import SwiftSoup

/// Čte stránku `/student/{username}`.
///
/// Jméno a uživatelské jméno se dají vzít z prvků, které má každá přihlášená
/// stránka: nabídky uživatele a drobečkové navigace. Ostatní údaje profilu
/// zatím nečteme — nemáme k té stránce uloženou předlohu, podle které by
/// se dal parser ověřit, a hádat obsah je horší než ho neukázat.
enum StudentProfileParser {

    private static let page = "Profil studenta"

    static func parse(_ html: String, username: String) throws -> Student {
        let document = try HTML.document(html, page: page)
        let identity = self.identity(in: document)

        guard let fullName = identity.fullName else {
            throw HTMLParseError(page: page, detail: "na stránce není jméno studenta")
        }

        return Student(
            fullName: fullName,
            username: identity.username ?? username,
            schoolMail: schoolMail(in: document) ?? "",
            className: nil,
            classGroups: nil,
            birthDate: nil,
            permanentAddress: nil,
            guardians: [],
            profilePicturePath: nil
        )
    }

    /// Jméno a uživatelské jméno přihlášeného studenta.
    ///
    /// Funguje na kterékoli přihlášené stránce, takže se dá použít i jako
    /// ověření, že relace opravdu patří tomu, koho čekáme.
    static func identity(in document: Document) -> (fullName: String?, username: String?) {
        // Odkaz „Můj profil“ v nabídce uživatele nese uživatelské jméno v cestě.
        let username = HTML.all(document, "a[href^=/student/]")
            .compactMap { $0.hrefLastComponent() }
            .first

        // Drobečková navigace v nadpisu nese jméno, příjmením napřed.
        let breadcrumb = HTML.first(document, "h1 span.breadcrumb a")
            ?? HTML.first(document, "span.breadcrumb a")

        return (breadcrumb.map { displayName($0.normalizedText) }, username)
    }

    /// Web píše „Příjmení Jméno“; k zobrazení se hodí obvyklé pořadí.
    private static func displayName(_ raw: String) -> String {
        let words = raw.normalizedWhitespace.split(separator: " ").map(String.init)
        guard words.count == 2 else { return raw.normalizedWhitespace }
        return "\(words[1]) \(words[0])"
    }

    private static func schoolMail(in document: Document) -> String? {
        HTML.all(document, "a[href^=mailto:]")
            .compactMap { $0.attribute("href")?.replacingOccurrences(of: "mailto:", with: "") }
            .first { $0.contains("@") }
    }
}

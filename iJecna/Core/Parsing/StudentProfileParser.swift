import Foundation
import SwiftSoup

/// Čte stránku `/student/{username}`.
///
/// Údaje jsou ve stejné tabulce `table.userprofile`, jakou má profil učitele.
/// Jméno a uživatelské jméno se navíc dají vzít z prvků, které nese každá
/// přihlášená stránka — nadpisu a drobečkové navigace.
enum StudentProfileParser {

    private static let page = "Profil studenta"

    static func parse(_ html: String, username: String) throws -> Student {
        let document = try HTML.document(html, page: page)
        let profile = UserProfileTable(document)
        let identity = self.identity(in: document)

        // Tabulka uvádí jméno rovnou ve správném pořadí, nadpis ho má obráceně.
        // Drobečková navigace tady jméno nenese — odkazuje na třídu.
        let heading = profile.isEmpty
            ? nil
            : HTML.first(document, "h1 span.label.label-icon")?.normalizedText.nilIfEmpty

        let fullName = profile.value("Celé jméno", "Jméno")
            ?? heading.map(displayName)
            ?? identity.fullName

        guard let fullName else {
            throw HTMLParseError(page: page, detail: "na stránce není jméno studenta")
        }

        let classAndGroups = parseClassAndGroups(profile.value("Třída, skupiny", "Třída"))
        let birth = parseBirth(profile.value("Narození", "Datum narození"))

        return Student(
            fullName: fullName,
            username: profile.value("Uživatelské jméno") ?? identity.username ?? username,
            // Popisek školní adresy nese i poznámku o přeposílání,
            // spolehlivý je odkaz.
            schoolMail: mailAddress(profile.link("Školní e-mail"))
                ?? profile.value("Školní e-mail")
                ?? schoolMail(in: document)
                ?? "",
            className: classAndGroups.className ?? classFromBreadcrumb(document),
            classGroups: classAndGroups.groups,
            birthDate: birth.date,
            birthPlace: birth.place,
            permanentAddress: profile.value("Trvalá adresa", "Trvalé bydliště", "Adresa"),
            guardians: [],
            profilePicturePath: HTML.first(document, "div.profilephoto img")?.attribute("src"),
            details: profile.rows
        )
    }

    /// `C3c, skupiny: A2` — třída a za ní volitelný výčet skupin.
    static func parseClassAndGroups(_ raw: String?) -> (className: String?, groups: String?) {
        guard let raw = raw?.normalizedWhitespace, !raw.isEmpty else { return (nil, nil) }

        guard let marker = raw.range(of: "skupin", options: .caseInsensitive) else {
            return (raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,")).nilIfEmpty, nil)
        }

        let className = String(raw[..<marker.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            .nilIfEmpty

        let groups = String(raw[marker.upperBound...])
            .drop { $0 != ":" }
            .dropFirst()
            .trimmingCharacters(in: .whitespaces)
            .nilIfEmpty

        return (className, groups)
    }

    /// `02.05.2008, DNĚPROPETROVSK` — datum a místo v jedné buňce.
    static func parseBirth(_ raw: String?) -> (date: Date?, place: String?) {
        guard let raw = raw?.normalizedWhitespace, !raw.isEmpty else { return (nil, nil) }
        var fields = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let date = fields.first.flatMap(JecnaDate.fromNumeric)
        if date != nil { fields.removeFirst() }
        return (date, fields.joined(separator: ", ").nilIfEmpty)
    }

    /// Na profilu odkazuje drobečková navigace na třídu (`/trida/C3c`).
    private static func classFromBreadcrumb(_ document: Document) -> String? {
        HTML.first(document, "h1 span.breadcrumb a[href^=/trida/]")?.normalizedText.nilIfEmpty
    }

    private static func mailAddress(_ link: String?) -> String? {
        guard let link, link.hasPrefix("mailto:") else { return nil }
        return String(link.dropFirst("mailto:".count)).nilIfEmpty
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

        // Drobečková navigace nese jméno jen na podstránkách studenta;
        // na samotném profilu odkazuje na třídu, a to jméno není.
        let breadcrumb = HTML.first(document, "span.breadcrumb a[href^=/student/]")

        return (breadcrumb.map { displayName($0.normalizedText) }, username)
    }

    /// Web píše jméno studenta příjmením napřed; k zobrazení se pořadí obrací.
    /// Delší jména (s tituly nebo složeným příjmením) necháváme být — u nich
    /// se nedá spolehlivě určit, co je co.
    static func displayName(_ raw: String) -> String {
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

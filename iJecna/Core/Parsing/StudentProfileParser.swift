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

        // Pořadí zdrojů není libovolné. Na profilu je jméno v nadpisu, ale na
        // podstránkách je v nadpisu název stránky — proto se nadpis bere jen
        // tam, kde je i tabulka profilu. Jinak by se student jmenoval „Skříňka“.
        let heading = profile.isEmpty
            ? nil
            : HTML.first(document, "h1 span.label.label-icon")?.normalizedText.nilIfEmpty

        let rawName = heading
            ?? HTML.first(document, "h1 span.breadcrumb a")?.normalizedText.nilIfEmpty
            ?? profile.value("Jméno")
            // Poslední záchrana pro případ, že by profil neměl ani tabulku,
            // ani drobečkovou navigaci. Sem se dostane jen stránka profilu,
            // takže v nadpisu bude jméno.
            ?? HTML.first(document, "h1 span.label.label-icon")?.normalizedText.nilIfEmpty

        guard let fullName = rawName.map(displayName) else {
            throw HTMLParseError(page: page, detail: "na stránce není jméno studenta")
        }

        return Student(
            fullName: fullName,
            username: profile.value("Uživatelské jméno") ?? identity.username ?? username,
            // Když tabulka e-mail neuvádí, najdeme ho podle odkazu — na profilu
            // je školní adresa jediný mailto na stránce.
            schoolMail: profile.value("E-mail", "Email") ?? schoolMail(in: document) ?? "",
            className: profile.value("Třída", "Třída/skupina", "Studijní skupina"),
            classGroups: profile.value("Skupiny", "Skupina", "Dělení", "Zařazení do skupin"),
            birthDate: profile.value("Datum narození").flatMap(JecnaDate.fromNumeric),
            permanentAddress: profile.value("Trvalé bydliště", "Adresa", "Bydliště"),
            guardians: [],
            profilePicturePath: HTML.first(document, "div.profilephoto img")?.attribute("src"),
            details: profile.rows
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

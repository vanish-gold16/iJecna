import XCTest
import SwiftSoup
@testable import iJecna

/// Jméno a uživatelské jméno se dají přečíst z kterékoli přihlášené stránky,
/// takže se dají ověřit i bez uložené předlohy samotného profilu.
final class StudentProfileParserTests: XCTestCase {

    func testReadsIdentityFromAnySignedInPage() throws {
        let document = try SwiftSoup.parse(Fixture.notifications.html())
        let identity = StudentProfileParser.identity(in: document)

        XCTAssertEqual(identity.username, "mytrofanov")
        // Web píše „Příjmení Jméno“, k zobrazení se pořadí obrací.
        XCTAssertEqual(identity.fullName, "Ivan Mytrofanov")
    }

    func testIdentityHandlesNonBreakingSpaceInName() throws {
        // V drobečkové navigaci je mezi jménem a příjmením pevná mezera.
        let html = """
        <html><body><h1 id="h1">
          <span class="breadcrumb"><a href="/student/novak">Novák&nbsp;Jan</a> / </span>
        </h1></body></html>
        """
        let identity = StudentProfileParser.identity(in: try SwiftSoup.parse(html))
        XCTAssertEqual(identity.fullName, "Jan Novák")
        XCTAssertEqual(identity.username, "novak")
    }

    func testFailsLoudlyWhenNameIsMissing() {
        // Prázdná stránka nesmí projít jako profil bez jména.
        XCTAssertThrowsError(
            try StudentProfileParser.parse("<html><body></body></html>", username: "novak")
        )
    }

    func testParsesProfileFromSignedInPage() throws {
        let student = try StudentProfileParser.parse(Fixture.notifications.html(), username: "mytrofanov")
        XCTAssertEqual(student.fullName, "Ivan Mytrofanov")
        XCTAssertEqual(student.username, "mytrofanov")
        XCTAssertEqual(student.initials, "IM")
    }
}

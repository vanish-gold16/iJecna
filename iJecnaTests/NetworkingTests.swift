import XCTest
@testable import iJecna

/// Zkoušky přenosové vrstvy — kódování adres, čtení přesměrování, CSRF token.
///
/// Nic z toho nechodí na síť: testuje se čistá logika, na které stojí rozhodnutí
/// „přihlášení vyšlo / nevyšlo / relace vypršela“.
final class NetworkingTests: XCTestCase {

    private let base = JecnaEndpoint.officialBase

    // MARK: - Adresy

    func testGradesURLMatchesRealForm() {
        // Hodnoty ověřené proti výběrům na skutečné stránce známek:
        // schoolYearId 17 = 2025/2026, schoolYearHalfId 22 = 2. pololetí.
        let url = JecnaEndpoint.grades(year: SchoolYear(2025), half: .second).url(base: base)
        XCTAssertEqual(
            url.absoluteString,
            "https://www.spsejecna.cz/score/student?schoolYearId=17&schoolYearHalfId=22"
        )
    }

    func testGradesURLWithoutHalfOmitsParameter() {
        let url = JecnaEndpoint.grades(year: SchoolYear(2026), half: nil).url(base: base)
        XCTAssertEqual(url.absoluteString, "https://www.spsejecna.cz/score/student?schoolYearId=18")
    }

    func testTimetableURLCarriesPeriodId() {
        let url = JecnaEndpoint.timetable(year: SchoolYear(2026), periodId: 215).url(base: base)
        XCTAssertEqual(
            url.absoluteString,
            "https://www.spsejecna.cz/timetable/class?schoolYearId=18&timetableId=215"
        )
    }

    func testSchoolYearIdMatchesSiteEncoding() {
        // Odpovídá nabídce na webu: 16 = 2024/2025, 17 = 2025/2026, 18 = 2026/2027.
        XCTAssertEqual(SchoolYear(2024).jecnaId, 16)
        XCTAssertEqual(SchoolYear(2025).jecnaId, 17)
        XCTAssertEqual(SchoolYear(2026).jecnaId, 18)
    }

    func testPathEndpointsIncludeIdentifier() {
        XCTAssertEqual(
            JecnaEndpoint.teacher(tag: "BC").url(base: base).absoluteString,
            "https://www.spsejecna.cz/ucitel/BC"
        )
        XCTAssertEqual(
            JecnaEndpoint.notification(recordId: 7314).url(base: base).absoluteString,
            "https://www.spsejecna.cz/user-student/record?userStudentRecordId=7314"
        )
    }

    // MARK: - Přesměrování

    func testRedirectPathHandlesAbsoluteLocation() {
        let response = JecnaResponse(
            statusCode: 302,
            body: "",
            location: "https://www.spsejecna.cz/user/need-login"
        )
        XCTAssertTrue(response.isRedirect)
        XCTAssertEqual(response.redirectPath, "/user/need-login")
    }

    func testRedirectPathHandlesRelativeLocation() {
        let response = JecnaResponse(statusCode: 302, body: "", location: "/")
        XCTAssertEqual(response.redirectPath, "/")
    }

    func testSuccessfulResponseHasNoRedirect() {
        let response = JecnaResponse(statusCode: 200, body: "<html></html>", location: nil)
        XCTAssertTrue(response.isOK)
        XCTAssertFalse(response.isRedirect)
        XCTAssertNil(response.redirectPath)
    }

    // MARK: - CSRF token

    func testExtractsLoginToken() {
        let html = """
        <form id="loginForm" method="post" action="/user/login">
          <input type="text" name="user" />
          <input type="password" name="pass" />
          <input type="hidden" name="token3" value="51565081" />
          <input type="submit" name="submit" value="Přihlásit se" />
        </form>
        """
        XCTAssertEqual(JecnaHTTPClient.extractLoginToken(from: html), "51565081")
    }

    func testExtractsLoginTokenWithReversedAttributeOrder() {
        // Šablona webu nemá pevné pořadí atributů a mezery mezi nimi občas chybí.
        let html = #"<input value="99887766"name="token3"type="hidden">"#
        XCTAssertEqual(JecnaHTTPClient.extractLoginToken(from: html), "99887766")
    }

    func testMissingLoginTokenReturnsNil() {
        XCTAssertNil(JecnaHTTPClient.extractLoginToken(from: "<html><body>nic</body></html>"))
    }

    // MARK: - Přihlašovací údaje

    func testUsernameNormalisationStripsSchoolDomain() {
        XCTAssertEqual(
            JecnaCredentials(username: "  Mytrofanov@spsejecna.cz ", password: "x").username,
            "mytrofanov"
        )
        XCTAssertEqual(JecnaCredentials(username: "NOVAK", password: "x").username, "novak")
    }
}

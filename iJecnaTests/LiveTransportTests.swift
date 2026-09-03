import XCTest
@testable import iJecna

/// Zkoušky proti opravdovému webu školy.
///
/// Standardně se přeskakují — chodí na síť a nesmí kazit běžný běh zkoušek.
/// Spustí se proměnnou prostředí:
///
/// ```sh
/// RUN_LIVE_TESTS=1 xcodebuild test … -only-testing:iJecnaTests/LiveTransportTests
/// ```
///
/// Přihlašovací údaje nepotřebují: ověřují jen to, co jde zjistit bez účtu —
/// že nás server pustí dovnitř, že najdeme CSRF token a že chráněná stránka
/// nepřihlášeného odmítne přesně tak, jak klient očekává.
final class LiveTransportTests: XCTestCase {

    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(isEnabled, "Živé zkoušky jsou vypnuté (nastav RUN_LIVE_TESTS=1)")
    }

    func testServerAcceptsOurClient() async throws {
        let client = JecnaHTTPClient()
        await client.setRole(.student)

        let response = try await client.plainRequest(.root)
        XCTAssertEqual(
            response.statusCode, 200,
            "Server odmítl našeho klienta — nejspíš kvůli User-Agent"
        )
    }

    func testRoleCookieIsActuallyStored() async throws {
        let client = JecnaHTTPClient()
        await client.setRole(.student)
        // Bez role serveru přijde stránka pro zájemce, kde formulář není.
        let value = await client.cookieValue(named: "WTDGUID")
        XCTAssertEqual(value, "10")
    }

    func testFindsLoginTokenOnLiveRootPage() async throws {
        let client = JecnaHTTPClient()
        await client.setRole(.student)

        let response = try await client.plainRequest(.root)
        XCTAssertTrue(
            response.body.contains("loginForm"),
            "Na kořenové stránce není přihlašovací formulář — nejspíš se neposlala role"
        )
        XCTAssertNotNil(
            JecnaHTTPClient.extractLoginToken(from: response.body),
            "Na kořenové stránce chybí token3 — změnil se přihlašovací formulář"
        )
    }

    func testProtectedPageRedirectsAnonymousVisitor() async throws {
        let client = JecnaHTTPClient()
        await client.setRole(.student)

        let response = try await client.plainRequest(.grades(year: .current, half: .current))

        // Tohle je základ celého rozpoznávání relace: nepřihlášený dostane
        // přesměrování, ne chybovou stránku.
        XCTAssertTrue(response.isRedirect, "Očekáváno přesměrování, přišlo \(response.statusCode)")
        XCTAssertEqual(response.redirectPath?.hasPrefix("/user/"), true)
    }

    func testPublicNewsPageParses() async throws {
        let client = JecnaHTTPClient()
        await client.setRole(.student)

        let html = try await client.html(.news)
        let articles = try NewsPageParser.parse(html)

        // Novinky jsou veřejné, takže je můžeme přečíst i bez přihlášení
        // a ověřit tím parser proti aktuální podobě webu.
        XCTAssertFalse(articles.isEmpty, "Živá stránka novinek se nepodařilo přečíst")
        XCTAssertTrue(articles.allSatisfy { $0.id > 0 })
        XCTAssertTrue(articles.allSatisfy { !$0.title.isEmpty })
    }
}

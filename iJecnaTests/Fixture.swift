import Foundation
import XCTest

/// Přístup k uloženým stránkám školního webu.
///
/// Soubory se čtou přímo ze zdrojů přes `#filePath`, ne z balíčku testů:
/// jde o vstupy pro snímkové zkoušky, ne o prostředky aplikace, a tímhle
/// způsobem nemusí být zapsané v projektu.
enum Fixture: String, CaseIterable {
    case grades = "SPŠE Ječná - Známky.html"
    case gradesPreviousYear = "SPŠE Ječná - Známky_2025:26.html"
    case timetable = "SPŠE Ječná - Rozvrh hodin.html"
    case news = "SPŠE Ječná - Novinky.html"
    case teachers = "SPŠE Ječná - Pedagogický sbor.html"
    case notifications = "SPŠE Ječná - Sdělení rodičům.html"

    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    var url: URL { Self.directory.appendingPathComponent(rawValue) }

    func html(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Chybí uložená stránka „\(rawValue)“ ve složce Fixtures", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Kontrola, že jsou všechny očekávané stránky na místě.
final class FixtureTests: XCTestCase {
    func testAllFixturesArePresent() throws {
        for fixture in Fixture.allCases {
            let html = try fixture.html()
            XCTAssertFalse(html.isEmpty, "Stránka „\(fixture.rawValue)“ je prázdná")
            XCTAssertTrue(
                html.contains("spsejecna") || html.contains("Ječná"),
                "Stránka „\(fixture.rawValue)“ nevypadá jako web školy"
            )
        }
    }
}

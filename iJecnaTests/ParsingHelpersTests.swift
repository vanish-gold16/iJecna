import XCTest
@testable import iJecna

/// Zkoušky pomocných nástrojů, na kterých stojí všechny parsery stránek.
final class ParsingHelpersTests: XCTestCase {

    // MARK: - Bílé znaky

    func testNormalisesNonBreakingSpaceAndDoubleSpaces() {
        // Web sype &nbsp; mezi jméno a příjmení a v názvech předmětů má dvojité mezery.
        XCTAssertEqual("Mytrofanov\u{00A0}Ivan".normalizedWhitespace, "Mytrofanov Ivan")
        XCTAssertEqual("Tělesná  výchova".normalizedWhitespace, "Tělesná výchova")
        XCTAssertEqual("  a \n b \t c  ".normalizedWhitespace, "a b c")
    }

    // MARK: - Názvy se zkratkou

    func testSplitsSubjectNameAndShortForm() {
        let name = DisplayName.parsingParenthesizedShort("Databázové systémy (DS)")
        XCTAssertEqual(name.full, "Databázové systémy")
        XCTAssertEqual(name.short, "DS")
    }

    func testSubjectNameWithoutShortFormStaysWhole() {
        let name = DisplayName.parsingParenthesizedShort("Chování")
        XCTAssertEqual(name.full, "Chování")
        XCTAssertNil(name.short)
    }

    func testSubjectNameNormalisesInnerSpacing() {
        let name = DisplayName.parsingParenthesizedShort("Tělesná  výchova (TV)")
        XCTAssertEqual(name.full, "Tělesná výchova")
        XCTAssertEqual(name.short, "TV")
    }

    // MARK: - Data

    func testParsesNumericDate() throws {
        let date = try XCTUnwrap(JecnaDate.fromNumeric("27.02.2026"))
        let parts = Calendar.prague.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 2)
        XCTAssertEqual(parts.day, 27)
    }

    func testParsesNumericDateWithoutLeadingZeros() throws {
        let date = try XCTUnwrap(JecnaDate.fromNumeric("30.1.2025"))
        let parts = Calendar.prague.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual([parts.day, parts.month, parts.year], [30, 1, 2025])
    }

    func testCzechMonthDateTakesCurrentYearWhenRecent() throws {
        // Novinky rok neuvádějí. Zářijová položka viděná v září patří do letoška.
        let now = try XCTUnwrap(JecnaDate.fromNumeric("15.09.2026"))
        let date = try XCTUnwrap(JecnaDate.fromDayAndCzechMonth("3.září", now: now))
        let parts = Calendar.prague.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual([parts.day, parts.month, parts.year], [3, 9, 2026])
    }

    func testCzechMonthDateFallsBackToPreviousYear() throws {
        // Táž zářijová položka viděná v lednu patří do loňska, ne o rok dopředu.
        let now = try XCTUnwrap(JecnaDate.fromNumeric("10.01.2027"))
        let date = try XCTUnwrap(JecnaDate.fromDayAndCzechMonth("3.září", now: now))
        let parts = Calendar.prague.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual([parts.day, parts.month, parts.year], [3, 9, 2026])
    }

    func testRejectsUnknownMonth() {
        XCTAssertNil(JecnaDate.fromDayAndCzechMonth("3.smyšlen"))
    }

    // MARK: - Časy

    func testParsesLessonTimeRange() throws {
        let range = try XCTUnwrap(JecnaDate.timeRange("7:30 - 8:15"))
        XCTAssertEqual(range.from, TimeOfDay(7, 30))
        XCTAssertEqual(range.to, TimeOfDay(8, 15))
    }

    func testRejectsMalformedTime() {
        XCTAssertNil(JecnaDate.time("25:99"))
        XCTAssertNil(JecnaDate.timeRange("7:30"))
    }

    // MARK: - Dny v týdnu

    func testMapsJecnaWeekdayAbbreviations() {
        XCTAssertEqual(Weekday.fromJecnaAbbreviation("Po"), .monday)
        XCTAssertEqual(Weekday.fromJecnaAbbreviation("Út"), .tuesday)
        XCTAssertEqual(Weekday.fromJecnaAbbreviation("St"), .wednesday)
        XCTAssertEqual(Weekday.fromJecnaAbbreviation("Čt"), .thursday)
        // Pátek web píše bez diakritiky.
        XCTAssertEqual(Weekday.fromJecnaAbbreviation("Pa"), .friday)
        XCTAssertEqual(Weekday.fromJecnaAbbreviation("Pá"), .friday)
        XCTAssertNil(Weekday.fromJecnaAbbreviation("So"))
    }
}

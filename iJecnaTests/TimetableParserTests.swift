import XCTest
@testable import iJecna

/// Snímkové zkoušky parseru rozvrhu proti skutečné uložené stránce.
///
/// Až škola šablonu změní, spadnou právě tyhle zkoušky — dřív, než se rozbitý
/// rozvrh dostane k uživateli.
final class TimetableParserTests: XCTestCase {

    private var page: TimetablePage!

    override func setUpWithError() throws {
        page = try TimetablePageParser.parse(Fixture.timetable.html())
    }

    // MARK: - Hlavička

    func testReadsAllLessonPeriods() {
        XCTAssertEqual(page.timetable.periods.count, 10)
        XCTAssertEqual(page.timetable.periods.first?.number, 1)
        XCTAssertEqual(page.timetable.periods.first?.from, TimeOfDay(7, 30))
        XCTAssertEqual(page.timetable.periods.first?.to, TimeOfDay(8, 15))
        XCTAssertEqual(page.timetable.periods.last?.number, 10)
        XCTAssertEqual(page.timetable.periods.last?.to, TimeOfDay(16, 25))
    }

    func testReadsAllFiveSchoolDays() {
        XCTAssertEqual(page.timetable.days.map(\.weekday), [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    func testReadsSelectedSchoolYear() {
        // Na stránce je vybraný rok 2026/2027 (id 18).
        XCTAssertEqual(page.schoolYear, SchoolYear(2026))
    }

    func testReadsTimetableVariant() throws {
        let option = try XCTUnwrap(page.periodOptions.first)
        XCTAssertEqual(option.id, 215)
        XCTAssertEqual(option.header, "Dočasný rozvrh září 2026")
        XCTAssertTrue(option.isSelected)
        XCTAssertNil(option.to, "Varianta bez koncového data nemá mít konec")

        let from = Calendar.prague.dateComponents([.year, .month, .day], from: option.from)
        XCTAssertEqual([from.day, from.month, from.year], [1, 9, 2026])
    }

    // MARK: - Obsah hodiny

    func testReadsLessonDetails() throws {
        let monday = try XCTUnwrap(page.timetable.day(.monday))
        let spot = try XCTUnwrap(monday.spot(atPeriod: 3))
        let lesson = try XCTUnwrap(spot.lessons.first)

        XCTAssertEqual(lesson.subject.full, "Český jazyk a literatura")
        XCTAssertEqual(lesson.subject.short, "C")
        XCTAssertEqual(lesson.classroom, "27")
        XCTAssertEqual(lesson.teacherTag, "SU")
        XCTAssertEqual(lesson.teacher?.full, "Kristina Studénková")
        XCTAssertNil(lesson.group, "Nedělená hodina nemá skupinu")
    }

    func testReadsSplitGroups() throws {
        let monday = try XCTUnwrap(page.timetable.day(.monday))
        let spot = try XCTUnwrap(monday.spot(atPeriod: 1))

        XCTAssertTrue(spot.isSplit)
        XCTAssertEqual(spot.lessons.map(\.group), ["1/2", "2/2"])
        XCTAssertEqual(spot.lessons.map(\.classroom), ["18a", "18b"])
        XCTAssertEqual(spot.lessons.map(\.teacherTag), ["BC", "RE"])
        XCTAssertEqual(Set(spot.lessons.map(\.subject.short)), ["DS"])

        XCTAssertEqual(spot.lesson(preferringGroup: "2/2")?.classroom, "18b")
    }

    // MARK: - Slučování do bloků

    func testMergesRepeatedCellsIntoOneBlock() throws {
        // Web nemá colspan: dvouhodinovka jsou dvě stejné sousední buňky.
        let monday = try XCTUnwrap(page.timetable.day(.monday))
        let block = try XCTUnwrap(monday.spot(atPeriod: 1))

        XCTAssertEqual(block.periodSpan, 2)
        XCTAssertEqual(block.periodRange, 1...2)
        XCTAssertIdentical2(monday.spot(atPeriod: 2), block)
    }

    func testDoesNotMergeCellsWithDifferentContent() throws {
        // V pondělí 6. hodinu má jedna skupina PSS a druhá A, sedmou už jen PSS.
        // Obsah se liší, takže z toho nesmí vzniknout jeden blok.
        let monday = try XCTUnwrap(page.timetable.day(.monday))
        let sixth = try XCTUnwrap(monday.spot(atPeriod: 6))
        let seventh = try XCTUnwrap(monday.spot(atPeriod: 7))

        XCTAssertEqual(sixth.periodSpan, 1)
        XCTAssertEqual(seventh.periodSpan, 1)
        XCTAssertEqual(Set(sixth.lessons.map(\.subject.short)), ["PSS", "A"])
        XCTAssertEqual(seventh.lessons.map(\.subject.short), ["PSS"])
    }

    func testSkipsPlaceholdersForGroupsWithoutLesson() throws {
        // Sedmá hodina v pondělí má druhý div jen jako výplň (lessonEmpty).
        let monday = try XCTUnwrap(page.timetable.day(.monday))
        let spot = try XCTUnwrap(monday.spot(atPeriod: 7))
        XCTAssertEqual(spot.lessons.count, 1)
    }

    func testMergesLateAfternoonBlock() throws {
        // Ve čtvrtek navazuje PSS v 8. a 9. hodině.
        let thursday = try XCTUnwrap(page.timetable.day(.thursday))
        let block = try XCTUnwrap(thursday.spot(atPeriod: 8))
        XCTAssertEqual(block.periodRange, 8...9)
        XCTAssertEqual(block.lessons.first?.subject.short, "PSS")
    }

    func testFreePeriodsStayEmpty() throws {
        // V úterý se první hodinu neučí a šestá je okno mezi výukou.
        let tuesday = try XCTUnwrap(page.timetable.day(.tuesday))
        XCTAssertTrue(try XCTUnwrap(tuesday.spot(atPeriod: 1)).isEmpty)
        XCTAssertTrue(try XCTUnwrap(tuesday.spot(atPeriod: 6)).isEmpty)
        XCTAssertFalse(try XCTUnwrap(tuesday.spot(atPeriod: 7)).isEmpty)
    }

    func testTrimsEmptyTailOfWeek() {
        // Nikdo se neučí do 10. hodiny, mřížka se má oříznout.
        XCTAssertEqual(page.timetable.occupiedPeriods.map(\.number), Array(1...9))
    }
}

private extension XCTestCase {
    /// Dvě buňky téhož bloku musí ukazovat na jeden a týž `LessonSpot`.
    func XCTAssertIdentical2(_ lhs: LessonSpot?, _ rhs: LessonSpot?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs?.id, rhs?.id, "Obě hodiny mají patřit do stejného bloku", file: file, line: line)
    }
}

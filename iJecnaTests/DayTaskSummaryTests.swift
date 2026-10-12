import XCTest
@testable import iJecna

/// Zkoušky toho, podle čeho se u dnů kreslí tečky a souhrny úkolů.
final class DayTaskSummaryTests: XCTestCase {

    private let calendar = Calendar.prague

    /// Pondělí 12. 10. 2026 v poledne, pražský čas.
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date.startOfSchoolDay(monday))!
    }

    private func task(_ kind: StudyTaskKind, done: Bool = false) -> StudyTask {
        StudyTask(kind: kind, title: "x", dueDate: day(0), isDone: done)
    }

    // MARK: - Souhrn dne

    func testCountsOnlyOpenTasksByKind() {
        let summary = DayTaskSummary(tasks: [
            task(.homework), task(.homework), task(.test), task(.note), task(.test, done: true),
        ])

        XCTAssertEqual(summary.count(of: .homework), 2)
        XCTAssertEqual(summary.count(of: .test), 1)
        XCTAssertEqual(summary.total, 4)
        XCTAssertTrue(summary.hasTest)
    }

    func testTestGoesFirst() {
        // Tečka za test musí být vidět vždycky, i když je úkolů víc.
        let summary = DayTaskSummary(tasks: [task(.note), task(.homework), task(.project), task(.test)])
        XCTAssertEqual(summary.kinds, [.test, .project, .homework, .note])
    }

    func testDoneDayIsEmpty() {
        let summary = DayTaskSummary(tasks: [task(.test, done: true)])
        XCTAssertTrue(summary.isEmpty)
        XCTAssertFalse(summary.hasTest)
        XCTAssertEqual(summary.kinds, [])
    }

    func testDescribesDayInWords() {
        let summary = DayTaskSummary(tasks: [task(.homework), task(.homework), task(.test)])
        XCTAssertEqual(summary.description, "1 test, 2 úkoly")
    }

    // MARK: - Čeština

    func testUsesCzechPluralForms() {
        XCTAssertEqual(StudyTaskKind.test.countLabel(1), "1 test")
        XCTAssertEqual(StudyTaskKind.test.countLabel(3), "3 testy")
        XCTAssertEqual(StudyTaskKind.test.countLabel(5), "5 testů")
        XCTAssertEqual(StudyTaskKind.homework.countLabel(2), "2 úkoly")
        XCTAssertEqual(StudyTaskKind.note.countLabel(1), "1 poznámka")
        XCTAssertEqual(StudyTaskKind.note.countLabel(7), "7 poznámek")
        XCTAssertEqual(StudyTaskKind.project.countLabel(4), "4 projekty")
    }

    // MARK: - Názvy dnů

    func testNamesDaysRelativeToToday() {
        XCTAssertEqual(day(0).relativeDayName(now: monday), "Dnes")
        XCTAssertEqual(day(1).relativeDayName(now: monday), "Zítra")
        XCTAssertEqual(day(-1).relativeDayName(now: monday), "Včera")
        XCTAssertEqual(day(3).relativeDayName(now: monday), "Čtvrtek")
    }

    func testRecognisesNextWeek() {
        // Týden začíná pondělím: neděle ještě patří k tomuhle týdnu.
        XCTAssertFalse(day(4).isInNextWeek(now: monday))
        XCTAssertFalse(day(6).isInNextWeek(now: monday))
        XCTAssertTrue(day(7).isInNextWeek(now: monday))
        XCTAssertTrue(day(13).isInNextWeek(now: monday))
        // Za dva týdny už to „příští týden“ není.
        XCTAssertFalse(day(14).isInNextWeek(now: monday))
    }

    func testShortWeekdayIncludesWeekend() {
        XCTAssertEqual(day(0).shortWeekdayName(), "Po")
        XCTAssertEqual(day(5).shortWeekdayName(), "So")
        XCTAssertEqual(day(6).shortWeekdayName(), "Ne")
        XCTAssertEqual(day(0).dayOfMonthLabel(), "12.")
    }
}

import XCTest
@testable import iJecna

/// Snímkové zkoušky parseru známek proti skutečné uložené stránce
/// za 2. pololetí 2025/2026 (98 známek ve dvanácti předmětech).
final class GradesParserTests: XCTestCase {

    private var page: GradesPage!

    override func setUpWithError() throws {
        page = try GradesPageParser.parse(Fixture.gradesPreviousYear.html())
    }

    // MARK: - Rozsah

    func testReadsAllSubjectsWithoutBehaviourRow() {
        // Řádek „Chování“ není předmět a nesmí se dostat mezi ně.
        XCTAssertEqual(page.subjects.count, 12)
        XCTAssertFalse(page.subjects.contains { $0.name.full == Behaviour.subjectName })
    }

    func testReadsEveryGrade() {
        XCTAssertEqual(page.totalGradeCount, 98)
    }

    func testReadsSelectedPeriod() {
        XCTAssertEqual(page.schoolYear, SchoolYear(2025))
        XCTAssertEqual(page.half, .second)
    }

    func testNormalisesSubjectNameWithDoubleSpace() throws {
        // Web má v názvu dvě mezery: „Tělesná  výchova (TV)“.
        let subject = try XCTUnwrap(page.subject(named: "Tělesná výchova"))
        XCTAssertEqual(subject.name.short, "TV")
    }

    // MARK: - Jedna známka

    func testReadsGradeDetails() throws {
        let subject = try XCTUnwrap(page.subject(named: "Český jazyk a literatura"))
        let grade = try XCTUnwrap(subject.allGrades.first { $0.id == 1261135 })

        XCTAssertEqual(grade.value, 2)
        XCTAssertFalse(grade.isSmall, "Známka bez třídy scoreSmall je velká")
        XCTAssertEqual(grade.weight, 2)
        XCTAssertEqual(grade.detail, "zkoušení - literatura")
        XCTAssertEqual(grade.teacher?.short, "SU")

        let date = try XCTUnwrap(grade.receivedAt)
        let parts = Calendar.prague.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual([parts.day, parts.month, parts.year], [27, 2, 2026])
    }

    func testReordersTeacherNameAndKeepsTitles() throws {
        // Na stránce známek stojí příjmení napřed a tituly na konci:
        // „Studénková Kristina, MUDr.“ — v rozvrhu je přitom pořadí opačné.
        let subject = try XCTUnwrap(page.subject(named: "Český jazyk a literatura"))
        let grade = try XCTUnwrap(subject.allGrades.first { $0.id == 1261135 })
        XCTAssertEqual(grade.teacher?.full, "MUDr. Kristina Studénková")
    }

    func testReadsTeacherWithoutTitles() throws {
        let subject = try XCTUnwrap(page.subject(named: "Elektronika a mikroelektronika"))
        let grade = try XCTUnwrap(subject.allGrades.first { $0.id == 1302501 })
        XCTAssertEqual(grade.teacher?.full, "Vratislav Němec")
    }

    func testReadsSmallGrade() throws {
        let subject = try XCTUnwrap(page.subject(named: "Český jazyk a literatura"))
        let grade = try XCTUnwrap(subject.allGrades.first { $0.id == 1275210 })
        XCTAssertTrue(grade.isSmall)
        XCTAssertEqual(grade.weight, 1)
        XCTAssertEqual(grade.value, 3)
    }

    func testGradeWithoutDescriptionHasNoDetail() throws {
        // Popisek pak obsahuje jen závorku s datem a učitelem.
        let subject = try XCTUnwrap(page.subject(named: "Matematika"))
        let grade = try XCTUnwrap(subject.allGrades.first { $0.id == 1256369 })
        XCTAssertNil(grade.detail)
        XCTAssertNotNil(grade.receivedAt)
        XCTAssertEqual(grade.value, 2)
    }

    // MARK: - Nepsal

    func testReadsNotWrittenGrade() throws {
        let subject = try XCTUnwrap(page.subject(named: "Fyzika"))
        let grade = try XCTUnwrap(subject.allGrades.first { $0.id == 1285991 })

        XCTAssertTrue(grade.isNotWritten)
        XCTAssertEqual(grade.value, 0)
        XCTAssertEqual(grade.label, "N")
        XCTAssertFalse(grade.countsTowardAverage)
    }

    func testNotWrittenGradeIsExcludedFromAverage() throws {
        let subject = try XCTUnwrap(page.subject(named: "Fyzika"))
        let withoutN = subject.allGrades.filter { !$0.isNotWritten }
        XCTAssertEqual(subject.average, Grade.weightedAverage(of: withoutN))
    }

    // MARK: - Části předmětu

    func testSplitsSubjectIntoParts() throws {
        let subject = try XCTUnwrap(page.subject(named: "Informační a komunikační technologie"))

        XCTAssertTrue(subject.isSplit)
        XCTAssertEqual(subject.parts.map(\.title), ["Cvičení", "Teorie"])
        XCTAssertEqual(subject.parts[0].grades.count, 13)
        XCTAssertEqual(subject.parts[1].grades.count, 6)
        XCTAssertEqual(subject.gradeCount, 19)
        XCTAssertTrue(subject.allGrades.allSatisfy { $0.subjectPart != nil })
    }

    func testSubjectWithoutPartsHasSingleUnnamedPart() throws {
        let subject = try XCTUnwrap(page.subject(named: "Matematika"))
        XCTAssertEqual(subject.parts.count, 1)
        XCTAssertNil(subject.parts[0].title)
        XCTAssertFalse(subject.isSplit)
    }

    // MARK: - Výsledné známky

    func testReadsFinalGrades() throws {
        XCTAssertEqual(page.subject(named: "Český jazyk a literatura")?.finalGrade, .grade(2))
        XCTAssertEqual(page.subject(named: "Anglický jazyk")?.finalGrade, .grade(1))
        XCTAssertEqual(page.subject(named: "Chemie")?.finalGrade, .grade(3))
    }

    func testKeepsNoteAttachedToFinalGrade() throws {
        // Popisek zní „výborný, Napomenutí za neklasifikace“ — hodnocení i dodatek.
        let subject = try XCTUnwrap(page.subject(named: "Multimédia a vývoj her"))
        XCTAssertEqual(subject.finalGrade, .grade(1))
        XCTAssertEqual(subject.finalGradeNote, "Napomenutí za neklasifikace")
    }

    func testSubjectWithoutNoteHasNone() {
        XCTAssertNil(page.subject(named: "Matematika")?.finalGradeNote)
    }

    // MARK: - Chování

    func testReadsBehaviour() {
        XCTAssertEqual(page.behaviour.finalGrade, .grade(1))
        XCTAssertTrue(page.behaviour.notificationIds.isEmpty)
    }

    // MARK: - Průměry

    func testComputesWeightedAverage() throws {
        // Ručně: (2·2 + 1·2 + 3·1 + 2·1 + 1·1 + 1·2 + 5·1 + 1·2 + 2·2) / 14 = 25/14
        let subject = try XCTUnwrap(page.subject(named: "Český jazyk a literatura"))
        XCTAssertEqual(try XCTUnwrap(subject.average), 25.0 / 14.0, accuracy: 0.0001)
        XCTAssertEqual(subject.average?.averageFormatted, "1.79")
    }

    // MARK: - Prázdná stránka

    func testHandlesStartOfYearWithNoGrades() throws {
        // Stránka z 3. září: předměty existují, známky ještě ne.
        let empty = try GradesPageParser.parse(Fixture.grades.html())

        XCTAssertEqual(empty.totalGradeCount, 0)
        XCTAssertFalse(empty.subjects.isEmpty)
        XCTAssertNil(empty.overallAverage, "Bez známek nemá průměr existovat")
        XCTAssertEqual(empty.schoolYear, SchoolYear(2026))
        XCTAssertEqual(empty.half, .first)

        // Dělení na části je v šabloně i bez známek.
        let split = try XCTUnwrap(empty.subject(named: "Programové vybavení"))
        XCTAssertEqual(split.parts.map(\.title), ["Cvičení", "Teorie"])
        XCTAssertTrue(split.isEmpty)
    }
}

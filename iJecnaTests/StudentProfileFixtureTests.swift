import XCTest
@testable import iJecna

/// Snímkové zkoušky profilu studenta proti skutečné stránce.
///
/// Právě tady se dřív ztrácela třída a e-mail: popisky na stránce se jmenují
/// jinak, než jsem odhadoval podle profilu učitele.
final class StudentProfileFixtureTests: XCTestCase {

    private var student: Student!

    override func setUpWithError() throws {
        student = try StudentProfileParser.parse(Fixture.studentProfile.html(), username: "mytrofanov")
    }

    // MARK: - Základ

    func testReadsNameInCorrectOrder() {
        // Tabulka uvádí „Celé jméno“ rovnou správně; nadpis stránky obráceně.
        XCTAssertEqual(student.fullName, "Ivan Mytrofanov")
        XCTAssertEqual(student.initials, "IM")
    }

    func testReadsUsername() {
        XCTAssertEqual(student.username, "mytrofanov")
    }

    func testReadsSchoolMailWithoutTrailingNote() {
        // Hodnota v tabulce zní „mytrofanov@spsejecna.cz (přeposílán na soukromý).“
        // Spolehlivá je adresa z odkazu, ne text buňky.
        XCTAssertEqual(student.schoolMail, "mytrofanov@spsejecna.cz")
    }

    // MARK: - Třída a skupiny

    func testReadsClassFromCombinedRow() {
        // Popisek je „Třída, skupiny“ a hodnota „C3c, skupiny: A2“.
        XCTAssertEqual(student.className, "C3c")
        XCTAssertEqual(student.classGroups, "A2")
    }

    func testSplitsClassAndGroups() {
        XCTAssertEqual(StudentProfileParser.parseClassAndGroups("C3c, skupiny: A2").className, "C3c")
        XCTAssertEqual(StudentProfileParser.parseClassAndGroups("C3c, skupiny: A2").groups, "A2")

        // Bez výčtu skupin zůstane jen třída.
        XCTAssertEqual(StudentProfileParser.parseClassAndGroups("C3c").className, "C3c")
        XCTAssertNil(StudentProfileParser.parseClassAndGroups("C3c").groups)
        XCTAssertNil(StudentProfileParser.parseClassAndGroups(nil).className)
    }

    // MARK: - Narození

    func testSplitsBirthDateAndPlace() throws {
        // Web má v jedné buňce „02.05.2008, DNĚPROPETROVSK“.
        let date = Calendar.prague.dateComponents([.year, .month, .day], from: try XCTUnwrap(student.birthDate))
        XCTAssertEqual([date.day, date.month, date.year], [2, 5, 2008])
        XCTAssertEqual(student.birthPlace, "DNĚPROPETROVSK")
    }

    func testBirthWithoutPlace() {
        let birth = StudentProfileParser.parseBirth("1.1.2000")
        XCTAssertNotNil(birth.date)
        XCTAssertNil(birth.place)
    }

    // MARK: - Ostatní údaje

    func testReadsAddressAndPhoto() {
        XCTAssertEqual(student.permanentAddress, "Pod Balkánem 522, Praha 9, 19000")
        XCTAssertEqual(student.profilePicturePath, "/img/thumbnail/IMG-1dea11mb.JPG")
    }

    func testKeepsEveryRowIncludingUnnamedOnes() {
        // Stránka má dvě tabulky profilu; obě se čtou celé.
        XCTAssertEqual(student.details.count, 16)
        XCTAssertTrue(student.details.contains { $0.label == "Číslo v tříd. výkazu" })
        XCTAssertTrue(student.details.contains { $0.label == "Bankovní účet" })
    }

    func testRepeatedLabelsGetDistinctIdentity() {
        // „Uživatelské jméno“ je na stránce dvakrát; v seznamu se nesmí srazit.
        let repeated = student.details.filter { $0.label == "Uživatelské jméno" }
        XCTAssertEqual(repeated.count, 2)
        XCTAssertEqual(Set(student.details.map(\.id)).count, student.details.count)
    }

    func testDoesNotMistakeClassBreadcrumbForName() throws {
        // Na profilu odkazuje drobečková navigace na třídu (/trida/C3c).
        // Kdyby se brala jako jméno, student by se jmenoval „C3c“.
        XCTAssertNotEqual(student.fullName, "C3c")
    }
}

import XCTest
@testable import iJecna

/// Snímkové zkoušky profilu učitele, seznamu učeben a skříňky.
final class PeopleAndRoomsParserTests: XCTestCase {

    // MARK: - Profil učitele

    func testReadsTeacherProfile() throws {
        let teacher = try TeacherParser.parse(Fixture.teacherDetail.html(), tag: "BU")

        XCTAssertEqual(teacher.fullName, "Mgr. Lenka Brůnová")
        XCTAssertEqual(teacher.tag, "Bu")
        XCTAssertEqual(teacher.username, "brunova")
        XCTAssertEqual(teacher.schoolMail, "brunova@spsejecna.cz")
        XCTAssertEqual(teacher.cabinet, "Sborovna")
    }

    func testReadsTeacherPhoneWithExtension() throws {
        // Telefon je volný text včetně linky, drží se tak, jak ho web píše.
        let teacher = try TeacherParser.parse(Fixture.teacherDetail.html(), tag: "BU")
        let phone = try XCTUnwrap(teacher.phoneNumbers.first)
        XCTAssertTrue(phone.contains("224 941 469"))
        XCTAssertTrue(phone.contains("106"))
    }

    func testReadsConsultationHours() throws {
        let teacher = try TeacherParser.parse(Fixture.teacherDetail.html(), tag: "BU")
        XCTAssertTrue(try XCTUnwrap(teacher.consultationHours).contains("Fridays"))
    }

    func testTeacherWithoutClassHasNoTutorship() throws {
        let teacher = try TeacherParser.parse(Fixture.teacherDetail.html(), tag: "BU")
        XCTAssertNil(teacher.tutorOfClass)
    }

    func testRejectsPageWithoutTeacherName() {
        XCTAssertThrowsError(try TeacherParser.parse("<html><body></body></html>", tag: "XX"))
    }

    // MARK: - Učebny

    func testReadsRoomList() throws {
        let rooms = try RoomsPageParser.parse(Fixture.rooms.html())
        XCTAssertGreaterThan(rooms.count, 20)
        XCTAssertEqual(rooms.first?.roomCode, "1")
        XCTAssertEqual(Set(rooms.map(\.roomCode)).count, rooms.count, "Kódy učeben se nesmí opakovat")
    }

    func testReadsHomeroomWithClassAndManager() throws {
        // „Učebna 1 (A2b, Ing. Dušan Kuchařík)“
        let rooms = try RoomsPageParser.parse(Fixture.rooms.html())
        let room = try XCTUnwrap(rooms.first { $0.roomCode == "1" })

        XCTAssertEqual(room.name, "Učebna 1")
        XCTAssertEqual(room.homeroomOf, "A2b")
        XCTAssertEqual(room.manager, "Ing. Dušan Kuchařík")
    }

    func testReadsRoomWithOnlyManager() throws {
        // „Učebna 5a (Správce: Mgr. Marie Kmoníčková)“ — není ničí kmenová.
        let rooms = try RoomsPageParser.parse(Fixture.rooms.html())
        let room = try XCTUnwrap(rooms.first { $0.roomCode == "5a" })

        XCTAssertEqual(room.name, "Učebna 5a")
        XCTAssertNil(room.homeroomOf)
        XCTAssertEqual(room.manager, "Mgr. Marie Kmoníčková")
    }

    func testRoomLabelWithoutParentheses() {
        let parsed = RoomsPageParser.parseLabel("Tělocvična")
        XCTAssertEqual(parsed.name, "Tělocvična")
        XCTAssertNil(parsed.homeroom)
        XCTAssertNil(parsed.manager)
    }

    // MARK: - Skříňka

    func testReadsLocker() throws {
        let locker = try XCTUnwrap(try LockerPageParser.parse(Fixture.locker.html()))

        XCTAssertEqual(locker.number, "469")
        XCTAssertEqual(locker.location, "1. patro - mezi učebnou 2 a 3")

        let from = Calendar.prague.dateComponents([.year, .month, .day], from: try XCTUnwrap(locker.assignedFrom))
        XCTAssertEqual([from.day, from.month, from.year], [1, 9, 2024])

        // „do současnosti“ znamená, že skříňka je pořád přidělená.
        XCTAssertNil(locker.assignedUntil)
    }

    func testReadsLockerWithEndDate() throws {
        let locker = try XCTUnwrap(
            LockerPageParser.parseLabel("Novák Jan skříňka č. 12 (přízemí) od 1.9.2023 do 30.6.2024")
        )
        XCTAssertEqual(locker.number, "12")
        XCTAssertEqual(locker.location, "přízemí")
        XCTAssertNotNil(locker.assignedUntil)
    }

    func testStudentWithoutLockerIsNotAnError() throws {
        // Nemít skříňku je běžný stav, ne porucha stránky.
        let html = "<html><body><main><div class=\"column-center\"></div></main></body></html>"
        XCTAssertNil(try LockerPageParser.parse(html))
    }
}

import XCTest
@testable import iJecna

/// Zkoušky mimořádného rozvrhu proti uložené odpovědi služby.
final class SubstitutionTests: XCTestCase {

    private var response: SubstitutionService.APIResponse!

    override func setUpWithError() throws {
        let data = try Data(contentsOf: Fixture.substitutions.url)
        response = try JSONDecoder().decode(SubstitutionService.APIResponse.self, from: data)
    }

    private func schedule(for className: String = "C3c") -> SubstitutionSchedule {
        SubstitutionService.schedule(from: response, className: className)
    }

    // MARK: - Základ

    func testReadsProviderStatus() {
        XCTAssertEqual(response.status.lastUpdated, "19:00")
        XCTAssertEqual(response.status.currentUpdateSchedule, 180)
    }

    func testReadsAllDays() {
        let schedule = self.schedule()
        XCTAssertEqual(schedule.days.count, 2)
        // Dny musí být seřazené, obrazovka je bere v pořadí.
        XCTAssertEqual(schedule.days, schedule.days.sorted { $0.date < $1.date })
    }

    func testReadsDayNote() throws {
        let schedule = self.schedule()
        let day = try XCTUnwrap(schedule.days.last)
        XCTAssertEqual(day.note, "Písemná maturitní práce z ČJ v učebnách K7 a 20 od 8.00 (Kt, Kp)")
    }

    func testEmptyNoteBecomesNil() throws {
        // Prázdný řetězec z tabulky se nesmí ukázat jako prázdný řádek.
        let day = try XCTUnwrap(schedule().days.first)
        XCTAssertNil(day.note)
    }

    func testReadsPreparationFlag() throws {
        // `inWork` znamená rozpracovaný den, ne volno: 3. 9. se normálně učilo
        // a suplovalo, 4. 9. byl v tabulce teprve v přípravě.
        let days = schedule().days
        XCTAssertFalse(try XCTUnwrap(days.first).isInPreparation)
        XCTAssertTrue(try XCTUnwrap(days.last).isInPreparation)
    }

    // MARK: - Změny pro třídu

    func testFindsChangeForOwnClass() throws {
        let day = try XCTUnwrap(schedule(for: "C3c").days.first)

        // C3c má změnu v páté hodině: „TV He(Lc)+“.
        let change = try XCTUnwrap(day.change(forPeriod: 5))
        XCTAssertEqual(change.text, "TV He(Lc)+")
        XCTAssertEqual(change.displayText, "TV He(Lc)")
        XCTAssertTrue(change.isConfirmed)

        XCTAssertNil(day.change(forPeriod: 1))
        XCTAssertNil(day.change(forPeriod: 10))
    }

    func testFindsChangeAnywhereInBlock() throws {
        // Dvouhodinovka musí najít změnu i když padne až na druhou hodinu.
        let day = try XCTUnwrap(schedule(for: "C3c").days.first)
        XCTAssertNotNil(day.change(forPeriods: 4...5))
        XCTAssertNil(day.change(forPeriods: 1...3))
    }

    func testFiltersToRequestedClassOnly() throws {
        // A1a má změny v prvních dvou hodinách, C3c ne — a naopak.
        let a1a = try XCTUnwrap(schedule(for: "A1a").days.first)
        XCTAssertEqual(a1a.change(forPeriod: 1)?.text, "ZE 2 Ht(Mu)+")
        XCTAssertNil(a1a.change(forPeriod: 5))
    }

    func testUnknownClassHasNoChanges() throws {
        let day = try XCTUnwrap(schedule(for: "X9z").days.first)
        XCTAssertTrue(day.changes.isEmpty)
        XCTAssertNil(day.change(forPeriod: 1))
    }

    // MARK: - Odpadlé hodiny

    func testRecognisesCancelledLesson() {
        // Tabulku píše každý zástupce trochu jinak, poznat se musí všechny podoby.
        for text in ["odpadá", "Odpadá+", "ODPADÁ", "TV odpadá", "odp.", "-", "—", "×",
                     "nekoná se", "nevyučuje se", "zrušeno", "bez výuky"] {
            XCTAssertTrue(change(text).isCancelled, "„\(text)“ má být odpadlá hodina")
        }
    }

    func testSubstitutionIsNotCancelled() {
        // Suplovaná hodina se učí dál — nesmí spadnout do odpadlých.
        for text in ["TV He(Lc)+", "M 16 Ng(Jr)+", "CEL D2,L3 Pr,Zn(Sy) rozděl.", "2/2 IT 17b Ms(Jz)+", ""] {
            XCTAssertFalse(change(text).isCancelled, "„\(text)“ nemá být odpadlá hodina")
        }
    }

    func testCountsCancelledLessonsOfDay() {
        let day = SubstitutionDay(
            date: .now,
            isInPreparation: false,
            changes: [change("odpadá"), nil, change("TV He(Lc)+"), change("ANJ odpadá+")],
            absences: [], note: nil, announcements: []
        )
        XCTAssertEqual(day.cancelledCount, 2)
    }

    // MARK: - Skupiny

    func testReadsGroupOfChange() {
        XCTAssertEqual(change("2/2 IT 17b Ms(Jz)+").groupNumber, 2)
        XCTAssertEqual(change("1/2 odpadá").groupNumber, 1)
        // Číslo učebny není skupina.
        XCTAssertNil(change("C 14 Ja(Mr)+").groupNumber)
        XCTAssertNil(change("TV He(Lc)+").groupNumber)
        XCTAssertEqual(change("2/2 IT 17b Ms(Jz)+").textWithoutGroup, "IT 17b Ms(Jz)")
    }

    func testChangeForOtherGroupDoesNotApply() {
        let groupChange = change("2/2 odpadá")
        XCTAssertTrue(groupChange.applies(toGroup: 2))
        XCTAssertFalse(groupChange.applies(toGroup: 1))
        // Neznámá skupina: radši ukázat.
        XCTAssertTrue(groupChange.applies(toGroup: nil))
        // Změna pro celou třídu platí pro každou skupinu.
        XCTAssertTrue(change("TV He(Lc)+").applies(toGroup: 1))
    }

    func testGroupPrefixDoesNotHideCancelledMark() {
        XCTAssertTrue(change("1/2 -").isCancelled)
        XCTAssertTrue(change("2/2 odp.").isCancelled)
    }

    func testLooksUpChangeForOwnGroupOnly() {
        let day = SubstitutionDay(
            date: .now,
            isInPreparation: false,
            changes: [change("2/2 odpadá"), change("1/2 odpadá"), change("C 14 Ja(Mr)+")],
            absences: [], note: nil, announcements: []
        )
        XCTAssertNil(day.change(forPeriods: 1...1, group: 1))
        XCTAssertEqual(day.otherGroupChange(forPeriods: 1...1, group: 1)?.text, "2/2 odpadá")
        XCTAssertEqual(day.change(forPeriods: 1...2, group: 1)?.text, "1/2 odpadá")
        XCTAssertEqual(day.change(forPeriods: 3...3, group: 1)?.text, "C 14 Ja(Mr)+")
        XCTAssertNil(day.otherGroupChange(forPeriods: 1...1, group: nil))

        XCTAssertEqual(day.cancelledCount(forGroup: 1), 1)
        XCTAssertEqual(day.cancelledCount, 2)
    }

    // MARK: - Hodiny navíc

    func testFindsChangesInFreePeriods() {
        let timetableDay = TimetableDay(weekday: .monday, spots: [
            LessonSpot(startPeriod: 1, lessons: [Lesson(subject: DisplayName("Matematika", short: "M"))]),
            .empty(at: 2), .empty(at: 3), .empty(at: 4), .empty(at: 5),
        ])
        let day = SubstitutionDay(
            date: .now,
            isInPreparation: false,
            changes: [
                change("M 16 Ng(Jr)+"),          // 1. hodina je v rozvrhu — obyčejná změna
                change("CEL D2 Pr(Sy)"),        // 2.–3. stejná buňka = jeden blok
                change("CEL D2 Pr(Sy)"),
                change("odpadá"),               // volná hodina nemá co odpadnout
                change("1/2 IT 17b Ms(Jz)+"),   // jen pro první skupinu
            ],
            absences: [], note: nil, announcements: []
        )

        let extras = day.extraLessons(outside: timetableDay, group: 2)
        XCTAssertEqual(extras.map(\.periods), [2...3])
        XCTAssertEqual(extras.first?.change.displayText, "CEL D2 Pr(Sy)")

        XCTAssertEqual(day.extraLessons(outside: timetableDay, group: 1).map(\.periods), [2...3, 5...5])
    }

    func testReadsSubjectAbbreviationOfChange() {
        XCTAssertEqual(change("2/2 IT 17b Ms(Jz)+").subjectAbbreviation, "IT")
        XCTAssertEqual(change("A 16 \nHo(Jr)+").subjectAbbreviation, "A")
    }

    func testCollapsesWhitespaceInCellText() {
        XCTAssertEqual(change("A 1                    Ju(Jr)+").displayText, "A 1 Ju(Jr)")
        XCTAssertEqual(change("A 16 \nHo(Jr)+").displayText, "A 16 Ho(Jr)")
    }

    private func change(_ text: String) -> SubstitutionChange {
        SubstitutionChange(text: text, backgroundColor: nil, foregroundColor: nil, willBeSpecified: nil)
    }

    // MARK: - Absence učitelů

    func testReadsWholeDayAbsence() throws {
        let day = try XCTUnwrap(schedule().days.first)
        XCTAssertEqual(day.absences.count, 6)

        let absence = try XCTUnwrap(day.absences.first)
        XCTAssertEqual(absence.kind, .wholeDay)
        XCTAssertEqual(absence.teacherCode, "jr")
        XCTAssertEqual(absence.displayName, "Doc. Ing. Vítězslav Jeřábek, CSc.")
        // U celodenní absence tabulka rozsah hodin neuvádí.
        XCTAssertNil(absence.hours)
        XCTAssertEqual(absence.scopeDescription, "celý den")
    }

    func testAbsenceHoursAreReadInBothForms() throws {
        // Rozsah přichází jednou jako číslo, jindy jako rozmezí.
        let single = try decodeAbsence(#"{"type":"single","teacher":"A","teacherCode":"aa","hours":3}"#)
        XCTAssertEqual(single.hours, .single(3))
        XCTAssertEqual(single.scopeDescription, "3. hodinu")

        let range = try decodeAbsence(#"{"type":"range","teacher":"B","teacherCode":"bb","hours":{"from":2,"to":4}}"#)
        XCTAssertEqual(range.hours, .range(from: 2, to: 4))
        XCTAssertEqual(range.scopeDescription, "2.–4. hodinu")
    }

    func testReadsSubstituteTeacher() throws {
        let absence = try decodeAbsence(
            #"{"type":"zastoupen","teacher":"C","teacherCode":"cc","hours":null,"zastupuje":{"teacher":"D","teacherCode":"dd"}}"#
        )
        XCTAssertEqual(absence.substituteCode, "dd")
        XCTAssertEqual(absence.scopeDescription, "zastupuje dd")
    }

    func testUnknownAbsenceTypeDoesNotThrow() throws {
        // Neznámý druh nesmí shodit celý den, jen se označí jako neurčený.
        let absence = try decodeAbsence(#"{"type":"neco_noveho","teacherCode":"xx","hours":null}"#)
        XCTAssertEqual(absence.kind, .invalid)
        XCTAssertEqual(absence.teacherCode, "xx")
    }

    private func decodeAbsence(_ json: String) throws -> TeacherAbsence {
        try JSONDecoder().decode(TeacherAbsence.self, from: Data(json.utf8))
    }

    // MARK: - Výběr dne

    func testFindsDayByDate() throws {
        let schedule = self.schedule()
        let date = try XCTUnwrap(SubstitutionService.date(from: "2026-09-04"))
        XCTAssertEqual(schedule.day(on: date)?.note?.isEmpty, false)
        XCTAssertNil(schedule.day(on: Date(timeIntervalSince1970: 0)))
    }

    func testDayWithNothingIsRecognised() {
        let empty = SubstitutionDay(
            date: .now, isInPreparation: false, changes: [nil, nil],
            absences: [], note: nil, announcements: []
        )
        XCTAssertFalse(empty.hasAnything)
    }
}

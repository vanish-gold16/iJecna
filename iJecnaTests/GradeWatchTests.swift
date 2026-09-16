import XCTest
@testable import iJecna

/// Zkoušky rozpoznávání nových známek.
///
/// Tohle je jádro upozornění: Ječna žádné „přečteno“ nezná, takže se rozdíl
/// počítá proti tomu, co jsme viděli naposledy. Chyba tady znamená buď mlčení
/// o nové známce, nebo opakované hlášení té samé.
@MainActor
final class GradeWatchTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "GradeWatchTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func tracker() -> NewGradesTracker {
        NewGradesTracker(defaults: defaults)
    }

    private func page(gradeIds: [Int]) -> GradesPage {
        let grades = gradeIds.map {
            Grade(id: $0, value: 1, isSmall: false, teacher: nil, detail: nil, receivedAt: .now, subjectPart: nil)
        }
        return GradesPage(
            subjects: [Subject(name: DisplayName("Matematika", short: "MAT"),
                               parts: [SubjectPart(title: nil, grades: grades)],
                               finalGrade: nil)],
            behaviour: Behaviour(finalGrade: nil, notificationIds: []),
            schoolYear: .current,
            half: .current
        )
    }

    // MARK: - První spuštění

    func testFirstRunAnnouncesNothing() {
        // Jinak by student při instalaci dostal upozornění na celý půlrok zpětně.
        let tracker = self.tracker()
        let fresh = tracker.register(page(gradeIds: [1, 2, 3]))

        XCTAssertTrue(fresh.isEmpty)
        XCTAssertFalse(tracker.hasUnseen)
        XCTAssertEqual(tracker.seenIds, [1, 2, 3])
    }

    // MARK: - Nová známka

    func testDetectsNewGrade() {
        let tracker = self.tracker()
        tracker.register(page(gradeIds: [1, 2]))

        let fresh = tracker.register(page(gradeIds: [1, 2, 3]))

        XCTAssertEqual(fresh.map(\.id), [3])
        XCTAssertTrue(tracker.hasUnseen)
        XCTAssertEqual(tracker.unseenCount, 1)
    }

    func testDoesNotAnnounceSameGradeTwice() {
        // Dokud se student do aplikace nepodívá, zůstává známka nepřečtená.
        // Bez zvláštní evidence odeslaných upozornění by ji každá kontrola
        // na pozadí ohlásila znovu.
        let tracker = self.tracker()
        tracker.register(page(gradeIds: [1]))

        let first = tracker.register(page(gradeIds: [1, 2]))
        XCTAssertEqual(first.map(\.id), [2])
        tracker.markNotified(first)

        let second = tracker.register(page(gradeIds: [1, 2]))
        XCTAssertTrue(second.isEmpty, "Táž známka se nesmí hlásit podruhé")
        XCTAssertTrue(tracker.hasUnseen, "Odznak ale musí zůstat, student ji ještě neviděl")
    }

    func testViewingGradesClearsBadge() {
        let tracker = self.tracker()
        tracker.register(page(gradeIds: [1]))
        tracker.register(page(gradeIds: [1, 2]))

        tracker.markAllSeen()

        XCTAssertFalse(tracker.hasUnseen)
        XCTAssertTrue(tracker.register(page(gradeIds: [1, 2])).isEmpty)
    }

    func testRemovedGradeDoesNotReappear() {
        // Učitel může známku smazat; když ji pak vrátí, je to pro nás stará známka.
        let tracker = self.tracker()
        tracker.register(page(gradeIds: [1, 2]))

        XCTAssertTrue(tracker.register(page(gradeIds: [1])).isEmpty)
        XCTAssertTrue(tracker.register(page(gradeIds: [1, 2])).isEmpty)
    }

    // MARK: - Trvalost

    func testStateSurvivesRestart() {
        let first = tracker()
        first.register(page(gradeIds: [1, 2]))
        let fresh = first.register(page(gradeIds: [1, 2, 3]))
        first.markNotified(fresh)

        // Nová instance čte tentýž stav — po restartu aplikace se nesmí
        // ohlásit znovu.
        let second = tracker()
        XCTAssertTrue(second.register(page(gradeIds: [1, 2, 3])).isEmpty)
    }

    // MARK: - Text upozornění

    func testNotificationBodyDescribesGrade() {
        let grade = Grade(id: 1, value: 2, isSmall: false, teacher: nil,
                          detail: "Písemka — logaritmy", receivedAt: .now, subjectPart: nil)
        let body = SchoolWatcher.body(for: .init(subject: DisplayName("Matematika", short: "MAT"), grade: grade))

        XCTAssertTrue(body.contains("Známka 2"))
        XCTAssertTrue(body.contains("Písemka — logaritmy"))
        XCTAssertTrue(body.contains("velká známka"))
    }

    func testNotificationBodyHandlesNotWritten() {
        let grade = Grade(id: 1, value: 0, isSmall: true, teacher: nil,
                          detail: nil, receivedAt: .now, subjectPart: nil)
        let body = SchoolWatcher.body(for: .init(subject: DisplayName("Fyzika"), grade: grade))

        XCTAssertTrue(body.contains("Nepsal"))
        XCTAssertFalse(body.contains("Známka 0"))
    }

    // MARK: - Plánování na pozadí

    func testBackgroundIntervalIsReasonable() {
        // Systém si interval stejně protáhne; hodina je prosba, ne příkaz.
        XCTAssertEqual(BackgroundRefresh.preferredInterval, 3600)
        XCTAssertEqual(BackgroundRefresh.taskIdentifier, "mytrofanov.iJecna.refresh")
    }
}

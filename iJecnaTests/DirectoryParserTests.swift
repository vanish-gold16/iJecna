import XCTest
@testable import iJecna

/// Snímkové zkoušky parserů novinek, učitelského sboru a sdělení rodičům.
final class DirectoryParserTests: XCTestCase {

    /// Pevný okamžik, aby odvozování roku u novinek nezáviselo na dni zkoušky.
    private let now = JecnaDate.fromNumeric("03.09.2026")!

    // MARK: - Aktuality

    func testReadsAllArticles() throws {
        let articles = try NewsPageParser.parse(Fixture.news.html(), now: now)
        XCTAssertEqual(articles.count, 9)
        // Pořadí na stránce je od nejnovější a nemá se měnit.
        XCTAssertEqual(articles.map(\.id).prefix(3), [3282, 3278, 3275])
    }

    func testReadsArticleDetails() throws {
        let articles = try NewsPageParser.parse(Fixture.news.html(), now: now)
        let article = try XCTUnwrap(articles.first { $0.id == 3282 })

        XCTAssertEqual(article.title, "Univerzita obrany")
        XCTAssertEqual(article.author, "Hana Budská")
        XCTAssertFalse(article.schoolOnly)
        XCTAssertTrue(article.content.contains("Defence Technology"))

        let date = Calendar.prague.dateComponents([.year, .month, .day], from: article.date)
        XCTAssertEqual([date.day, date.month, date.year], [3, 9, 2026])
    }

    func testDetectsSchoolOnlyArticles() throws {
        let articles = try NewsPageParser.parse(Fixture.news.html(), now: now)
        XCTAssertTrue(try XCTUnwrap(articles.first { $0.id == 3278 }).schoolOnly)
        XCTAssertFalse(try XCTUnwrap(articles.first { $0.id == 3277 }).schoolOnly)
    }

    func testResolvesYearForArticleFromPreviousMonth() throws {
        // Patička uvádí jen „15.srpna“ bez roku.
        let articles = try NewsPageParser.parse(Fixture.news.html(), now: now)
        let article = try XCTUnwrap(articles.first { $0.id == 3276 })
        let date = Calendar.prague.dateComponents([.year, .month, .day], from: article.date)
        XCTAssertEqual([date.day, date.month, date.year], [15, 8, 2026])
    }

    func testReadsAttachmentsFromArticleBody() throws {
        // Přílohy nemají vlastní blok, jsou to odkazy na /download/ uvnitř textu.
        let articles = try NewsPageParser.parse(Fixture.news.html(), now: now)
        let article = try XCTUnwrap(articles.first { $0.id == 3275 })

        XCTAssertEqual(article.attachments.count, 1)
        let attachment = try XCTUnwrap(article.attachments.first)
        XCTAssertTrue(attachment.downloadPath.hasPrefix("/download/"))
        XCTAssertEqual(attachment.fileExtension, "PDF")
        XCTAssertFalse(attachment.label.isEmpty)
    }

    func testArticlesWithoutAttachmentsHaveNone() throws {
        let articles = try NewsPageParser.parse(Fixture.news.html(), now: now)
        XCTAssertTrue(try XCTUnwrap(articles.first { $0.id == 3282 }).attachments.isEmpty)
    }

    // MARK: - Učitelé

    func testReadsWholeTeachingStaff() throws {
        let teachers = try TeachersPageParser.parse(Fixture.teachers.html())

        // Seznam je na stránce ve dvou sloupcích a musí se spojit do jednoho.
        XCTAssertEqual(teachers.count, 65)
        XCTAssertEqual(teachers.first?.tag, "AD")
        XCTAssertEqual(teachers.first?.fullName, "Bc. Daniel Adámek")
        XCTAssertEqual(teachers.last?.tag, "ZN")
    }

    func testTeacherTagsAreUnique() throws {
        let teachers = try TeachersPageParser.parse(Fixture.teachers.html())
        XCTAssertEqual(Set(teachers.map(\.tag)).count, teachers.count)
    }

    func testDerivesSortKeyFromSurname() throws {
        let teachers = try TeachersPageParser.parse(Fixture.teachers.html())
        let teacher = try XCTUnwrap(teachers.first { $0.tag == "AD" })
        // Tituly se do řazení nesmí počítat.
        XCTAssertEqual(teacher.sortKey, "Adámek")
        XCTAssertEqual(teacher.initials, "DA")
    }

    func testRejectsPageWithoutTeachers() {
        XCTAssertThrowsError(try TeachersPageParser.parse("<html><body></body></html>"))
    }

    // MARK: - Sdělení rodičům

    func testReadsNotifications() throws {
        let notifications = try NotificationsPageParser.parse(Fixture.notifications.html())
        XCTAssertEqual(notifications.count, 1)

        let record = try XCTUnwrap(notifications.first)
        XCTAssertEqual(record.id, 7314)
        XCTAssertEqual(record.kind, .good)
        XCTAssertEqual(record.exactType, "Pochvala tř. učitele")
        XCTAssertEqual(record.caseNumber, "SPSE/00179/2025")

        let date = Calendar.prague.dateComponents([.year, .month, .day], from: record.date)
        XCTAssertEqual([date.day, date.month, date.year], [30, 1, 2025])
    }

    func testParsesLabelWithoutCaseNumber() {
        let fields = NotificationsPageParser.parseLabel("12.5.2026, Napomenutí třídního učitele")
        XCTAssertNil(fields.caseNumber)
        XCTAssertEqual(fields.type, "Napomenutí třídního učitele")
        XCTAssertNotNil(fields.date)
    }

    func testKeepsCommasInsideNotificationType() {
        // Druh sdělení může sám obsahovat čárku a nesmí se o ni rozpadnout.
        let fields = NotificationsPageParser.parseLabel(
            "1.3.2026, č.j. SPSE/00042/2026, Důtka ředitele školy, opakovaně"
        )
        XCTAssertEqual(fields.caseNumber, "SPSE/00042/2026")
        XCTAssertEqual(fields.type, "Důtka ředitele školy, opakovaně")
    }

    func testEmptyNotificationListIsNotAnError() throws {
        // Student bez jediného záznamu je běžný stav, ne porucha.
        let html = "<html><body><main><div class=\"column-center\"></div></main></body></html>"
        XCTAssertEqual(try NotificationsPageParser.parse(html).count, 0)
    }
}

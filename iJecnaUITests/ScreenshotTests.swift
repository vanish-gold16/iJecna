import XCTest

/// Projde hlavní obrazovky a uloží snímky.
///
/// Slouží jako kouřová zkouška navigace i jako zdroj obrázků pro revizi návrhu.
/// Snímky se ukládají do dočasné složky simulátoru, odkud se dají vyzvednout
/// z hostitelského systému.
final class ScreenshotTests: XCTestCase {

    private var outputDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ijecna-shots")
    }

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func launchApp(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["INITIAL_TAB"] = tab
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSubjectDetailAndPredictor() throws {
        let app = launchApp(tab: "grades")

        let subject = app.staticTexts["Matematika"]
        XCTAssertTrue(subject.waitForExistence(timeout: 10), "Seznam předmětů se nenačetl")
        subject.tap()

        let header = app.staticTexts["Vážený průměr"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Detail předmětu se neotevřel")
        capture("20-detail-predmetu")

        let predictorButton = app.buttons["Zkusit"]
        XCTAssertTrue(predictorButton.waitForExistence(timeout: 5), "Chybí přepínač predikce")
        predictorButton.tap()

        let newAverage = app.staticTexts["Nový průměr"]
        XCTAssertTrue(newAverage.waitForExistence(timeout: 5), "Predikce se nezobrazila")
        capture("21-predikce")
    }

    func testDirectoryScreens() throws {
        let app = launchApp(tab: "more")

        let teachers = app.staticTexts["Učitelé"]
        XCTAssertTrue(teachers.waitForExistence(timeout: 10), "Rozcestník se nenačetl")
        teachers.tap()

        let firstTeacher = app.staticTexts["Mgr. Adam Beneš"]
        XCTAssertTrue(firstTeacher.waitForExistence(timeout: 5), "Seznam učitelů se nenačetl")
        capture("22-ucitele")

        firstTeacher.tap()
        capture("23-detail-ucitele")
    }

    func testNotificationsScreen() throws {
        let app = launchApp(tab: "more")

        let notifications = app.staticTexts["Poznámky a pochvaly"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()

        let record = app.staticTexts["Pochvala třídního učitele"]
        XCTAssertTrue(record.waitForExistence(timeout: 5), "Poznámky se nenačetly")
        capture("24-poznamky")
    }
}

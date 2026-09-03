import Foundation
import SwiftSoup

/// Čte stránku `/timetable/class`.
///
/// Rozvrh je tabulka: v hlavičce vyučovací hodiny, v každém řádku jeden den.
/// Zásadní vlastnost je, že **web nepoužívá `colspan`** — dvouhodinovka se
/// zapíše jako dvě sousední buňky se stejným obsahem. Bloky proto vznikají až
/// tady, sloučením shodných sousedů; kdyby se to neudělalo, praxe přes tři
/// hodiny by v aplikaci vypadala jako tři samostatné hodiny po sobě.
enum TimetablePageParser {

    private static let page = "Rozvrh"

    static func parse(_ html: String, fallbackYear: SchoolYear = .current) throws -> TimetablePage {
        let document = try HTML.document(html, page: page)
        let table = try HTML.require(document, "table.timetable", page: page)

        let periods = try parsePeriods(table)
        guard !periods.isEmpty else {
            throw HTMLParseError(page: page, detail: "v hlavičce nejsou žádné vyučovací hodiny")
        }

        let days = HTML.all(table, "tr")
            .compactMap { row -> TimetableDay? in parseDay(row, periods: periods) }

        return TimetablePage(
            timetable: Timetable(periods: periods, days: days),
            periodOptions: parsePeriodOptions(document),
            schoolYear: parseSelectedYear(document) ?? fallbackYear
        )
    }

    // MARK: - Hlavička s hodinami

    private static func parsePeriods(_ table: Element) throws -> [LessonPeriod] {
        HTML.all(table, "th.period").compactMap { header in
            // Číslo hodiny je vlastní text buňky, čas je ve vnořeném spanu.
            guard let number = Int(header.ownText().normalizedWhitespace),
                  let timeElement = HTML.first(header, "span.time"),
                  let range = JecnaDate.timeRange(timeElement.normalizedText) else { return nil }
            return LessonPeriod(number: number, from: range.from, to: range.to)
        }
    }

    // MARK: - Jeden den

    private static func parseDay(_ row: Element, periods: [LessonPeriod]) -> TimetableDay? {
        guard let dayHeader = HTML.first(row, "th.day"),
              let weekday = Weekday.fromJecnaAbbreviation(dayHeader.normalizedText) else { return nil }

        let cells = HTML.all(row, "td")
        // Buňky odpovídají hodinám v hlavičce pozicí; kratší řádek jen znamená
        // dřívější konec dne.
        let rawSpots: [(period: Int, lessons: [Lesson])] = cells.enumerated().compactMap { index, cell in
            guard index < periods.count else { return nil }
            return (periods[index].number, parseLessons(in: cell))
        }

        return TimetableDay(weekday: weekday, spots: merge(rawSpots))
    }

    private static func parseLessons(in cell: Element) -> [Lesson] {
        HTML.all(cell, "div")
            // `lessonEmpty` je zástupné místo pro skupinu, která zrovna výuku nemá.
            .filter { $0.hasClass("lessonEmpty") == false }
            .compactMap(parseLesson)
    }

    private static func parseLesson(_ div: Element) -> Lesson? {
        guard let subjectElement = HTML.first(div, "span.subject") else { return nil }

        // Zkratka je v textu, plný název v atributu title.
        let short = subjectElement.normalizedText.nilIfEmpty
        let full = subjectElement.attribute("title") ?? short ?? ""
        guard !full.isEmpty else { return nil }

        let teacherElement = HTML.first(div, "a.employee")
        let teacher = teacherElement.flatMap { element -> DisplayName? in
            guard let fullName = element.attribute("title") else { return nil }
            return DisplayName(fullName, short: element.normalizedText.nilIfEmpty)
        }

        return Lesson(
            subject: DisplayName(full, short: short),
            teacher: teacher,
            teacherTag: teacherElement?.hrefLastComponent(),
            classroom: HTML.first(div, "a.room")?.normalizedText.nilIfEmpty,
            group: HTML.first(div, "span.group")?.normalizedText.nilIfEmpty
        )
    }

    // MARK: - Slučování do bloků

    /// Spojí sousední hodiny se shodným obsahem do jednoho bloku.
    private static func merge(_ raw: [(period: Int, lessons: [Lesson])]) -> [LessonSpot] {
        var spots: [LessonSpot] = []
        var index = 0

        while index < raw.count {
            let current = raw[index]

            guard !current.lessons.isEmpty else {
                spots.append(.empty(at: current.period))
                index += 1
                continue
            }

            let signature = self.signature(current.lessons)
            var span = 1
            // Sousední buňka patří do bloku jen když navazuje číslem hodiny
            // a nese úplně stejnou výuku.
            while index + span < raw.count,
                  raw[index + span].period == current.period + span,
                  self.signature(raw[index + span].lessons) == signature {
                span += 1
            }

            spots.append(LessonSpot(startPeriod: current.period, periodSpan: span, lessons: current.lessons))
            index += span
        }

        return spots
    }

    /// Otisk obsahu buňky. `Lesson` má vlastní `id`, takže se porovnává obsahem.
    private static func signature(_ lessons: [Lesson]) -> String {
        lessons
            .map { [$0.subject.full, $0.teacherTag ?? "", $0.classroom ?? "", $0.group ?? ""].joined(separator: "|") }
            .joined(separator: "&")
    }

    // MARK: - Výběry nad tabulkou

    private static func parseSelectedYear(_ document: Document) -> SchoolYear? {
        guard let option = HTML.first(document, "select#schoolYearId option[selected]"),
              let id = Int(option.attribute("value") ?? "") else { return nil }
        return SchoolYear(2008 + id)
    }

    /// Nabídka variant rozvrhu, např. „Dočasný rozvrh září 2026 - Od 01.09.2026“.
    private static func parsePeriodOptions(_ document: Document) -> [TimetablePeriodOption] {
        HTML.all(document, "select#timetableId option").compactMap { option in
            guard let id = Int(option.attribute("value") ?? "") else { return nil }
            let label = option.normalizedText
            let dates = extractDates(from: label)
            guard let from = dates.first else { return nil }

            return TimetablePeriodOption(
                id: id,
                header: header(from: label),
                from: from,
                to: dates.count > 1 ? dates[1] : nil,
                isSelected: option.hasAttr("selected")
            )
        }
    }

    private static let dateExpression = try? NSRegularExpression(pattern: #"\d{1,2}\.\d{1,2}\.\d{4}"#)

    private static func extractDates(from text: String) -> [Date] {
        guard let dateExpression else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return dateExpression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return JecnaDate.fromNumeric(String(text[matchRange]))
        }
    }

    /// Popis před datem, pokud tam nějaký je. „Od“ samo o sobě popis není.
    private static func header(from label: String) -> String? {
        guard let dateExpression else { return nil }
        let range = NSRange(label.startIndex..., in: label)
        guard let first = dateExpression.firstMatch(in: label, range: range),
              let matchRange = Range(first.range, in: label) else { return label.nilIfEmpty }

        var prefix = String(label[..<matchRange.lowerBound]).normalizedWhitespace
        for suffix in ["- Od", "-Od", "Od", "-"] where prefix.hasSuffix(suffix) {
            prefix = String(prefix.dropLast(suffix.count)).normalizedWhitespace
            break
        }
        return prefix.trimmingCharacters(in: CharacterSet(charactersIn: " -")).nilIfEmpty
    }
}

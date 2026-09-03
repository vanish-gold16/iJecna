import Foundation
import SwiftSoup

/// Čte stránku `/score/student`.
///
/// Tabulka má na řádek jeden předmět: záhlaví s názvem, buňku se známkami
/// a buňku s výslednou známkou. Poslední řádek je chování.
///
/// Známky uvnitř buňky nejsou zanořené do skupin — části předmětu
/// („Cvičení“, „Teorie“) jsou jen nadpisy mezi nimi, takže se musí číst
/// v pořadí, v jakém stojí v dokumentu.
enum GradesPageParser {

    private static let page = "Známky"

    static func parse(
        _ html: String,
        fallbackYear: SchoolYear = .current,
        fallbackHalf: SchoolYearHalf = .current
    ) throws -> GradesPage {
        let document = try HTML.document(html, page: page)
        let table = try HTML.require(document, "table.score", page: page)

        var subjects: [Subject] = []
        var behaviour = Behaviour(finalGrade: nil, notificationIds: [])

        for row in HTML.all(table, "tbody tr") {
            guard let header = HTML.first(row, "th") else { continue }
            let cells = HTML.all(row, "td")
            guard cells.count >= 2 else { continue }

            let title = header.normalizedText
            if title == Behaviour.subjectName {
                behaviour = parseBehaviour(gradesCell: cells[0], finalCell: cells[1])
            } else {
                subjects.append(parseSubject(name: title, gradesCell: cells[0], finalCell: cells[1]))
            }
        }

        return GradesPage(
            subjects: subjects,
            behaviour: behaviour,
            schoolYear: parseSelected(document, id: "schoolYearId").map { SchoolYear(2008 + $0) } ?? fallbackYear,
            half: parseSelected(document, id: "schoolYearHalfId").flatMap(SchoolYearHalf.init) ?? fallbackHalf
        )
    }

    // MARK: - Předmět

    private static func parseSubject(name: String, gradesCell: Element, finalCell: Element) -> Subject {
        let parts = parseParts(gradesCell)
        let final = parseFinalGrade(finalCell)

        return Subject(
            name: .parsingParenthesizedShort(name),
            parts: parts.isEmpty ? [SubjectPart(title: nil, grades: [])] : parts,
            finalGrade: final.grade,
            finalGradeNote: final.note
        )
    }

    /// Rozdělí známky podle nadpisů částí předmětu.
    ///
    /// Nadpis platí pro všechny známky až po další nadpis. Když v buňce
    /// žádný nadpis není, spadne všechno do jediné části bez názvu.
    private static func parseParts(_ cell: Element) -> [SubjectPart] {
        var parts: [(title: String?, grades: [Grade])] = []
        var currentTitle: String? = nil
        var currentGrades: [Grade] = []
        var sawPartHeader = false

        func flush() {
            guard sawPartHeader || !currentGrades.isEmpty else { return }
            parts.append((currentTitle, currentGrades))
            currentGrades = []
        }

        for child in cell.children().array() {
            if child.hasClass("subjectPart") {
                flush()
                sawPartHeader = true
                // Nadpis má tvar „Cvičení: “.
                currentTitle = child.normalizedText
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                    .nilIfEmpty
            } else if child.hasClass("score"), !child.hasClass("scoreFinal") {
                if let grade = parseGrade(child, part: currentTitle) {
                    currentGrades.append(grade)
                }
            }
        }
        flush()

        return parts.map { SubjectPart(title: $0.title, grades: $0.grades) }
    }

    // MARK: - Jedna známka

    /// `<a title="popis (27.02.2026, Studénková Kristina, MUDr.)"
    ///     class="score scoreValue2 scoreSmall" href="/score/view?scoreId=1261135">`
    private static func parseGrade(_ element: Element, part: String?) -> Grade? {
        let label = HTML.first(element, "span.value")?.normalizedText ?? element.normalizedText
        guard let value = gradeValue(from: label) else { return nil }

        let details = parseTitle(element.attribute("title"))
        let teacherShort = HTML.first(element, "span.employee")?.normalizedText.nilIfEmpty

        return Grade(
            // Bez id z webu by se nedaly rozlišit dvě stejné známky ve stejný den,
            // a tím pádem ani poznat, která z nich je nová.
            id: Int(element.hrefQueryValue("scoreId") ?? "") ?? syntheticId(element, label: label),
            value: value,
            isSmall: element.hasClass("scoreSmall"),
            teacher: details.teacher.map { DisplayName($0, short: teacherShort) }
                ?? teacherShort.map { DisplayName($0) },
            detail: details.description,
            receivedAt: details.date,
            subjectPart: part
        )
    }

    /// „N“ znamená, že student nepsal; v modelu je to nula a do průměru nevstupuje.
    private static func gradeValue(from label: String) -> Int? {
        if label.uppercased() == "N" { return 0 }
        guard let value = Int(label), (1...5).contains(value) else { return nil }
        return value
    }

    /// Kdyby web přestal dodávat `scoreId`, ať aplikace nespadne — jen se
    /// zhorší rozpoznávání nových známek.
    private static func syntheticId(_ element: Element, label: String) -> Int {
        abs("\(element.attribute("title") ?? "")|\(label)".hashValue)
    }

    /// Rozebere `title` na popis, datum a učitele.
    ///
    /// Tvar je `popis (DD.MM.RRRR, Příjmení Jméno, tituly)`, přičemž popis
    /// může chybět a tituly nemusí být. Závorka se hledá od konce, protože
    /// popis sám může závorky obsahovat.
    static func parseTitle(_ raw: String?) -> (description: String?, date: Date?, teacher: String?) {
        guard let raw = raw?.normalizedWhitespace, !raw.isEmpty else { return (nil, nil, nil) }
        guard raw.hasSuffix(")"), let open = raw.lastIndex(of: "(") else {
            return (raw.nilIfEmpty, nil, nil)
        }

        let description = String(raw[..<open]).trimmingCharacters(in: .whitespaces).nilIfEmpty
        let inside = String(raw[raw.index(after: open)..<raw.index(before: raw.endIndex)])
        let fields = inside.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard let first = fields.first, let date = JecnaDate.fromNumeric(first) else {
            return (raw.nilIfEmpty, nil, nil)
        }

        let teacher = fields.count > 1
            ? teacherName(name: fields[1], titles: fields.dropFirst(2).joined(separator: " "))
            : nil

        return (description, date, teacher)
    }

    /// Na této stránce se učitel píše příjmením napřed a s tituly na konci.
    /// V rozvrhu je přitom pořadí opačné, tak to sjednotíme na „Tituly Jméno Příjmení“.
    private static func teacherName(name: String, titles: String) -> String? {
        let words = name.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        let reordered = words.count == 2 ? "\(words[1]) \(words[0])" : name
        let prefix = titles.normalizedWhitespace
        return prefix.isEmpty ? reordered : "\(prefix) \(reordered)"
    }

    // MARK: - Výsledná známka

    /// `<a title="chvalitebný" class="score scoreFinal scoreValue2">2</a>`
    private static func parseFinalGrade(_ cell: Element) -> (grade: FinalGrade?, note: String?) {
        guard let element = HTML.first(cell, "a.scoreFinal") else { return (nil, nil) }

        let label = element.normalizedText
        let title = element.attribute("title")

        // Popisek může nést i dodatek za čárkou: „výborný, Napomenutí za neklasifikace“.
        let note = title?
            .components(separatedBy: ",")
            .dropFirst()
            .joined(separator: ",")
            .trimmingCharacters(in: .whitespaces)
            .nilIfEmpty

        return (finalGrade(label: label, title: title), note)
    }

    private static func finalGrade(label: String, title: String?) -> FinalGrade? {
        if let value = Int(label), (1...5).contains(value) { return .grade(value) }
        if label.uppercased() == "U" { return .excused }

        // Varování web nepíše číslem; poznáme je podle slovního popisku.
        let text = (title ?? label).lowercased()
        let hasGradesWarning = text.contains("prospěch") || text.contains("nedostatečn")
        let hasAbsenceWarning = text.contains("neklasifik") || text.contains("absenc")

        switch (hasGradesWarning, hasAbsenceWarning) {
        case (true, true): return .gradesAndAbsenceWarning
        case (true, false): return .gradesWarning
        case (false, true): return .absenceWarning
        case (false, false): return nil
        }
    }

    // MARK: - Chování

    private static func parseBehaviour(gradesCell: Element, finalCell: Element) -> Behaviour {
        let ids = HTML.all(gradesCell, "a")
            .compactMap { $0.hrefQueryValue("userStudentRecordId") }
            .compactMap(Int.init)

        return Behaviour(finalGrade: parseFinalGrade(finalCell).grade, notificationIds: ids)
    }

    // MARK: - Výběry období

    private static func parseSelected(_ document: Document, id: String) -> Int? {
        guard let option = HTML.first(document, "select#\(id) option[selected]") else { return nil }
        return Int(option.attribute("value") ?? "")
    }
}

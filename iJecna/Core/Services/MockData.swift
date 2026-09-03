import Foundation

/// Statická data pro maketu. Struktura přesně odpovídá tomu, co vrací Ječna,
/// aby se dala později nahradit parserem beze změny UI.
enum MockData {
    static let calendar = Calendar.prague

    static func date(_ day: Int, _ month: Int, _ year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? .now
    }

    /// Datum posunuté o `days` dozadu od dneška — ať makety nezestárnou.
    static func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: .now) ?? .now
    }

    // MARK: - Učitelé

    static let teacherRefs: [TeacherRef] = [
        TeacherRef(tag: "Nov", fullName: "Ing. Petr Novák"),
        TeacherRef(tag: "Svo", fullName: "Mgr. Jana Svobodová"),
        TeacherRef(tag: "Dvo", fullName: "Ing. Tomáš Dvořák"),
        TeacherRef(tag: "Cer", fullName: "Mgr. Lucie Černá"),
        TeacherRef(tag: "Pro", fullName: "Ing. Martin Procházka"),
        TeacherRef(tag: "Hor", fullName: "RNDr. Eva Horáková"),
        TeacherRef(tag: "Kuc", fullName: "Mgr. Josef Kučera"),
        TeacherRef(tag: "Ves", fullName: "Ing. Marie Veselá, Ph.D."),
        TeacherRef(tag: "Ben", fullName: "Mgr. Adam Beneš"),
        TeacherRef(tag: "Kra", fullName: "Ing. Pavel Král"),
        TeacherRef(tag: "Ryb", fullName: "Mgr. Tereza Rybářová"),
        TeacherRef(tag: "Mar", fullName: "Ing. Jakub Marek"),
    ]

    static func teacher(_ tag: String) -> TeacherRef? {
        teacherRefs.first { $0.tag == tag }
    }

    static func teacherName(_ tag: String) -> DisplayName? {
        teacher(tag).map { DisplayName($0.fullName, short: $0.tag) }
    }

    static let teacherDetails: [String: Teacher] = [
        "Nov": Teacher(
            tag: "Nov",
            fullName: "Ing. Petr Novák",
            username: "novak",
            schoolMail: "novak@spsejecna.cz",
            phoneNumbers: ["+420 224 920 111"],
            cabinet: "312",
            tutorOfClass: "3.C",
            consultationHours: "Úterý 14:30 – 15:30, kabinet 312"
        ),
        "Svo": Teacher(
            tag: "Svo",
            fullName: "Mgr. Jana Svobodová",
            username: "svobodova",
            schoolMail: "svobodova@spsejecna.cz",
            phoneNumbers: ["+420 224 920 118"],
            cabinet: "204",
            tutorOfClass: nil,
            consultationHours: "Po domluvě e-mailem"
        ),
        "Dvo": Teacher(
            tag: "Dvo",
            fullName: "Ing. Tomáš Dvořák",
            username: "dvorak",
            schoolMail: "dvorak@spsejecna.cz",
            phoneNumbers: ["+420 224 920 145", "+420 601 234 567"],
            cabinet: "417",
            tutorOfClass: "4.A",
            consultationHours: "Čtvrtek 13:40 – 14:25"
        ),
    ]

    // MARK: - Předměty a známky

    private static var nextGradeId = 4000

    private static func grade(
        _ value: Int,
        small: Bool,
        _ detail: String,
        teacherTag: String,
        daysAgo days: Int,
        part: String? = nil
    ) -> Grade {
        nextGradeId += 1
        return Grade(
            id: nextGradeId,
            value: value,
            isSmall: small,
            teacher: teacherName(teacherTag),
            detail: detail,
            receivedAt: MockData.daysAgo(days),
            subjectPart: part
        )
    }

    static func gradesPage(year: SchoolYear, half: SchoolYearHalf) -> GradesPage {
        // Starší roky/pololetí vracejí menší, „uzavřený“ dataset,
        // ať je vidět, jak se obrazovka chová i pro archiv.
        let isCurrent = year == .current && half == .current
        let subjects = isCurrent ? currentSubjects() : archivedSubjects()

        return GradesPage(
            subjects: subjects,
            behaviour: Behaviour(
                finalGrade: isCurrent ? nil : .grade(1),
                notificationIds: isCurrent ? [8801, 8802] : []
            ),
            schoolYear: year,
            half: half
        )
    }

    private static func currentSubjects() -> [Subject] {
        nextGradeId = 4000
        return [
            Subject(
                name: DisplayName("Matematika", short: "MAT"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(2, small: false, "Písemka — goniometrické funkce", teacherTag: "Hor", daysAgo: 2),
                    grade(1, small: true, "Aktivita v hodině", teacherTag: "Hor", daysAgo: 9),
                    grade(3, small: false, "Čtvrtletní práce", teacherTag: "Hor", daysAgo: 24),
                    grade(1, small: true, "Domácí úkol", teacherTag: "Hor", daysAgo: 31),
                    grade(2, small: true, "Desetiminutovka — logaritmy", teacherTag: "Hor", daysAgo: 45),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Programové vybavení", short: "PVY"),
                parts: [
                    SubjectPart(title: "Teorie", grades: [
                        grade(1, small: false, "Test — objektové programování", teacherTag: "Dvo", daysAgo: 1, part: "Teorie"),
                        grade(2, small: true, "Ústní zkoušení — kolekce", teacherTag: "Dvo", daysAgo: 17, part: "Teorie"),
                    ]),
                    SubjectPart(title: "Cvičení", grades: [
                        grade(1, small: false, "Semestrální projekt — 1. odevzdání", teacherTag: "Dvo", daysAgo: 5, part: "Cvičení"),
                        grade(1, small: true, "Cvičení 07 — rekurze", teacherTag: "Dvo", daysAgo: 12, part: "Cvičení"),
                        grade(0, small: true, "Cvičení 05 — nebyl přítomen", teacherTag: "Dvo", daysAgo: 26, part: "Cvičení"),
                    ]),
                ],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Základy elektrotechniky", short: "ZEL"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(3, small: false, "Písemka — střídavé obvody", teacherTag: "Nov", daysAgo: 4),
                    grade(2, small: true, "Referát — Kirchhoffovy zákony", teacherTag: "Nov", daysAgo: 20),
                    grade(4, small: false, "Test — RLC obvody", teacherTag: "Nov", daysAgo: 38),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Anglický jazyk", short: "ANJ"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(1, small: true, "Slovíčka — unit 4", teacherTag: "Svo", daysAgo: 3),
                    grade(2, small: false, "Test — present perfect", teacherTag: "Svo", daysAgo: 15),
                    grade(1, small: false, "Prezentace — My hometown", teacherTag: "Svo", daysAgo: 29),
                    grade(1, small: true, "Slovíčka — unit 3", teacherTag: "Svo", daysAgo: 41),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Český jazyk a literatura", short: "CJL"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(2, small: false, "Slohová práce — úvaha", teacherTag: "Cer", daysAgo: 8),
                    grade(3, small: true, "Literatura — romantismus", teacherTag: "Cer", daysAgo: 22),
                    grade(2, small: true, "Diktát", teacherTag: "Cer", daysAgo: 36),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Číslicová technika", short: "CIT"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(1, small: false, "Laboratorní úloha — klopné obvody", teacherTag: "Pro", daysAgo: 6),
                    grade(2, small: true, "Test — Booleova algebra", teacherTag: "Pro", daysAgo: 19),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Fyzika", short: "FYZ"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(3, small: false, "Písemka — termodynamika", teacherTag: "Kra", daysAgo: 11),
                    grade(4, small: true, "Laboratorní protokol", teacherTag: "Kra", daysAgo: 27),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Praxe", short: "PRA"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(1, small: false, "Pájení — DPS zesilovač", teacherTag: "Mar", daysAgo: 7),
                    grade(1, small: false, "Měření — osciloskop", teacherTag: "Mar", daysAgo: 21),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Dějepis", short: "DEJ"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(2, small: true, "Referát — první republika", teacherTag: "Ben", daysAgo: 14),
                ])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Ekonomika", short: "EKO"),
                parts: [SubjectPart(title: nil, grades: [])],
                finalGrade: nil
            ),
            Subject(
                name: DisplayName("Tělesná výchova", short: "TEV"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(1, small: true, "Vytrvalostní běh", teacherTag: "Kuc", daysAgo: 18),
                ])],
                finalGrade: nil
            ),
        ]
    }

    private static func archivedSubjects() -> [Subject] {
        nextGradeId = 2000
        return [
            Subject(
                name: DisplayName("Matematika", short: "MAT"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(2, small: false, "Pololetní práce", teacherTag: "Hor", daysAgo: 220),
                    grade(2, small: true, "Domácí úkol", teacherTag: "Hor", daysAgo: 240),
                ])],
                finalGrade: .grade(2)
            ),
            Subject(
                name: DisplayName("Programové vybavení", short: "PVY"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(1, small: false, "Projekt", teacherTag: "Dvo", daysAgo: 225),
                ])],
                finalGrade: .grade(1)
            ),
            Subject(
                name: DisplayName("Základy elektrotechniky", short: "ZEL"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(4, small: false, "Souhrnný test", teacherTag: "Nov", daysAgo: 230),
                ])],
                finalGrade: .grade(4)
            ),
            Subject(
                name: DisplayName("Fyzika", short: "FYZ"),
                parts: [SubjectPart(title: nil, grades: [])],
                finalGrade: .absenceWarning
            ),
            Subject(
                name: DisplayName("Anglický jazyk", short: "ANJ"),
                parts: [SubjectPart(title: nil, grades: [
                    grade(1, small: false, "Závěrečný test", teacherTag: "Svo", daysAgo: 228),
                ])],
                finalGrade: .grade(1)
            ),
            Subject(
                name: DisplayName("Tělesná výchova", short: "TEV"),
                parts: [SubjectPart(title: nil, grades: [])],
                finalGrade: .excused
            ),
        ]
    }
}

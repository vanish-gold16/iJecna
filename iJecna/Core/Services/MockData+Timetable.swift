import Foundation

extension MockData {

    // MARK: - Zvonění

    /// Rozvrh hodin na Ječné včetně nulté hodiny.
    static let lessonPeriods: [LessonPeriod] = [
        LessonPeriod(number: 0, from: TimeOfDay(7, 10), to: TimeOfDay(7, 55)),
        LessonPeriod(number: 1, from: TimeOfDay(8, 0), to: TimeOfDay(8, 45)),
        LessonPeriod(number: 2, from: TimeOfDay(8, 55), to: TimeOfDay(9, 40)),
        LessonPeriod(number: 3, from: TimeOfDay(10, 0), to: TimeOfDay(10, 45)),
        LessonPeriod(number: 4, from: TimeOfDay(10, 55), to: TimeOfDay(11, 40)),
        LessonPeriod(number: 5, from: TimeOfDay(11, 50), to: TimeOfDay(12, 35)),
        LessonPeriod(number: 6, from: TimeOfDay(12, 45), to: TimeOfDay(13, 30)),
        LessonPeriod(number: 7, from: TimeOfDay(13, 40), to: TimeOfDay(14, 25)),
        LessonPeriod(number: 8, from: TimeOfDay(14, 35), to: TimeOfDay(15, 20)),
        LessonPeriod(number: 9, from: TimeOfDay(15, 30), to: TimeOfDay(16, 15)),
    ]

    private static func lesson(
        _ subject: String,
        _ short: String,
        teacher tag: String,
        room: String,
        group: String? = nil
    ) -> Lesson {
        Lesson(
            subject: DisplayName(subject, short: short),
            teacher: teacherName(tag),
            teacherTag: tag,
            classroom: room,
            group: group
        )
    }

    private static func spot(_ period: Int, span: Int = 1, _ lessons: Lesson...) -> LessonSpot {
        LessonSpot(startPeriod: period, periodSpan: span, lessons: lessons)
    }

    // MARK: - Rozvrh 3.C

    static func timetablePage(year: SchoolYear, periodId: Int?) -> TimetablePage {
        TimetablePage(
            timetable: Timetable(periods: lessonPeriods, days: weekDays),
            periodOptions: periodOptions,
            schoolYear: year
        )
    }

    private static var weekDays: [TimetableDay] {
        [
            TimetableDay(weekday: .monday, spots: [
                spot(1, lesson("Matematika", "MAT", teacher: "Hor", room: "306")),
                spot(2, lesson("Český jazyk a literatura", "CJL", teacher: "Cer", room: "306")),
                spot(3,
                     lesson("Anglický jazyk", "ANJ", teacher: "Svo", room: "204", group: "1/2"),
                     lesson("Anglický jazyk", "ANJ", teacher: "Ryb", room: "205", group: "2/2")),
                spot(4, lesson("Základy elektrotechniky", "ZEL", teacher: "Nov", room: "410")),
                spot(5, lesson("Fyzika", "FYZ", teacher: "Kra", room: "212")),
                spot(6, lesson("Tělesná výchova", "TEV", teacher: "Kuc", room: "Tělocvična")),
            ]),
            TimetableDay(weekday: .tuesday, spots: [
                spot(1, span: 2,
                     lesson("Programové vybavení", "PVY", teacher: "Dvo", room: "Lab 217", group: "S1"),
                     lesson("Programové vybavení", "PVY", teacher: "Ves", room: "Lab 219", group: "S2")),
                spot(3, lesson("Matematika", "MAT", teacher: "Hor", room: "306")),
                spot(4, lesson("Dějepis", "DEJ", teacher: "Ben", room: "301")),
                spot(5, lesson("Číslicová technika", "CIT", teacher: "Pro", room: "408")),
                spot(6, lesson("Ekonomika", "EKO", teacher: "Ves", room: "301")),
            ]),
            // Ve středu je mezi 4. a 6. hodinou okno — stav „volná hodina“ tak jde vyzkoušet.
            TimetableDay(weekday: .wednesday, spots: [
                spot(1, lesson("Základy elektrotechniky", "ZEL", teacher: "Nov", room: "410")),
                spot(2, lesson("Číslicová technika", "CIT", teacher: "Pro", room: "408")),
                spot(3, lesson("Programové vybavení", "PVY", teacher: "Dvo", room: "306")),
                spot(4, lesson("Matematika", "MAT", teacher: "Hor", room: "306")),
                spot(6, lesson("Český jazyk a literatura", "CJL", teacher: "Cer", room: "306")),
            ]),
            TimetableDay(weekday: .thursday, spots: [
                spot(1, span: 3,
                     lesson("Praxe", "PRA", teacher: "Mar", room: "Dílny 004", group: "S1"),
                     lesson("Praxe", "PRA", teacher: "Kra", room: "Dílny 006", group: "S2")),
                spot(4,
                     lesson("Anglický jazyk", "ANJ", teacher: "Svo", room: "204", group: "1/2"),
                     lesson("Anglický jazyk", "ANJ", teacher: "Ryb", room: "205", group: "2/2")),
                spot(5, lesson("Fyzika", "FYZ", teacher: "Kra", room: "212")),
                spot(6, lesson("Tělesná výchova", "TEV", teacher: "Kuc", room: "Tělocvična")),
            ]),
            TimetableDay(weekday: .friday, spots: [
                spot(1, lesson("Matematika", "MAT", teacher: "Hor", room: "306")),
                spot(2, lesson("Programové vybavení", "PVY", teacher: "Dvo", room: "306")),
                spot(3, lesson("Český jazyk a literatura", "CJL", teacher: "Cer", room: "306")),
                spot(4, lesson("Základy elektrotechniky", "ZEL", teacher: "Nov", room: "410")),
                spot(5, lesson("Dějepis", "DEJ", teacher: "Ben", room: "301")),
            ]),
        ]
    }

    private static var periodOptions: [TimetablePeriodOption] {
        [
            TimetablePeriodOption(
                id: 1,
                header: nil,
                from: date(1, 9, 2025),
                to: nil,
                isSelected: true
            ),
            TimetablePeriodOption(
                id: 2,
                header: "Mimořádný rozvrh",
                from: daysAgo(-6),
                to: daysAgo(-2),
                isSelected: false
            ),
        ]
    }

    // MARK: - Učebny

    static let rooms: [Room] = [
        Room(roomCode: "306", name: "Učebna 306", floor: "3. patro", homeroomOf: "3.C", manager: teacher("Nov")?.fullName),
        Room(roomCode: "301", name: "Učebna 301", floor: "3. patro", homeroomOf: "2.A", manager: teacher("Ben")?.fullName),
        Room(roomCode: "204", name: "Jazyková učebna 204", floor: "2. patro", homeroomOf: nil, manager: teacher("Svo")?.fullName),
        Room(roomCode: "205", name: "Jazyková učebna 205", floor: "2. patro", homeroomOf: nil, manager: teacher("Ryb")?.fullName),
        Room(roomCode: "212", name: "Fyzikální posluchárna", floor: "2. patro", homeroomOf: nil, manager: teacher("Kra")?.fullName),
        Room(roomCode: "408", name: "Laboratoř číslicové techniky", floor: "4. patro", homeroomOf: nil, manager: teacher("Pro")?.fullName),
        Room(roomCode: "410", name: "Elektrotechnická laboratoř", floor: "4. patro", homeroomOf: "4.A", manager: teacher("Nov")?.fullName),
        Room(roomCode: "217", name: "Počítačová učebna Lab 217", floor: "2. patro", homeroomOf: nil, manager: teacher("Dvo")?.fullName),
        Room(roomCode: "219", name: "Počítačová učebna Lab 219", floor: "2. patro", homeroomOf: nil, manager: teacher("Ves")?.fullName),
        Room(roomCode: "004", name: "Dílny — elektro", floor: "Suterén", homeroomOf: nil, manager: teacher("Mar")?.fullName),
        Room(roomCode: "TV", name: "Tělocvična", floor: "Přízemí", homeroomOf: nil, manager: teacher("Kuc")?.fullName),
    ]

    // MARK: - Aktuality

    static var news: [Article] {
        [
            Article(
                id: 3282,
                title: "Ředitelské volno 30. října",
                content: "Ředitel školy vyhlašuje na pátek 30. října ředitelské volno. Výuka odpadá pro všechny ročníky, budova školy bude uzavřena. Obědy jsou automaticky odhlášeny.",
                date: daysAgo(1),
                author: "Vedení školy",
                schoolOnly: false
            ),
            Article(
                id: 3278,
                title: "Přihlášky na maturitní ples",
                content: "Do konce měsíce se můžete přihlásit na maturitní ples čtvrtých ročníků. Vstupenky jsou k dispozici u třídních učitelů, kapacita sálu je omezená.",
                date: daysAgo(3),
                author: "Mgr. Lucie Černá",
                schoolOnly: true,
                attachments: [
                    ArticleAttachment(label: "Přihláška (PDF)", downloadPath: "/soubory/ples-prihlaska.pdf")
                ]
            ),
            Article(
                id: 3275,
                title: "Exkurze do ČEZ — Temelín",
                content: "Pro třetí ročníky pořádáme exkurzi do jaderné elektrárny Temelín. Odjezd v 7:00 od školy, návrat kolem 18:00. Nezapomeňte občanský průkaz.",
                date: daysAgo(6),
                author: "Ing. Petr Novák",
                schoolOnly: true,
                attachments: [
                    ArticleAttachment(label: "Informace pro rodiče", downloadPath: "/soubory/exkurze-temelin.pdf"),
                    ArticleAttachment(label: "Souhlas zákonného zástupce", downloadPath: "/soubory/souhlas.docx"),
                ]
            ),
            Article(
                id: 3260,
                title: "Sběr starých mobilů pokračuje",
                content: "Ve vestibulu školy je umístěn sběrný box na vysloužilou elektroniku. Zapojujeme se do projektu recyklace, výtěžek putuje na školní fond.",
                date: daysAgo(12),
                author: "Mgr. Josef Kučera"
            ),
            Article(
                id: 3201,
                title: "Zahájení školního roku 2025/2026",
                content: "Školní rok začíná v pondělí 1. září. První ročníky se sejdou v 8:00 před hlavním vchodem, ostatní ročníky ve svých kmenových učebnách.",
                date: date(1, 9, 2025),
                author: "Vedení školy"
            ),
        ]
    }

    // MARK: - Poznámky a pochvaly

    static var notifications: [SchoolNotification] {
        [
            SchoolNotification(
                id: 8801,
                kind: .good,
                exactType: "Pochvala třídního učitele",
                message: "Za reprezentaci školy na krajském kole soutěže v programování.",
                date: daysAgo(10),
                issuedBy: teacher("Nov")
            ),
            SchoolNotification(
                id: 8802,
                kind: .bad,
                exactType: "Napomenutí třídního učitele",
                message: "Opakované pozdní příchody na první vyučovací hodinu.",
                date: daysAgo(34),
                issuedBy: teacher("Nov")
            ),
            SchoolNotification(
                id: 8803,
                kind: .info,
                exactType: "Informace pro zákonné zástupce",
                message: "Uvolnění z tělesné výchovy na základě lékařského potvrzení do konce pololetí.",
                date: daysAgo(58),
                issuedBy: teacher("Kuc")
            ),
        ]
    }

    // MARK: - Student

    static var student: Student {
        Student(
            fullName: "Jan Novotný",
            username: "novotny",
            schoolMail: "novotny@spsejecna.cz",
            className: "3.C",
            classGroups: "S1, 1/2",
            birthDate: date(14, 3, 2008),
            permanentAddress: "Slezská 1234/45, 120 00 Praha 2",
            guardians: [
                Guardian(name: "Ing. Martina Novotná", phoneNumber: "+420 602 111 222", email: "novotna@email.cz"),
                Guardian(name: "Pavel Novotný", phoneNumber: "+420 603 333 444", email: nil),
            ],
            profilePicturePath: nil
        )
    }

    static var locker: Locker {
        Locker(
            number: "312",
            location: "Přízemí — v místnosti se skříňkami, 4. ulička vpravo od dveří k oknu",
            assignedFrom: date(1, 9, 2025),
            assignedUntil: nil
        )
    }
}

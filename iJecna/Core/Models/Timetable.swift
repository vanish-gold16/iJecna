import Foundation

/// Čas v rámci dne, bez data a bez časové zóny.
struct TimeOfDay: Hashable, Comparable, Codable, Sendable {
    let hour: Int
    let minute: Int

    init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    var minutesFromMidnight: Int { hour * 60 + minute }

    var formatted: String { String(format: "%d:%02d", hour, minute) }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }

    static func now(calendar: Calendar = .prague, date: Date = .now) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Vyučovací hodina jako časový interval (0. až 9. hodina).
struct LessonPeriod: Identifiable, Hashable, Codable, Sendable {
    /// Číslo hodiny tak, jak ho zobrazuje Ječna (0. hodina existuje).
    let number: Int
    let from: TimeOfDay
    let to: TimeOfDay

    var id: Int { number }
    var displayRange: String { "\(from.formatted) – \(to.formatted)" }
    var durationMinutes: Int { to.minutesFromMidnight - from.minutesFromMidnight }

    func contains(_ time: TimeOfDay) -> Bool {
        time >= from && time <= to
    }

    /// 0…1 podíl uplynulého času hodiny.
    func progress(at time: TimeOfDay) -> Double {
        let total = Double(durationMinutes)
        guard total > 0 else { return 0 }
        let elapsed = Double(time.minutesFromMidnight - from.minutesFromMidnight)
        return min(1, max(0, elapsed / total))
    }
}

/// Jedna konkrétní výuka. Ve spotu jich může být víc (dělené skupiny).
struct Lesson: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let subject: DisplayName
    let teacher: DisplayName?
    let teacherTag: String?
    let classroom: String?
    /// Skupina u dělených hodin, např. „1/2“ nebo „S1“. `nil` = celá třída.
    let group: String?

    init(
        id: UUID = UUID(),
        subject: DisplayName,
        teacher: DisplayName? = nil,
        teacherTag: String? = nil,
        classroom: String? = nil,
        group: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.teacher = teacher
        self.teacherTag = teacherTag
        self.classroom = classroom
        self.group = group
    }
}

/// Místo v rozvrhu. Může být prázdné (volná hodina), obsahovat jednu výuku,
/// nebo víc výuk pro různé skupiny. `periodSpan` pokrývá dvouhodinovky (praxe).
struct LessonSpot: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// Číslo hodiny, na které spot začíná.
    let startPeriod: Int
    let periodSpan: Int
    let lessons: [Lesson]

    init(id: UUID = UUID(), startPeriod: Int, periodSpan: Int = 1, lessons: [Lesson]) {
        self.id = id
        self.startPeriod = startPeriod
        self.periodSpan = periodSpan
        self.lessons = lessons
    }

    var isEmpty: Bool { lessons.isEmpty }
    var isSplit: Bool { lessons.count > 1 }
    var periodRange: ClosedRange<Int> { startPeriod...(startPeriod + periodSpan - 1) }

    /// Výuka pro zvolenou skupinu, nebo první dostupná.
    func lesson(preferringGroup group: String?) -> Lesson? {
        if let group, let match = lessons.first(where: { $0.group == group }) { return match }
        return lessons.first
    }

    static func empty(at period: Int) -> LessonSpot {
        LessonSpot(startPeriod: period, lessons: [])
    }

    /// Časový rozsah celého bloku podle zvonění.
    func timeRange(in periods: [LessonPeriod]) -> (from: TimeOfDay, to: TimeOfDay)? {
        guard let first = periods.first(where: { $0.number == periodRange.lowerBound }),
              let last = periods.first(where: { $0.number == periodRange.upperBound }) else { return nil }
        return (first.from, last.to)
    }

    /// Probíhá blok právě teď? Přestávka uvnitř dvou- či tříhodinovky se počítá jako „probíhá“.
    func isOngoing(at time: TimeOfDay, periods: [LessonPeriod]) -> Bool {
        guard let range = timeRange(in: periods) else { return false }
        return time >= range.from && time <= range.to
    }
}

enum Weekday: Int, CaseIterable, Identifiable, Codable, Sendable {
    case monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: "Po"
        case .tuesday: "Út"
        case .wednesday: "St"
        case .thursday: "Čt"
        case .friday: "Pá"
        }
    }

    var fullName: String {
        switch self {
        case .monday: "Pondělí"
        case .tuesday: "Úterý"
        case .wednesday: "Středa"
        case .thursday: "Čtvrtek"
        case .friday: "Pátek"
        }
    }

    /// Mapuje `Calendar.component(.weekday)` (1 = neděle) na školní den.
    static func from(calendarWeekday: Int) -> Weekday? {
        Weekday(rawValue: calendarWeekday)
    }

    static func today(calendar: Calendar = .prague, date: Date = .now) -> Weekday? {
        from(calendarWeekday: calendar.component(.weekday, from: date))
    }

    var next: Weekday {
        Weekday(rawValue: rawValue + 1) ?? .monday
    }

    /// Nejbližší datum, kdy tenhle den nastane — dnešek se počítá.
    ///
    /// Rozvrh je týdenní šablona bez konkrétních dat, ale úkoly se váží na datum.
    /// Když si ve čtvrtek otevřu středeční hodinu, myslím tím středu příští,
    /// ne tu včerejší — proto se dny, které už tenhle týden proběhly, posunou o týden.
    func nextOccurrence(from now: Date = .now, calendar: Calendar = .prague) -> Date {
        let today = Date.startOfSchoolDay(now, calendar: calendar)

        // `Calendar.prague` má firstWeekday = 2, týden tedy začíná pondělím.
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return today
        }

        let offset = rawValue - Weekday.monday.rawValue
        guard let thisWeek = calendar.date(byAdding: .day, value: offset, to: startOfWeek) else {
            return today
        }

        let candidate = Date.startOfSchoolDay(thisWeek, calendar: calendar)
        guard candidate < today else { return candidate }
        return calendar.date(byAdding: .day, value: 7, to: candidate) ?? candidate
    }
}

struct TimetableDay: Identifiable, Hashable, Codable, Sendable {
    let weekday: Weekday
    let spots: [LessonSpot]

    var id: Int { weekday.rawValue }
    var lessonSpots: [LessonSpot] { spots.filter { !$0.isEmpty } }
    var isEmpty: Bool { lessonSpots.isEmpty }

    func spot(atPeriod period: Int) -> LessonSpot? {
        spots.first { $0.periodRange.contains(period) }
    }

    /// Poslední hodina dne — dál rozvrh oříznout, ať se nezobrazují prázdné řádky.
    var lastOccupiedPeriod: Int? {
        lessonSpots.map { $0.periodRange.upperBound }.max()
    }
}

/// Varianta rozvrhu (řádný / dočasný / mimořádný) z rozbalovátka na webu.
struct TimetablePeriodOption: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let header: String?
    let from: Date
    let to: Date?
    let isSelected: Bool

    var displayName: String {
        let formatter = DateFormatter.jecnaShortDate
        let fromText = formatter.string(from: from)
        let toText = to.map(formatter.string(from:)) ?? "?"
        let range = "\(fromText) – \(toText)"
        return header.map { "\($0): \(range)" } ?? range
    }
}

struct Timetable: Hashable, Codable, Sendable {
    let periods: [LessonPeriod]
    let days: [TimetableDay]

    func day(_ weekday: Weekday) -> TimetableDay? {
        days.first { $0.weekday == weekday }
    }

    func period(number: Int) -> LessonPeriod? {
        periods.first { $0.number == number }
    }

    /// Rozsah hodin, který má smysl vykreslit (ořízne prázdné konce týdne).
    var occupiedPeriods: [LessonPeriod] {
        guard let last = days.compactMap(\.lastOccupiedPeriod).max() else { return periods }
        return periods.filter { $0.number <= last }
    }
}

/// Stránka `/timetable/class` — rozvrh + dostupné varianty.
struct TimetablePage: Hashable, Codable, Sendable {
    let timetable: Timetable
    let periodOptions: [TimetablePeriodOption]
    let schoolYear: SchoolYear
}

/// Co se právě děje — podklad pro hlavní obrazovku i pro pruh nad tab barem.
struct LessonMoment: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Hodina právě běží. `progress` je podíl celého bloku, ne jedné hodiny.
        case ongoing(progress: Double)
        /// Přestávka uvnitř bloku — tatáž výuka za chvíli pokračuje.
        case intermission(inMinutes: Int)
        case upcoming(inMinutes: Int)
        /// Volná hodina v rozvrhu, další výuka až později.
        case freePeriod(untilMinutes: Int)
        case dayFinished
        case weekend
    }

    let kind: Kind
    let lesson: Lesson?
    let spot: LessonSpot?
    let startPeriod: LessonPeriod?
    let endPeriod: LessonPeriod?
    let weekday: Weekday?

    /// Popisek hodiny: „3. hodina“, nebo „1.–3. hodina“ u vícehodinovky.
    var periodLabel: String? {
        guard let spot else { return nil }
        let range = spot.periodRange
        return range.count > 1
            ? "\(range.lowerBound).–\(range.upperBound). hodina"
            : "\(range.lowerBound). hodina"
    }

    static let weekend = LessonMoment(
        kind: .weekend, lesson: nil, spot: nil, startPeriod: nil, endPeriod: nil, weekday: nil
    )

    static func finished(_ weekday: Weekday) -> LessonMoment {
        LessonMoment(kind: .dayFinished, lesson: nil, spot: nil, startPeriod: nil, endPeriod: nil, weekday: weekday)
    }
}

extension Timetable {
    /// Určí aktuální nebo nejbližší výuku. Vše se počítá v pražském čase.
    ///
    /// Rozlišuje přestávku uvnitř bloku (praxe přes tři hodiny) od skutečné
    /// volné hodiny — jinak by aplikace tvrdila, že praxe „začne za 5 minut“,
    /// i když běží od osmi.
    func moment(at date: Date = .now, calendar: Calendar = .prague, group: String? = nil) -> LessonMoment {
        guard let weekday = Weekday.today(calendar: calendar, date: date),
              let day = day(weekday) else {
            return .weekend
        }

        let now = TimeOfDay.now(calendar: calendar, date: date)

        func bounds(of spot: LessonSpot) -> (LessonPeriod, LessonPeriod)? {
            guard let first = period(number: spot.periodRange.lowerBound),
                  let last = period(number: spot.periodRange.upperBound) else { return nil }
            return (first, last)
        }

        // 1. Probíhá právě hodina?
        if let current = periods.first(where: { $0.contains(now) }),
           let spot = day.spot(atPeriod: current.number),
           let lesson = spot.lesson(preferringGroup: group),
           let (first, last) = bounds(of: spot) {
            let total = Double(last.to.minutesFromMidnight - first.from.minutesFromMidnight)
            let elapsed = Double(now.minutesFromMidnight - first.from.minutesFromMidnight)
            let progress = total > 0 ? min(1, max(0, elapsed / total)) : 0
            return LessonMoment(
                kind: .ongoing(progress: progress),
                lesson: lesson,
                spot: spot,
                startPeriod: first,
                endPeriod: last,
                weekday: weekday
            )
        }

        // 2. Nejbližší další výuka dnes.
        let upcoming = periods.filter { $0.from > now }.sorted { $0.from < $1.from }
        for candidate in upcoming {
            guard let spot = day.spot(atPeriod: candidate.number),
                  let lesson = spot.lesson(preferringGroup: group),
                  let (first, last) = bounds(of: spot) else { continue }

            let minutes = candidate.from.minutesFromMidnight - now.minutesFromMidnight

            // Přestávka uvnitř bloku: blok už začal, jen běží pauza mezi hodinami.
            let isIntermission = first.from < now

            // Volná hodina (okno) není totéž co přestávka: musí mezi poslední
            // odučenou a nejbližší hodinou zůstat prázdný slot v rozvrhu.
            let previousOccupied = periods
                .filter { $0.to <= now && day.spot(atPeriod: $0.number)?.isEmpty == false }
                .max { $0.number < $1.number }

            let isFreePeriod = !isIntermission && {
                guard let previousOccupied else { return false }
                return ((previousOccupied.number + 1)..<candidate.number)
                    .contains { day.spot(atPeriod: $0)?.isEmpty != false }
            }()

            let kind: LessonMoment.Kind = if isIntermission {
                .intermission(inMinutes: minutes)
            } else if isFreePeriod {
                .freePeriod(untilMinutes: minutes)
            } else {
                .upcoming(inMinutes: minutes)
            }

            return LessonMoment(
                kind: kind,
                lesson: lesson,
                spot: spot,
                startPeriod: first,
                endPeriod: last,
                weekday: weekday
            )
        }

        return .finished(weekday)
    }
}

extension DateFormatter {
    static let jecnaShortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .prague
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.timeZone = Calendar.prague.timeZone
        formatter.setLocalizedDateFormatFromTemplate("d. M. yyyy")
        return formatter
    }()

    static let jecnaDayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .prague
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.timeZone = Calendar.prague.timeZone
        formatter.setLocalizedDateFormatFromTemplate("d. M.")
        return formatter
    }()

    static let jecnaWeekdayLong: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .prague
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.timeZone = Calendar.prague.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE d. M.")
        return formatter
    }()
}

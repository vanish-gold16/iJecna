import SwiftUI

struct TimetableView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDay: Weekday = Weekday.today() ?? .monday
    @State private var layout: Layout = .day
    @Namespace private var dayNamespace

    enum Layout: String, CaseIterable {
        case day = "Den"
        case week = "Týden"

        var symbol: String {
            switch self {
            case .day: "list.bullet"
            case .week: "square.grid.3x3"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                content
            }
            .navigationTitle("Rozvrh")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Zobrazení", selection: $layout) {
                        ForEach(Layout.allCases, id: \.self) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                if let page = model.timetable.value, !page.timetable.groupNumbers.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        classGroupMenu
                    }
                }
                if let page = model.timetable.value, !page.periodOptions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        periodOptionMenu(page.periodOptions)
                    }
                }
            }
            .task { await model.loadTimetable() }
        }
    }

    /// V podtitulku je vidět, podle které varianty se právě učí — mimořádný
    /// nebo dočasný rozvrh se od řádného může lišit celým dnem.
    private var subtitle: String {
        guard let option = selectedOption else { return model.selectedYear.displayName }
        return option.shortName
    }

    private var selectedOption: TimetablePeriodOption? {
        guard let options = model.timetable.value?.periodOptions, !options.isEmpty else { return nil }
        if let id = model.selectedTimetablePeriodId, let match = options.first(where: { $0.id == id }) {
            return match
        }
        return options.first(where: \.isSelected) ?? options.first
    }

    @ViewBuilder
    private var content: some View {
        switch model.timetable {
        case .idle, .loading:
            TimetableSkeleton()
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await model.loadTimetable(force: true) }
            }
        case .loaded(let page, _):
            // Hodiny jen pro druhou skupinu se v rozvrhu vůbec neukážou.
            let timetable = page.timetable.visible(toGroup: model.classGroup)
            switch layout {
            case .day: dayLayout(timetable)
            case .week: WeekGridView(
                timetable: timetable,
                preferredGroup: model.classGroup,
                substitutions: substitutionsByDay
            )
            }
        }
    }

    /// Mimořádný rozvrh pro celý týden — mřížka potřebuje všechny dny naráz.
    private var substitutionsByDay: [Weekday: SubstitutionDay] {
        Weekday.allCases.reduce(into: [:]) { result, weekday in
            result[weekday] = model.substitutionDay(on: weekday.nextOccurrence())
        }
    }

    // MARK: - Denní zobrazení

    private func dayLayout(_ timetable: Timetable) -> some View {
        VStack(spacing: 0) {
            dayPicker

            TabView(selection: $selectedDay) {
                ForEach(Weekday.allCases) { weekday in
                    DayScheduleList(
                        day: timetable.day(weekday),
                        periods: timetable.periods,
                        subjects: timetable.subjects,
                        preferredGroup: model.classGroup,
                        isToday: weekday == Weekday.today(),
                        substitutions: model.substitutionDay(on: weekday.nextOccurrence())
                    )
                    .tag(weekday)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .refreshable { await model.loadTimetable(force: true) }
    }

    /// Přepínač dnů. Dnešek je zvýrazněn i když je vybraný jiný den.
    private var dayPicker: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { weekday in
                    let isSelected = weekday == selectedDay
                    let isToday = weekday == Weekday.today()

                    Button {
                        withAnimation(.smooth(duration: 0.28)) { selectedDay = weekday }
                        Haptics.selection()
                    } label: {
                        VStack(spacing: 3) {
                            Text(weekday.shortName)
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                            Circle()
                                .fill(isToday ? Theme.accent : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(isSelected ? Color.white : .primary)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.accent.gradient)
                                .matchedGeometryEffect(id: "daySelection", in: dayNamespace)
                        }
                    }
                }
            }
            .padding(6)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    /// Přepínač variant rozvrhu — řádný, dočasný, mimořádný.
    ///
    /// Ukazuje se i když je varianta jediná: bez toho by student nevěděl,
    /// že se dívá na dočasný rozvrh, a divil by se, proč nesedí.
    private func periodOptionMenu(_ options: [TimetablePeriodOption]) -> some View {
        @Bindable var model = model
        return Menu {
            Picker("Varianta rozvrhu", selection: $model.selectedTimetablePeriodId) {
                ForEach(options) { option in
                    Text(option.displayName + (option.isActive() ? " • platí teď" : ""))
                        .tag(Optional(option.id))
                }
            }
            .onChange(of: model.selectedTimetablePeriodId) { _, _ in
                Task { await model.loadTimetable(force: true) }
            }
        } label: {
            Image(systemName: options.count > 1 ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
        }
        .accessibilityLabel("Varianta rozvrhu")
    }

    /// Rychlé přepnutí skupiny přímo z rozvrhu — tady je hned vidět,
    /// jestli dělené hodiny sedí.
    private var classGroupMenu: some View {
        Menu {
            Section("Moje skupina") {
                ClassGroupPicker()
            }
        } label: {
            Image(systemName: "person.2")
        }
        .accessibilityLabel("Moje skupina")
    }
}

/// Výběr vlastní skupiny u dělených hodin.
///
/// Profil na webu ji píše jinak než rozvrh („A2“ proti „1/2“) a bývá v něm
/// i špatně, proto si ji student může nastavit sám.
struct ClassGroupPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        Picker("Moje skupina", selection: $settings.classGroup) {
            Text(automaticTitle).tag(Int?.none)
            ForEach(options, id: \.self) { group in
                Text("\(group). skupina").tag(Optional(group))
            }
        }
    }

    /// Nabízené skupiny včetně té uložené, i kdyby ji rozvrh zrovna neměl.
    private var options: [Int] {
        Set(model.availableClassGroups + [model.settings.classGroup].compactMap { $0 }).sorted()
    }

    /// U volby „podle profilu“ je vidět, co profil tvrdí — student hned pozná,
    /// jestli web uvádí jeho skupinu správně.
    private var automaticTitle: String {
        guard let label = model.profile.value?.primaryGroup else { return "Podle profilu" }
        return "Podle profilu (\(label))"
    }
}

// MARK: - Seznam hodin pro jeden den

struct DayScheduleList: View {
    let day: TimetableDay?
    let periods: [LessonPeriod]
    /// Předměty třídy — podle nich se pojmenuje hodina navíc ze suplování.
    var subjects: [DisplayName] = []
    var preferredGroup: Int?
    var isToday: Bool
    /// Změny z mimořádného rozvrhu pro tenhle den, pokud nějaké jsou.
    var substitutions: SubstitutionDay?

    @Environment(StudyTaskStore.self) private var tasks
    @State private var newTask: NewTaskContext?
    @State private var detailSpot: LessonSpot?

    /// Datum, ke kterému se úkoly z tohohle dne přiřadí.
    private var date: Date {
        day?.weekday.nextOccurrence() ?? Date.startOfSchoolDay()
    }

    /// Hodiny z rozvrhu a hodiny navíc z mimořádného rozvrhu, jak jdou za sebou.
    private var items: [ScheduleItem] {
        let lessons = (day?.lessonSpots ?? []).map(ScheduleItem.lesson)
        let extras = (substitutions?.extraLessons(outside: day, group: preferredGroup) ?? []).map(ScheduleItem.extra)
        return (lessons + extras).sorted { $0.startPeriod < $1.startPeriod }
    }

    private var weekdayNumber: Int { day?.weekday.rawValue ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let substitutions {
                    SubstitutionDayBanner(day: substitutions)
                        .padding(.bottom, 2)
                }

                if items.isEmpty {
                    EmptyStateView(
                        symbol: "moon.zzz",
                        title: "Volný den",
                        message: "Tenhle den nemáš v rozvrhu žádnou výuku."
                    )
                    .padding(.top, 60)
                }

                ForEach(items) { item in
                    switch item {
                    case .lesson(let spot):
                        LessonCard(
                            spot: spot,
                            periods: periods,
                            preferredGroup: preferredGroup,
                            isCurrent: isToday && isOngoing(spot),
                            tasks: tasks.tasks(on: date, periodRange: spot.periodRange),
                            substitution: substitutions?.change(forPeriods: spot.periodRange, group: preferredGroup),
                            otherGroupSubstitution: substitutions?.otherGroupChange(
                                forPeriods: spot.periodRange,
                                group: preferredGroup
                            ),
                            onTap: { detailSpot = spot },
                            onAddTask: { kind in
                                newTask = NewTaskContext(
                                    lesson: spot.lesson(preferringGroup: preferredGroup),
                                    periodNumber: spot.periodRange.lowerBound,
                                    date: date,
                                    kind: kind
                                )
                            }
                        )
                        // Stránkovací TabView drží v hierarchii všech pět dnů naráz,
                        // takže hledání podle názvu předmětu není jednoznačné.
                        .accessibilityIdentifier("lesson-\(weekdayNumber)-\(spot.periodRange.lowerBound)")

                    case .extra(let extra):
                        ExtraLessonCard(
                            lesson: extra,
                            periods: periods,
                            subjects: subjects,
                            isToday: isToday
                        )
                        .accessibilityIdentifier("extra-\(weekdayNumber)-\(extra.periods.lowerBound)")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .sheet(item: $detailSpot) { spot in
            LessonDetailSheet(
                spot: spot,
                periods: periods,
                date: date,
                preferredGroup: preferredGroup
            )
        }
        .sheet(item: $newTask) { context in
            TaskEditorView(
                newTaskFor: context.lesson,
                periodNumber: context.periodNumber,
                date: context.date,
                kind: context.kind
            )
        }
    }

    private func isOngoing(_ spot: LessonSpot) -> Bool {
        spot.isOngoing(at: .now(), periods: periods)
    }

    enum ScheduleItem: Identifiable {
        case lesson(LessonSpot)
        case extra(ExtraLesson)

        var id: String {
            switch self {
            case .lesson(let spot): "lesson-\(spot.id)"
            case .extra(let extra): "extra-\(extra.id)"
            }
        }

        var startPeriod: Int {
            switch self {
            case .lesson(let spot): spot.periodRange.lowerBound
            case .extra(let extra): extra.periods.lowerBound
            }
        }
    }

    /// Popis nově zakládaného záznamu, předvyplněný z hodiny v rozvrhu.
    struct NewTaskContext: Identifiable {
        let id = UUID()
        let lesson: Lesson?
        let periodNumber: Int?
        let date: Date
        let kind: StudyTaskKind
    }
}

/// Karta jedné hodiny. U dělených hodin ukazuje obě skupiny.
struct LessonCard: View {
    let spot: LessonSpot
    let periods: [LessonPeriod]
    var preferredGroup: Int?
    var isCurrent: Bool
    var tasks: [StudyTask] = []
    /// Změna, která se studenta týká.
    var substitution: SubstitutionChange?
    /// Změna jen pro druhou skupinu — kartu nepřebarví, jen se pod ní zmíní.
    var otherGroupSubstitution: SubstitutionChange?
    var onTap: (() -> Void)?
    var onAddTask: ((StudyTaskKind) -> Void)?

    private var startPeriod: LessonPeriod? {
        periods.first { $0.number == spot.periodRange.lowerBound }
    }
    private var endPeriod: LessonPeriod? {
        periods.first { $0.number == spot.periodRange.upperBound }
    }

    /// Hodina, která se neučí. Karta se pak čte jako přeškrtnutá poznámka,
    /// ne jako výuka, na kterou se má někam jít.
    private var isCancelled: Bool { substitution?.isCancelled == true }

    var body: some View {
        Button {
            onTap?()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onAddTask {
                Button {
                    onAddTask(.homework)
                } label: {
                    Label("Přidat úkol", systemImage: "pencil.and.list.clipboard")
                }
                Button {
                    onAddTask(.test)
                } label: {
                    Label("Přidat test", systemImage: "exclamationmark.triangle")
                }
                Button {
                    onAddTask(.project)
                } label: {
                    Label("Přidat projekt", systemImage: "hammer")
                }
            }
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            timeColumn

            VStack(alignment: .leading, spacing: 10) {
                ForEach(orderedLessons) { lesson in
                    lessonBlock(lesson, isPrimary: lesson.id == orderedLessons.first?.id)
                }

                if let substitution {
                    Divider()
                    HStack(spacing: 8) {
                        SubstitutionBadge(change: substitution)
                        if isCancelled {
                            Text(freeTimeNote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if let otherGroupSubstitution {
                    if substitution == nil { Divider() }
                    otherGroupNote(otherGroupSubstitution)
                }

                if !tasks.isEmpty {
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(tasks) { task in
                            taskLine(task)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            if isCancelled {
                // Šrafování na zeleném podkladu — odpadlá hodina má vypadat
                // jako škrtnutý řádek v rozvrhu, ne jako běžná změna.
                Theme.cancelled.opacity(0.09)
                HatchPattern(color: Theme.cancelled.opacity(0.16))
            } else if isCurrent {
                Theme.accent.opacity(0.10)
            } else {
                Color.clear
            }
        }
        .background(.background.secondary, in: Theme.cardShape)
        .overlay {
            if isCancelled {
                // Přerušovaný rámeček: hodina v rozvrhu je, ale neplatí.
                Theme.cardShape.strokeBorder(
                    Theme.cancelled.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
            } else if isCurrent {
                Theme.cardShape.strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.5)
            } else if substitution != nil {
                Theme.cardShape.strokeBorder(Color.orange.opacity(0.45), lineWidth: 1.5)
            }
        }
        .clipShape(Theme.cardShape)
        .contentShape(.rect)
    }

    /// Krátká odměna za odpadlou hodinu. Mění se podle délky bloku, ať to
    /// není pořád dokola tatáž věta.
    private var freeTimeNote: String {
        switch spot.periodSpan {
        case 1: "máš hodinu volno"
        case 2: "máš dvě hodiny volno"
        case 3: "máš tři hodiny volno"
        default: "máš \(spot.periodSpan) hodin volno"
        }
    }

    /// Změna pro druhou skupinu. Šedě a bez odznaku: studentovi se nic nemění,
    /// ale kdyby měl skupinu nastavenou špatně, pozná to tady.
    private func otherGroupNote(_ change: SubstitutionChange) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2")
                .font(.system(size: 9, weight: .semibold))
            Text(otherGroupTitle(change) + ": " + (change.isCancelled ? "odpadá" : change.textWithoutGroup))
                .font(.caption2)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func otherGroupTitle(_ change: SubstitutionChange) -> String {
        change.groupNumber.map { "Jen \($0). skupina" } ?? "Jiná skupina"
    }

    /// Úkol navázaný na tuhle hodinu. Jen informace — odškrtává se v detailu hodiny,
    /// aby karta zůstala jedním klepnutelným celkem.
    private func taskLine(_ task: StudyTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.callout)
                .foregroundStyle(task.isDone ? Theme.taskColor(for: task.kind) : .secondary)

            Image(systemName: task.kind.symbolName)
                .font(.caption2)
                .foregroundStyle(Theme.taskColor(for: task.kind))

            Text(task.title)
                .font(.caption)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if task.hasPendingReminder {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Vlastní skupina studenta jde vždycky první.
    private var orderedLessons: [Lesson] {
        spot.lessons(preferringGroup: preferredGroup)
    }

    private var timeColumn: some View {
        VStack(spacing: 4) {
            Text("\(spot.periodRange.lowerBound)\(spot.periodSpan > 1 ? "–\(spot.periodRange.upperBound)" : "")")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(periodNumberColor)
                .strikethrough(isCancelled, color: Theme.cancelled)

            LessonTaskIndicator(tasks: tasks)

            if substitution != nil {
                Image(systemName: isCancelled ? "zzz" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isCancelled ? Theme.cancelled : Color.orange)
            }

            if let startPeriod, let endPeriod {
                Text(startPeriod.from.formatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 10)
                Text(endPeriod.to.formatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 46)
        .opacity(isCancelled ? 0.7 : 1)
    }

    private var periodNumberColor: Color {
        if isCancelled {
            Theme.cancelled
        } else if isCurrent {
            Theme.accent
        } else {
            .primary
        }
    }

    private func lessonBlock(_ lesson: Lesson, isPrimary: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SubjectMonogram(name: lesson.subject, size: 38)
                .opacity(isPrimary ? 1 : 0.55)
                // Barevná zkratka předmětu odpadlé hodině nepatří — vytáhla by
                // pozornost k něčemu, co se dnes nekoná.
                .saturation(isCancelled ? 0 : 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(lesson.subject.full)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(isCancelled, color: .secondary)
                        .foregroundStyle(isCancelled ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    if let group = lesson.group {
                        Text(group)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                isPrimary ? Theme.accent.opacity(0.18) : Color.secondary.opacity(0.14),
                                in: .capsule
                            )
                            .foregroundStyle(isPrimary ? Theme.accent : .secondary)
                    }
                }

                HStack(spacing: 10) {
                    if let classroom = lesson.classroom {
                        Label(classroom, systemImage: "mappin")
                    }
                    if let teacher = lesson.teacher {
                        Label(teacher.full, systemImage: "person")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .strikethrough(isCancelled, color: .secondary)
            }

            Spacer(minLength: 0)
        }
        .opacity(isCancelled ? 0.65 : (isPrimary ? 1 : 0.7))
    }
}

/// Hodina, kterou řádný rozvrh nemá, ale mimořádný ji přidává — třeba
/// přesunutá z jiného dne. Oranžová jako ostatní změny, ať je hned vidět,
/// že v běžném rozvrhu tahle hodina není.
struct ExtraLessonCard: View {
    let lesson: ExtraLesson
    let periods: [LessonPeriod]
    var subjects: [DisplayName] = []
    var isToday = false

    private var startPeriod: LessonPeriod? {
        periods.first { $0.number == lesson.periods.lowerBound }
    }
    private var endPeriod: LessonPeriod? {
        periods.first { $0.number == lesson.periods.upperBound }
    }

    /// Předmět podle zkratky v buňce. Když ho třída v rozvrhu nemá,
    /// zůstane jen text z tabulky.
    private var subject: DisplayName? {
        guard let abbreviation = lesson.change.subjectAbbreviation else { return nil }
        return subjects.first { $0.short?.caseInsensitiveCompare(abbreviation) == .orderedSame }
    }

    private var isCurrent: Bool {
        guard isToday, let startPeriod, let endPeriod else { return false }
        let now = TimeOfDay.now()
        return now >= startPeriod.from && now <= endPeriod.to
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            timeColumn

            HStack(alignment: .top, spacing: 12) {
                if let subject {
                    SubjectMonogram(name: subject, size: 38)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.orange.gradient, in: .rect(cornerRadius: 38 * 0.3, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(subject?.full ?? lesson.change.displayText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        SubstitutionBadge(change: lesson.change)
                        Text(lesson.change.isConfirmed ? "hodina navíc" : "hodina navíc • upřesní se")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(isCurrent ? Theme.accent.opacity(0.10) : Color.orange.opacity(0.06))
        .background(.background.secondary, in: Theme.cardShape)
        .overlay {
            Theme.cardShape.strokeBorder(
                isCurrent ? Theme.accent.opacity(0.55) : Color.orange.opacity(0.45),
                lineWidth: 1.5
            )
        }
        .clipShape(Theme.cardShape)
        .accessibilityElement(children: .combine)
    }

    private var timeColumn: some View {
        VStack(spacing: 4) {
            Text("\(lesson.periods.lowerBound)\(lesson.periods.count > 1 ? "–\(lesson.periods.upperBound)" : "")")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Theme.accent : .orange)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)

            if let startPeriod, let endPeriod {
                Text(startPeriod.from.formatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 10)
                Text(endPeriod.to.formatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 46)
    }
}

// MARK: - Týdenní mřížka

struct WeekGridView: View {
    let timetable: Timetable
    var preferredGroup: Int?
    /// Změny z mimořádného rozvrhu po dnech. Odpadlé i změněné hodiny mají
    /// jít poznat na první pohled, stejně jako v denním přehledu.
    var substitutions: [Weekday: SubstitutionDay] = [:]

    /// Hodiny navíc ze suplování — ve volných hodinách řádného rozvrhu.
    private var extraLessons: [Weekday: [ExtraLesson]] {
        substitutions.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.extraLessons(outside: timetable.day(entry.key), group: preferredGroup)
        }
    }

    /// Sloupce až po poslední hodinu, kdy se v týdnu něco děje — i když je
    /// to hodina navíc, kterou řádný rozvrh nemá.
    private func columns(extras: [Weekday: [ExtraLesson]]) -> [LessonPeriod] {
        let occupied = timetable.occupiedPeriods
        guard let lastExtra = extras.values.flatMap({ $0 }).map(\.periods.upperBound).max(),
              lastExtra > occupied.last?.number ?? .max else { return occupied }
        return timetable.periods.filter { $0.number <= lastExtra }
    }

    var body: some View {
        let extras = extraLessons
        let periods = columns(extras: extras)

        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Color.clear.frame(width: 34, height: 1)
                    ForEach(periods) { period in
                        VStack(spacing: 1) {
                            Text("\(period.number)")
                                .font(.caption.weight(.bold))
                            Text(period.from.formatted)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 78)
                    }
                }

                ForEach(Weekday.allCases) { weekday in
                    GridRow {
                        Text(weekday.shortName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(weekday == Weekday.today() ? Theme.accent : .secondary)
                            .frame(width: 34)

                        ForEach(periods) { period in
                            gridCell(weekday: weekday, period: period, extras: extras[weekday] ?? [])
                        }
                    }
                }
            }
            .padding(18)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func gridCell(weekday: Weekday, period: LessonPeriod, extras: [ExtraLesson]) -> some View {
        if let spot = timetable.day(weekday)?.spot(atPeriod: period.number), !spot.isEmpty {
            // Změna se hledá přes celý blok, ať je vícehodinovka obarvená celá.
            return WeekGridCell(
                spot: spot,
                isStart: spot.periodRange.lowerBound == period.number,
                preferredGroup: preferredGroup,
                change: substitutions[weekday]?.change(forPeriods: spot.periodRange, group: preferredGroup)
            )
        }

        let extra = extras.first { $0.periods.contains(period.number) }
        return WeekGridCell(
            spot: nil,
            isStart: extra.map { $0.periods.lowerBound == period.number } ?? true,
            preferredGroup: preferredGroup,
            change: extra?.change
        )
    }
}

/// Jedna buňka týdenní mřížky. Změny vypadají jako na kartách v denním
/// přehledu: odpadlá hodina je zelená, šrafovaná a s přerušovaným rámečkem,
/// změněná oranžová s textem z tabulky suplování.
private struct WeekGridCell: View {
    let spot: LessonSpot?
    /// Vícehodinovka se vykreslí jen na svém začátku, ostatní buňky zůstanou tlumené.
    let isStart: Bool
    var preferredGroup: Int?
    var change: SubstitutionChange?

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// Škrtá se jen skutečná hodina — ve volné hodině nemá co odpadnout.
    private var isCancelled: Bool { spot != nil && change?.isCancelled == true }
    private var isChanged: Bool { change != nil && change?.isCancelled != true }

    var body: some View {
        VStack(spacing: 2) {
            if let spot, isStart, let lesson = spot.lesson(preferringGroup: preferredGroup) {
                lessonContent(lesson, isSplit: spot.isSplit)
            } else if spot == nil, isStart, let change, isChanged {
                // Hodina, která v řádném rozvrhu není — přidaná nebo přesunutá.
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
                changeText(change, lineLimit: 2)
            } else if spot != nil || isChanged {
                Image(systemName: "arrow.left")
                    .font(.system(size: 9))
                    .foregroundStyle(isChanged ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.horizontal, 4)
        .frame(width: 78, height: 54)
        .background { background }
        .overlay { border }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func lessonContent(_ lesson: Lesson, isSplit: Bool) -> some View {
        HStack(spacing: 3) {
            if isChanged {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Text(lesson.subject.abbreviation)
                .font(.caption.weight(.bold))
                .strikethrough(isCancelled, color: Theme.cancelled)
                .foregroundStyle(isCancelled ? Color.secondary : Color.primary)
        }
        .lineLimit(1)

        if isCancelled {
            Label("odpadá", systemImage: "zzz")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.cancelled)
                .lineLimit(1)
        } else if let change {
            // Učebna a vyučující ze suplování nahrazují ty z řádného rozvrhu.
            changeText(change, lineLimit: isSplit ? 1 : 2)
        } else {
            Text(lesson.classroom ?? "—")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }

        if isSplit {
            Text(lesson.group ?? "")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    /// Text buňky z tabulky suplování. Do úzké buňky se nevejde vždycky,
    /// proto se smí zalomit a trochu zmenšit.
    private func changeText(_ change: SubstitutionChange, lineLimit: Int) -> some View {
        Text(change.displayText)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var background: some View {
        if isCancelled {
            shape.fill(Theme.cancelled.opacity(isStart ? 0.14 : 0.06))
            HatchPattern(color: Theme.cancelled.opacity(0.14), spacing: 7, lineWidth: 1.5)
                .clipShape(shape)
        } else if isChanged {
            shape.fill(Color.orange.opacity(isStart ? 0.14 : 0.06))
        } else if spot != nil {
            shape.fill(Theme.accent.opacity(isStart ? 0.12 : 0.05))
        } else {
            shape.fill(Color.secondary.opacity(0.06))
        }
    }

    @ViewBuilder
    private var border: some View {
        if isCancelled {
            // Přerušovaný rámeček jako u karty: hodina v rozvrhu je, ale neplatí.
            shape.strokeBorder(
                Theme.cancelled.opacity(0.55),
                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
            )
        } else if isChanged {
            shape.strokeBorder(Color.orange.opacity(0.5), lineWidth: 1.2)
        }
    }
}

// MARK: - Skeleton

struct TimetableSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 12) {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 20, height: 18)
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 34, height: 10)
                        }
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 150, height: 14)
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 100, height: 11)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(.background.secondary, in: Theme.cardShape)
                }
            }
            .padding(.horizontal, 18)
            .redacted(reason: .placeholder)
        }
    }
}

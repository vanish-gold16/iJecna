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
            switch layout {
            case .day: dayLayout(page)
            case .week: WeekGridView(
                page: page,
                preferredGroup: model.profile.value?.primaryGroup,
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

    private func dayLayout(_ page: TimetablePage) -> some View {
        VStack(spacing: 0) {
            dayPicker

            TabView(selection: $selectedDay) {
                ForEach(Weekday.allCases) { weekday in
                    DayScheduleList(
                        day: page.timetable.day(weekday),
                        periods: page.timetable.periods,
                        preferredGroup: model.profile.value?.primaryGroup,
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
}

// MARK: - Seznam hodin pro jeden den

struct DayScheduleList: View {
    let day: TimetableDay?
    let periods: [LessonPeriod]
    var preferredGroup: String?
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

    var body: some View {
        ScrollView {
            if let day, !day.isEmpty {
                VStack(spacing: 10) {
                    if let substitutions {
                        SubstitutionDayBanner(day: substitutions)
                            .padding(.bottom, 2)
                    }

                    ForEach(day.lessonSpots) { spot in
                        LessonCard(
                            spot: spot,
                            periods: periods,
                            preferredGroup: preferredGroup,
                            isCurrent: isToday && isOngoing(spot),
                            tasks: tasks.tasks(on: date, periodRange: spot.periodRange),
                            substitution: substitutions?.change(forPeriods: spot.periodRange),
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
                        .accessibilityIdentifier("lesson-\(day.weekday.rawValue)-\(spot.periodRange.lowerBound)")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 44)
            } else {
                EmptyStateView(
                    symbol: "moon.zzz",
                    title: "Volný den",
                    message: "Tenhle den nemáš v rozvrhu žádnou výuku."
                )
                .padding(.top, 60)
            }
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
    var preferredGroup: String?
    var isCurrent: Bool
    var tasks: [StudyTask] = []
    var substitution: SubstitutionChange?
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
        guard let preferredGroup else { return spot.lessons }
        return spot.lessons.sorted { lhs, _ in lhs.group == preferredGroup }
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

// MARK: - Týdenní mřížka

struct WeekGridView: View {
    let page: TimetablePage
    var preferredGroup: String?
    /// Změny z mimořádného rozvrhu po dnech — v mřížce jde hlavně o to,
    /// aby odpadlé hodiny šly poznat na první pohled.
    var substitutions: [Weekday: SubstitutionDay] = [:]

    private var periods: [LessonPeriod] { page.timetable.occupiedPeriods }

    var body: some View {
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
                            gridCell(weekday: weekday, period: period)
                        }
                    }
                }
            }
            .padding(18)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private func gridCell(weekday: Weekday, period: LessonPeriod) -> some View {
        let day = page.timetable.day(weekday)
        let spot = day?.spot(atPeriod: period.number)

        if let spot, !spot.isEmpty {
            // Vícehodinovka se vykreslí jen na svém začátku, ostatní buňky zůstanou tlumené.
            let isStart = spot.periodRange.lowerBound == period.number
            let lesson = spot.lesson(preferringGroup: preferredGroup)
            let isCancelled = substitutions[weekday]?.change(forPeriods: spot.periodRange)?.isCancelled == true

            VStack(spacing: 2) {
                if isStart, let lesson {
                    Text(lesson.subject.abbreviation)
                        .font(.caption.weight(.bold))
                        .strikethrough(isCancelled, color: Theme.cancelled)
                        .foregroundStyle(isCancelled ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    if isCancelled {
                        Label("odpadá", systemImage: "zzz")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.cancelled)
                            .lineLimit(1)
                    } else {
                        Text(lesson.classroom ?? "—")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if spot.isSplit {
                        Text(lesson.group ?? "")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                } else {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 78, height: 54)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                if isCancelled {
                    shape.fill(Theme.cancelled.opacity(isStart ? 0.14 : 0.06))
                    HatchPattern(color: Theme.cancelled.opacity(0.14), spacing: 7, lineWidth: 1.5)
                        .clipShape(shape)
                } else {
                    shape.fill(Theme.accent.opacity(isStart ? 0.12 : 0.05))
                }
            }
        } else {
            Color.secondary.opacity(0.06)
                .frame(width: 78, height: 54)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
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

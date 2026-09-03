import SwiftUI

struct DashboardView: View {
    @Binding var selection: AppTab
    @Environment(AppModel.self) private var model
    @Namespace private var glassNamespace

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        HeroLessonCard(namespace: glassNamespace)

                        if model.newGrades.hasUnseen {
                            NewGradesSection(selection: $selection)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        TodayScheduleSection(selection: $selection)

                        AverageSummarySection(selection: $selection)

                        RecentGradesSection()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .refreshable { await model.refreshDashboard() }
            }
            .navigationTitle("Dnes")
            .navigationSubtitle(todayLabel)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Poznámky a pochvaly")
                }
            }
            .task {
                await model.loadGrades()
                await model.loadTimetable()
            }
            .animation(.smooth, value: model.newGrades.unseenCount)
        }
    }

    private var todayLabel: String {
        DateFormatter.jecnaWeekdayLong.string(from: .now).capitalizedFirst
    }
}

// MARK: - Hero

/// Hlavní karta obrazovky: co se právě učí, nebo co přijde.
struct HeroLessonCard: View {
    var namespace: Namespace.ID
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            switch model.timetable {
            case .idle, .loading:
                GlassCard { placeholder }
            case .failed(let error):
                GlassCard { compactError(error) }
            case .loaded(let page, _):
                content(for: page.timetable.moment(group: model.profile.value?.primaryGroup))
            }
        }
    }

    @ViewBuilder
    private func content(for moment: LessonMoment) -> some View {
        if let lesson = moment.lesson, let startPeriod = moment.startPeriod, let endPeriod = moment.endPeriod {
            GlassCard(tint: tint(for: moment.kind)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: moment.kind))
                            .font(.caption.weight(.semibold))
                        Text(headline(for: moment))
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(tint(for: moment.kind))

                    HStack(alignment: .top, spacing: 14) {
                        SubjectMonogram(name: lesson.subject, size: 54)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(lesson.subject.full)
                                .font(.title2.weight(.bold))
                                .lineLimit(2)

                            HStack(spacing: 10) {
                                if let classroom = lesson.classroom {
                                    Label(classroom, systemImage: "mappin.and.ellipse")
                                }
                                if let periodLabel = moment.periodLabel {
                                    Label(periodLabel, systemImage: "clock")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            if let teacher = lesson.teacher {
                                Label(teacher.full, systemImage: "person")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if case .ongoing(let progress) = moment.kind {
                        VStack(spacing: 6) {
                            ProgressView(value: progress)
                                .tint(tint(for: moment.kind))
                            HStack {
                                Text(startPeriod.from.formatted)
                                Spacer()
                                Text(remainingText(until: endPeriod))
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(endPeriod.to.formatted)
                            }
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                    } else if let group = lesson.group {
                        Label("Skupina \(group)", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .glassEffectID("hero", in: namespace)
        } else {
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: symbol(for: moment.kind))
                        .font(.title)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline(for: moment))
                            .font(.headline)
                        Text(moment.kind == .weekend ? "Užij si volno." : "Zbytek dne je tvůj.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .glassEffectID("hero", in: namespace)
        }
    }

    private var placeholder: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: 160, height: 18)
                RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: 110, height: 13)
            }
            Spacer()
        }
        .redacted(reason: .placeholder)
        .frame(height: 88)
    }

    private func compactError(_ error: JecnaError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: error.symbolName)
                .font(.title3)
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "Rozvrh se nepodařilo načíst")
                .font(.subheadline)
            Spacer()
            Button("Znovu") {
                Task { await model.loadTimetable(force: true) }
            }
            .buttonStyle(.glass)
        }
    }

    private func headline(for moment: LessonMoment) -> String {
        switch moment.kind {
        case .ongoing: "Právě probíhá"
        case .intermission(let minutes): "Přestávka • pokračuje za \(minutes) min"
        case .upcoming(let minutes): "Za \(minutes) min"
        case .freePeriod(let minutes): "Volná hodina • dál za \(minutes) min"
        case .dayFinished: "Dnes už máš odučeno"
        case .weekend: "Víkend"
        }
    }

    private func symbol(for kind: LessonMoment.Kind) -> String {
        switch kind {
        case .ongoing: "waveform"
        case .intermission: "pause.circle"
        case .upcoming: "clock.badge"
        case .freePeriod: "cup.and.saucer"
        case .dayFinished: "checkmark.seal"
        case .weekend: "sun.max"
        }
    }

    private func tint(for kind: LessonMoment.Kind) -> Color {
        switch kind {
        case .ongoing: Theme.accent
        case .intermission: .orange
        case .upcoming: .indigo
        case .freePeriod: .teal
        default: .secondary
        }
    }

    private func remainingText(until period: LessonPeriod) -> String {
        let now = TimeOfDay.now()
        let remaining = max(0, period.to.minutesFromMidnight - now.minutesFromMidnight)
        return "zbývá \(remaining) min"
    }
}

// MARK: - Nové známky

struct NewGradesSection: View {
    @Binding var selection: AppTab
    @Environment(AppModel.self) private var model

    private var items: [(subject: Subject, grade: Grade)] {
        guard let page = model.grades.value else { return [] }
        return page.subjects
            .flatMap { subject in subject.allGrades.map { (subject, $0) } }
            .filter { model.newGrades.isNew($0.1) }
            .sorted { ($0.1.receivedAt ?? .distantPast) > ($1.1.receivedAt ?? .distantPast) }
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Nové známky",
                    subtitle: "\(items.count) od posledního otevření"
                ) {
                    Button("Zobrazit vše") { selection = .grades }
                        .font(.subheadline)
                }

                GlassCard(tint: Theme.accent) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(3).enumerated()), id: \.element.grade.id) { index, item in
                            if index > 0 { Divider().padding(.vertical, 10) }
                            NewGradeRow(subject: item.subject, grade: item.grade)
                        }
                    }
                }
            }
        }
    }
}

private struct NewGradeRow: View {
    let subject: Subject
    let grade: Grade

    var body: some View {
        HStack(spacing: 12) {
            GradeBadge(grade: grade)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name.full)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let detail = grade.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            NewBadge()
        }
    }
}

// MARK: - Dnešní rozvrh

struct TodayScheduleSection: View {
    @Binding var selection: AppTab
    @Environment(AppModel.self) private var model

    private var today: Weekday? { Weekday.today() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Dnešní rozvrh", subtitle: today?.fullName) {
                Button("Celý týden") { selection = .timetable }
                    .font(.subheadline)
            }

            if let page = model.timetable.value, let today, let day = page.timetable.day(today) {
                if day.isEmpty {
                    ContentCard {
                        Label("Dnes se neučí", systemImage: "moon.zzz")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                } else {
                    ContentCard {
                        VStack(spacing: 0) {
                            ForEach(Array(day.lessonSpots.enumerated()), id: \.element.id) { index, spot in
                                if index > 0 {
                                    Divider().padding(.leading, 66)
                                }
                                CompactLessonRow(
                                    spot: spot,
                                    periods: page.timetable.periods,
                                    preferredGroup: model.profile.value?.primaryGroup,
                                    isCurrent: isCurrent(spot, periods: page.timetable.periods)
                                )
                            }
                        }
                    }
                }
            } else if today == nil {
                ContentCard {
                    Label("Víkend — žádná výuka", systemImage: "sun.max")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            } else {
                ContentCard {
                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack {
                                RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: 44, height: 14)
                                RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(height: 14)
                            }
                        }
                    }
                    .padding(16)
                    .redacted(reason: .placeholder)
                }
            }
        }
    }

    private func isCurrent(_ spot: LessonSpot, periods: [LessonPeriod]) -> Bool {
        spot.isOngoing(at: .now(), periods: periods)
    }
}

struct CompactLessonRow: View {
    let spot: LessonSpot
    let periods: [LessonPeriod]
    var preferredGroup: String?
    var isCurrent: Bool = false

    private var lesson: Lesson? { spot.lesson(preferringGroup: preferredGroup) }

    private var timeRange: String {
        let start = periods.first { $0.number == spot.periodRange.lowerBound }
        let end = periods.first { $0.number == spot.periodRange.upperBound }
        guard let start, let end else { return "" }
        return "\(start.from.formatted)\n\(end.to.formatted)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(timeRange)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                .multilineTextAlignment(.trailing)
                .frame(width: 42, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(isCurrent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson?.subject.full ?? "Volná hodina")
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let classroom = lesson?.classroom {
                        Text(classroom)
                    }
                    if let teacher = lesson?.teacher?.abbreviation {
                        Text(teacher)
                    }
                    if spot.periodSpan > 1 {
                        Text("\(spot.periodSpan)h")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if spot.isSplit {
                Image(systemName: "person.2")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isCurrent ? Theme.accent.opacity(0.08) : .clear)
    }
}

// MARK: - Průměry

struct AverageSummarySection: View {
    @Binding var selection: AppTab
    @Environment(AppModel.self) private var model

    var body: some View {
        if let page = model.grades.value {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    "Prospěch",
                    subtitle: "\(page.schoolYear.displayName) • \(page.half.displayName)"
                )

                GlassEffectContainer(spacing: 14) {
                    HStack(spacing: 14) {
                        GlassCard(radius: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Celkový průměr")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                AverageLabel(average: page.overallAverage, style: .prominent)
                                Text("\(page.totalGradeCount) známek")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        GlassCard(radius: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nejhorší předmět")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let worst = worstSubject(page) {
                                    Text(worst.name.abbreviation)
                                        .font(.largeTitle.weight(.bold))
                                        .foregroundStyle(Theme.averageColor(for: worst.average ?? 3))
                                    Text(worst.average?.averageFormatted ?? "—")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text("—").font(.largeTitle.weight(.bold)).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .onTapGesture { selection = .grades }
            }
        }
    }

    private func worstSubject(_ page: GradesPage) -> Subject? {
        page.subjects
            .filter { $0.average != nil }
            .max { ($0.average ?? 0) < ($1.average ?? 0) }
    }
}

// MARK: - Poslední známky

struct RecentGradesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recent = model.recentGrades(limit: 5)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Poslední známky")

                ContentCard {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.grade.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 60) }
                            NavigationLink {
                                SubjectDetailView(subject: item.subject)
                            } label: {
                                RecentGradeRow(subject: item.subject, grade: item.grade)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct RecentGradeRow: View {
    let subject: Subject
    let grade: Grade

    var body: some View {
        HStack(spacing: 12) {
            GradeBadge(grade: grade, size: .small)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name.full)
                    .font(.subheadline)
                    .lineLimit(1)
                if let detail = grade.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let date = grade.receivedAt {
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

import SwiftUI

struct GradesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ZStack {
                AuroraBackground()
                content
            }
            .navigationTitle("Známky")
            .navigationSubtitle(periodLabel)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    periodMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
            }
            .task { await model.loadGrades() }
        }
    }

    private var periodLabel: String {
        "\(model.selectedYear.displayName) • \(model.selectedHalf.shortName)"
    }

    @ViewBuilder
    private var content: some View {
        switch model.grades {
        case .idle, .loading:
            SubjectListSkeleton()
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await model.loadGrades(force: true) }
            }
        case .loaded(let page, _):
            loadedContent(page)
        }
    }

    private func loadedContent(_ page: GradesPage) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                GradesSummaryHeader(page: page)

                if page.subjects.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "Žádné předměty",
                        message: "Pro tohle období nejsou k dispozici žádná data."
                    )
                    .padding(.top, 40)
                } else {
                    ContentCard {
                        VStack(spacing: 0) {
                            ForEach(Array(model.sortedSubjects(page).enumerated()), id: \.element.id) { index, subject in
                                if index > 0 { Divider().padding(.leading, 68) }
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                } label: {
                                    SubjectRow(subject: subject)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    BehaviourCard(behaviour: page.behaviour)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await model.loadGrades(force: true) }
    }

    private var periodMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Pololetí", selection: $model.selectedHalf) {
                ForEach(SchoolYearHalf.allCases) { half in
                    Text(half.displayName).tag(half)
                }
            }
            Divider()
            Picker("Školní rok", selection: $model.selectedYear) {
                ForEach(SchoolYear.recent()) { year in
                    Text(year.displayName).tag(year)
                }
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
        }
        .accessibilityLabel("Vybrat období")
    }

    private var sortMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Řazení", selection: $model.settings.subjectSorting) {
                ForEach(AppSettings.SubjectSorting.allCases) { sorting in
                    Text(sorting.title).tag(sorting)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Řazení předmětů")
    }
}

// MARK: - Souhrn

struct GradesSummaryHeader: View {
    let page: GradesPage
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            GlassCard(tint: page.overallAverage.map { Theme.averageColor(for: $0) }) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vážený průměr")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AverageLabel(average: page.overallAverage, style: .prominent)
                        Text("ze všech \(page.totalGradeCount) známek")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 0)

                    GradeDistributionChart(grades: page.subjects.flatMap(\.allGrades))
                        .frame(width: 120, height: 58)
                }
            }
        }
    }
}

/// Sloupcový přehled, kolik je kterých známek. Rychlejší čtení než průměr sám.
struct GradeDistributionChart: View {
    let grades: [Grade]

    private var counts: [(value: Int, count: Int)] {
        (1...5).map { value in
            (value, grades.filter { $0.value == value }.count)
        }
    }

    private var maxCount: Int { max(1, counts.map(\.count).max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(counts, id: \.value) { item in
                VStack(spacing: 3) {
                    Text(item.count == 0 ? " " : "\(item.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.gradeColor(for: item.value).gradient)
                        .frame(height: max(3, 34 * CGFloat(item.count) / CGFloat(maxCount)))
                        .opacity(item.count == 0 ? 0.2 : 1)
                    Text("\(item.value)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rozložení známek")
        .accessibilityValue(counts.map { "\($0.value): \($0.count)" }.joined(separator: ", "))
    }
}

// MARK: - Řádek předmětu

struct SubjectRow: View {
    let subject: Subject
    @Environment(AppModel.self) private var model

    private var hasNew: Bool {
        subject.allGrades.contains { model.newGrades.isNew($0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            SubjectMonogram(name: subject.name)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(subject.name.full)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if hasNew { NewBadge() }
                    Spacer(minLength: 0)
                }

                if subject.isEmpty {
                    Text("Zatím bez známek")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    GradeStrip(grades: subject.gradesNewestFirst, highlight: model.newGrades)
                }
            }

            .layoutPriority(1)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                AverageLabel(average: subject.average)
                if let finalGrade = subject.finalGrade {
                    FinalGradeBadge(finalGrade: finalGrade)
                }
            }
            // Průměr má přednost před názvem předmětu — bez toho ho vyšší
            // priorita levého sloupce vytlačí na nulovou šířku.
            .fixedSize(horizontal: true, vertical: false)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

/// Vodorovný proužek známek. Když se nevejdou, poslední pole ukáže „+n“.
struct GradeStrip: View {
    let grades: [Grade]
    var highlight: NewGradesTracker?
    var limit: Int = 6

    var body: some View {
        HStack(spacing: 5) {
            ForEach(grades.prefix(limit)) { grade in
                GradeBadge(grade: grade, size: .small)
                    .overlay {
                        if highlight?.isNew(grade) == true {
                            Circle()
                                .strokeBorder(Theme.accent, lineWidth: 2)
                                .padding(-2.5)
                        }
                    }
            }
            if grades.count > limit {
                Text("+\(grades.count - limit)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
    }
}

// MARK: - Chování

struct BehaviourCard: View {
    let behaviour: Behaviour

    var body: some View {
        NavigationLink {
            NotificationsView()
        } label: {
            ContentCard {
                HStack(spacing: 12) {
                    Image(systemName: "figure.stand")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 42, height: 42)
                        .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chování")
                            .font(.subheadline.weight(.medium))
                        Text(behaviour.notificationIds.isEmpty
                             ? "Bez záznamů"
                             : "\(behaviour.notificationIds.count) záznamů")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let finalGrade = behaviour.finalGrade {
                        FinalGradeBadge(finalGrade: finalGrade)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skeleton

struct SubjectListSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: 110, height: 12)
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 80, height: 32)
                        }
                        Spacer()
                    }
                }
                ContentCard {
                    VStack(spacing: 18) {
                        ForEach(0..<7, id: \.self) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 140, height: 13)
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 90, height: 11)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 18)
            .redacted(reason: .placeholder)
        }
    }
}

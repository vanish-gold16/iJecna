import SwiftUI
import UserNotifications

struct TasksView: View {
    @Environment(StudyTaskStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var filter: Filter = .open
    @State private var editedTask: StudyTask?
    @State private var isCreating = false
    /// Den z kalendáře, na který se má seznam posunout.
    @State private var scrollTarget: String?
    /// Prázdný den z kalendáře — nový záznam se na něj rovnou předvyplní.
    @State private var newTaskDay: NewTaskDay?
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    enum Filter: String, CaseIterable, Identifiable {
        case open = "Aktivní"
        case tests = "Testy"
        case done = "Hotovo"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                content
            }
            .navigationTitle("Úkoly")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Filtr", selection: $filter) {
                        ForEach(Filter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nový úkol")
                }
            }
            .sheet(isPresented: $isCreating) {
                TaskEditorView(
                    newTaskFor: nil,
                    periodNumber: nil,
                    date: Date.startOfSchoolDay()
                )
            }
            .sheet(item: $editedTask) { task in
                TaskEditorView(task: task, isNew: false)
            }
            .sheet(item: $newTaskDay) { day in
                TaskEditorView(newTaskFor: nil, periodNumber: nil, date: day.date, kind: day.kind)
            }
            .task {
                authorizationStatus = await store.notificationAuthorizationStatus()
            }
        }
    }

    private var subtitle: String {
        let open = store.overdue.count + store.dueToday.count
        if open == 0 { return "Nic naléhavého" }
        return open == 1 ? "1 úkol na teď" : "\(open) úkolů na teď"
    }

    // MARK: - Obsah

    @ViewBuilder
    private var content: some View {
        let sections = groupedSections

        VStack(spacing: 14) {
            if filter != .done {
                TaskCalendarStrip(summary: calendarSummary, onSelect: selectDay)
            }

            if sections.isEmpty {
                emptyState
                    .frame(maxHeight: .infinity)
            } else {
                list(sections)
            }
        }
    }

    private func list(_ sections: [TaskSection]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    if shouldWarnAboutPermission {
                        permissionBanner
                    }

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: section.title, subtitle: section.subtitle) {
                                TaskSummaryChips(summary: DayTaskSummary(tasks: section.tasks))
                            }
                            ContentCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(section.tasks.enumerated()), id: \.element.id) { index, task in
                                        if index > 0 { Divider().padding(.leading, 62) }
                                        taskRow(task, showsDueDate: section.date == nil)
                                    }
                                }
                            }
                            .overlay {
                                // Den s testem dostane oranžový lem, zmeškané červený —
                                // ať je to vidět i při rychlém projetí.
                                if let accent = section.accent {
                                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                        .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
                                }
                            }
                        }
                        .id(section.id)
                    }

                    if filter == .done && !store.tasks.filter(\.isDone).isEmpty {
                        Button("Smazat splněné", role: .destructive) {
                            withAnimation { store.clearCompleted() }
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 44)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.smooth) { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
    }

    // MARK: - Kalendář

    /// V kalendáři se ukazuje totéž, co v seznamu pod ním.
    private func calendarSummary(_ day: Date) -> DayTaskSummary {
        let tasks = store.tasks(on: day)
        return DayTaskSummary(tasks: filter == .tests ? tasks.filter { $0.kind == .test } : tasks)
    }

    /// Den se záznamy posune seznam na sebe, prázdný den rovnou nabídne nový záznam.
    private func selectDay(_ day: Date) {
        if groupedSections.contains(where: { $0.date == day }) {
            scrollTarget = TaskSection.id(for: day)
        } else {
            newTaskDay = NewTaskDay(date: day, kind: filter == .tests ? .test : .homework)
        }
    }

    struct NewTaskDay: Identifiable {
        let date: Date
        let kind: StudyTaskKind
        var id: Date { date }
    }

    private func taskRow(_ task: StudyTask, showsDueDate: Bool = true) -> some View {
        Button {
            editedTask = task
        } label: {
            TaskRow(task: task, showsDueDate: showsDueDate) {
                withAnimation(.smooth) { store.toggleDone(task) }
                Haptics.impact(.soft)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editedTask = task
            } label: {
                Label("Upravit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                withAnimation { store.delete(task) }
            } label: {
                Label("Smazat", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: filter == .done ? "checkmark.circle" : "checklist",
            title: filter == .done ? "Zatím nic splněného" : "Žádné úkoly",
            message: filter == .tests
                ? "Termíny testů si přidáš tlačítkem plus nebo přímo z rozvrhu."
                : "Úkol přidáš tlačítkem plus, nebo podržením hodiny v rozvrhu."
        )
    }

    // MARK: - Upozornění na oprávnění

    private var shouldWarnAboutPermission: Bool {
        authorizationStatus == .denied && store.tasks.contains { $0.hasPendingReminder }
    }

    private var permissionBanner: some View {
        GlassCard(tint: .orange) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upozornění jsou vypnutá")
                        .font(.subheadline.weight(.semibold))
                    Text("Termíny máš nastavené, ale systém je nedoručí.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Nastavení") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: - Řazení do sekcí

    private struct TaskSection: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let tasks: [StudyTask]
        /// Den, ke kterému sekce patří. `nil` u souhrnných sekcí (po termínu, splněné).
        var date: Date? = nil

        static func id(for day: Date) -> String { "day-\(day.timeIntervalSince1970)" }

        var accent: Color? {
            if id == "overdue" { return .red }
            guard date != nil, tasks.contains(where: { $0.kind == .test && !$0.isDone }) else { return nil }
            return .orange
        }
    }

    private func overdueSubtitle(_ count: Int) -> String {
        switch count {
        case 1: "1 nesplněný"
        case 2...4: "\(count) nesplněné"
        default: "\(count) nesplněných"
        }
    }

    private var groupedSections: [TaskSection] {
        switch filter {
        case .done:
            let done = store.tasks
                .filter(\.isDone)
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return done.isEmpty ? [] : [TaskSection(id: "done", title: "Splněné", subtitle: "\(done.count) záznamů", tasks: done)]

        case .tests:
            return daySections(for: store.upcomingTests)

        case .open:
            var sections: [TaskSection] = []

            let overdue = store.overdue
            if !overdue.isEmpty {
                sections.append(TaskSection(id: "overdue", title: "Po termínu", subtitle: overdueSubtitle(overdue.count), tasks: overdue))
            }

            let upcoming = store.tasks.filter { !$0.isDone && $0.daysUntilDue() >= 0 }
            return sections + daySections(for: upcoming)
        }
    }

    /// Každý den vlastní sekce — „Zítra“, „Čtvrtek“ — ať je hned jasné,
    /// na kdy co je, a ne jen „za 3 dny“ u každého řádku.
    private func daySections(for tasks: [StudyTask]) -> [TaskSection] {
        Dictionary(grouping: tasks, by: \.dueDate)
            .sorted { $0.key < $1.key }
            .map { day, tasks in
                TaskSection(
                    id: TaskSection.id(for: day),
                    title: day.relativeDayName(),
                    subtitle: daySubtitle(day),
                    tasks: tasks.sorted { ($0.periodNumber ?? Int.max, $0.createdAt) < ($1.periodNumber ?? Int.max, $1.createdAt) },
                    date: day
                )
            }
    }

    /// „úterý 13. 10.“ u dneška a zítřka, jinak „15. 10. • za 3 dny“.
    private func daySubtitle(_ day: Date) -> String {
        let days = day.schoolDaysFromToday()
        let date = DateFormatter.jecnaDayMonth.string(from: day)
        switch days {
        case 0, 1:
            return DateFormatter.jecnaWeekdayLong.string(from: day)
        default:
            let distance = days < 5 ? "za \(days) dny" : "za \(days) dnů"
            return day.isInNextWeek() ? "\(date) • příští týden • \(distance)" : "\(date) • \(distance)"
        }
    }
}

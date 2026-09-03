import SwiftUI
import UserNotifications

struct TasksView: View {
    @Environment(StudyTaskStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var filter: Filter = .open
    @State private var editedTask: StudyTask?
    @State private var isCreating = false
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

        if sections.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    if shouldWarnAboutPermission {
                        permissionBanner
                    }

                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(section.title, subtitle: section.subtitle)
                            ContentCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(section.tasks.enumerated()), id: \.element.id) { index, task in
                                        if index > 0 { Divider().padding(.leading, 62) }
                                        taskRow(task)
                                    }
                                }
                            }
                        }
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
        }
    }

    private func taskRow(_ task: StudyTask) -> some View {
        Button {
            editedTask = task
        } label: {
            TaskRow(task: task) {
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

    private struct TaskSection {
        let title: String
        let subtitle: String?
        let tasks: [StudyTask]
    }

    private var groupedSections: [TaskSection] {
        switch filter {
        case .done:
            let done = store.tasks
                .filter(\.isDone)
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return done.isEmpty ? [] : [TaskSection(title: "Splněné", subtitle: "\(done.count) záznamů", tasks: done)]

        case .tests:
            let tests = store.upcomingTests
            return tests.isEmpty ? [] : [TaskSection(title: "Nadcházející testy", subtitle: nil, tasks: tests)]

        case .open:
            var sections: [TaskSection] = []

            let overdue = store.overdue
            if !overdue.isEmpty {
                sections.append(TaskSection(title: "Po termínu", subtitle: "\(overdue.count) nesplněných", tasks: overdue))
            }

            let today = store.dueToday
            if !today.isEmpty {
                sections.append(TaskSection(title: "Dnes", subtitle: nil, tasks: today))
            }

            let open = store.tasks.filter { !$0.isDone }
            let thisWeek = open
                .filter { (1...7).contains($0.daysUntilDue()) }
                .sorted { ($0.dueDate, $0.periodNumber ?? Int.max) < ($1.dueDate, $1.periodNumber ?? Int.max) }
            if !thisWeek.isEmpty {
                sections.append(TaskSection(title: "Nejbližších sedm dní", subtitle: nil, tasks: thisWeek))
            }

            let later = open
                .filter { $0.daysUntilDue() > 7 }
                .sorted { $0.dueDate < $1.dueDate }
            if !later.isEmpty {
                sections.append(TaskSection(title: "Později", subtitle: nil, tasks: later))
            }

            return sections
        }
    }
}

import SwiftUI

/// Detail jedné hodiny z rozvrhu: kdo, kde, kdy — a co k ní mám za úkoly.
///
/// Tohle je hlavní místo, kde se úkol nebo test zakládá: student vidí hodinu,
/// na kterou se záznam váže, a nemusí datum ani hodinu vybírat ručně.
struct LessonDetailSheet: View {
    let spot: LessonSpot
    let periods: [LessonPeriod]
    let date: Date
    var preferredGroup: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(StudyTaskStore.self) private var store

    @State private var newTaskKind: StudyTaskKind?
    @State private var editedTask: StudyTask?

    private var lessons: [Lesson] {
        guard let preferredGroup else { return spot.lessons }
        return spot.lessons.sorted { lhs, _ in lhs.group == preferredGroup }
    }

    private var primaryLesson: Lesson? { lessons.first }

    private var tasks: [StudyTask] {
        store.tasks(on: date, periodRange: spot.periodRange)
    }

    private var timeRange: String {
        guard let first = periods.first(where: { $0.number == spot.periodRange.lowerBound }),
              let last = periods.first(where: { $0.number == spot.periodRange.upperBound }) else { return "" }
        return "\(first.from.formatted) – \(last.to.formatted)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        if lessons.count > 1 { groupsSection }
                        tasksSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .navigationTitle(primaryLesson?.subject.abbreviation ?? "Hodina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .sheet(item: $newTaskKind) { kind in
                TaskEditorView(
                    newTaskFor: primaryLesson,
                    periodNumber: spot.periodRange.lowerBound,
                    date: date,
                    kind: kind
                )
            }
            .sheet(item: $editedTask) { task in
                TaskEditorView(task: task, isNew: false)
            }
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        GlassCard(tint: Theme.accent) {
            HStack(alignment: .top, spacing: 14) {
                if let primaryLesson {
                    SubjectMonogram(name: primaryLesson.subject, size: 52)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(primaryLesson?.subject.full ?? "Hodina")
                        .font(.title3.weight(.bold))
                        .lineLimit(2)

                    Label(timeRange, systemImage: "clock")
                    Label(periodLabel, systemImage: "calendar")

                    if let classroom = primaryLesson?.classroom {
                        Label(classroom, systemImage: "mappin.and.ellipse")
                    }
                    if let teacher = primaryLesson?.teacher {
                        Label(teacher.full, systemImage: "person")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        }
    }

    private var periodLabel: String {
        let range = spot.periodRange
        return range.count > 1
            ? "\(range.lowerBound).–\(range.upperBound). hodina • \(DateFormatter.jecnaWeekdayLong.string(from: date))"
            : "\(range.lowerBound). hodina • \(DateFormatter.jecnaWeekdayLong.string(from: date))"
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Skupiny")
            ContentCard {
                VStack(spacing: 0) {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        if index > 0 { Divider().padding(.leading, 14) }
                        HStack(spacing: 10) {
                            Text(lesson.group ?? "—")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(index == 0 ? Theme.accent : .secondary)
                                .frame(width: 36, alignment: .leading)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(lesson.teacher?.full ?? "—")
                                    .font(.subheadline)
                                Text(lesson.classroom ?? "—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == 0 {
                                Text("tvoje skupina")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    // MARK: - Úkoly

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Úkoly a testy", subtitle: tasks.isEmpty ? nil : "\(tasks.count) k této hodině")

            if tasks.isEmpty {
                ContentCard {
                    Text("K téhle hodině zatím nic nemáš.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            } else {
                ContentCard {
                    VStack(spacing: 0) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 { Divider().padding(.leading, 62) }
                            Button {
                                editedTask = task
                            } label: {
                                TaskRow(task: task, showsDueDate: false) {
                                    withAnimation(.smooth) { store.toggleDone(task) }
                                    Haptics.impact(.soft)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    newTaskKind = .homework
                } label: {
                    Label("Přidat úkol", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)

                Button {
                    newTaskKind = .test
                } label: {
                    Label("Přidat test", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 4)
        }
    }
}

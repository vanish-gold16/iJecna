import SwiftUI

/// Odznak druhu záznamu — ikona v barevném čtverečku.
struct TaskKindBadge: View {
    let kind: StudyTaskKind
    var size: CGFloat = 32
    var isDone: Bool = false

    var body: some View {
        Image(systemName: isDone ? "checkmark" : kind.symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                (isDone ? AnyShapeStyle(Color.secondary.gradient)
                        : AnyShapeStyle(Theme.taskColor(for: kind).gradient)),
                in: .rect(cornerRadius: size * 0.3, style: .continuous)
            )
    }
}

/// Řádek se záznamem. Zaškrtávátko je samostatné tlačítko, aby zbytek řádku
/// mohl otevřít úpravu.
struct TaskRow: View {
    let task: StudyTask
    var showsDueDate: Bool = true
    var onToggle: () -> Void

    private var isOverdue: Bool { task.isOverdue() }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Theme.taskColor(for: task.kind) : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Označit jako nesplněné" : "Označit jako splněné")

            TaskKindBadge(kind: task.kind, size: 30, isDone: task.isDone)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(task.displaySubject)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.taskColor(for: task.kind))

                    if let period = task.periodNumber {
                        Text("• \(period). hodina")
                    }

                    if showsDueDate {
                        Text("• \(task.dueDescription())")
                            .foregroundStyle(isOverdue && !task.isDone ? .red : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if task.hasPendingReminder {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Upozornění nastaveno")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}

/// Malý ukazatel u hodiny v rozvrhu — kolik má navázaných úkolů a testů.
struct LessonTaskIndicator: View {
    let tasks: [StudyTask]

    private var openTasks: [StudyTask] { tasks.filter { !$0.isDone } }
    private var hasTest: Bool { openTasks.contains { $0.kind == .test } }

    var body: some View {
        if !openTasks.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: hasTest ? "exclamationmark.triangle.fill" : "pencil.and.list.clipboard")
                    .font(.system(size: 9, weight: .semibold))
                if openTasks.count > 1 {
                    Text("\(openTasks.count)")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                (hasTest ? Color.orange : Theme.accent).gradient,
                in: .capsule
            )
            .accessibilityLabel(
                hasTest ? "Test a \(openTasks.count) úkolů" : "\(openTasks.count) úkolů"
            )
        }
    }
}

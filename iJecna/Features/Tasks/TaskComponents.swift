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

// MARK: - Značky po dnech

/// Barevné tečky za to, co na den připadá — test oranžově, úkol modře,
/// projekt fialově. Stačí koutkem oka, aby bylo jasné, kde je test.
struct TaskDayDots: View {
    let summary: DayTaskSummary
    /// Na vybraném dni s modrým podkladem by modrá a šedá tečka zanikly —
    /// ty jsou bílé, test a projekt si barvu nechají a dostanou bílý lem.
    var onAccent = false
    /// Prázdný den ukáže nenápadné plus — klepnutím se na něj přidá záznam.
    var showsAddHint = false

    var body: some View {
        HStack(spacing: 3) {
            if summary.isEmpty && showsAddHint {
                Image(systemName: "plus")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.quaternary)
            }
            ForEach(summary.kinds.prefix(3)) { kind in
                let blendsIn = onAccent && (kind == .homework || kind == .note)
                Circle()
                    .fill(blendsIn ? Color.white : Theme.taskColor(for: kind))
                    .frame(width: 6, height: 6)
                    .overlay {
                        if onAccent && !blendsIn { Circle().strokeBorder(.white, lineWidth: 1) }
                    }
            }
        }
        // Výška zůstává, i když je den prázdný — dny v řadě pak neposkakují.
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(summary.isEmpty ? "" : summary.description)
    }
}

/// Souhrn dne po druzích: „1 test“, „2 úkoly“. Když se nevejde, zkrátí se
/// na ikonu a číslo.
struct TaskSummaryChips: View {
    let summary: DayTaskSummary

    var body: some View {
        if !summary.isEmpty {
            ViewThatFits(in: .horizontal) {
                chips(compact: false)
                chips(compact: true)
            }
            .accessibilityElement()
            .accessibilityLabel(summary.description)
        }
    }

    private func chips(compact: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(summary.kinds) { kind in
                let count = summary.count(of: kind)
                HStack(spacing: 3) {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 9, weight: .bold))
                    Text(compact ? "\(count)" : kind.countLabel(count))
                        .font(.caption2.weight(.semibold))
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.taskColor(for: kind))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Theme.taskColor(for: kind).opacity(0.15), in: .capsule)
            }
        }
    }
}

/// Malá značka do rohu buňky v týdenní mřížce. Test má přednost —
/// je to jediné, co se nevyplatí přehlédnout.
struct TaskCornerMark: View {
    let tasks: [StudyTask]

    private var summary: DayTaskSummary { DayTaskSummary(tasks: tasks) }

    var body: some View {
        if let kind = summary.kinds.first {
            Image(systemName: kind == .test ? "exclamationmark" : kind.symbolName)
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(Theme.taskColor(for: kind).gradient, in: .circle)
                .overlay(alignment: .topTrailing) {
                    if summary.total > 1 {
                        Text("\(summary.total)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Color.black.opacity(0.55), in: .circle)
                            .offset(x: 5, y: -5)
                    }
                }
                .accessibilityLabel(summary.description)
        }
    }
}

/// Dva týdny dopředu po dnech. Tečky ukazují, kdy co je — test za týden
/// je vidět stejně dobře jako úkol na zítra.
struct TaskCalendarStrip: View {
    var dayCount = 14
    /// Co se pro den počítá — filtr „Testy“ ukazuje jen testy.
    let summary: (Date) -> DayTaskSummary
    var onSelect: (Date) -> Void

    private var days: [Date] {
        let today = Date.startOfSchoolDay()
        return (0..<dayCount).compactMap { Calendar.prague.date(byAdding: .day, value: $0, to: today) }
    }

    /// Druhy, které se ve zobrazených dnech vyskytují — jen ty má smysl vysvětlit.
    private var presentKinds: [StudyTaskKind] {
        let all = Set(days.flatMap { summary($0).kinds })
        return StudyTaskKind.byImportance.filter(all.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        // Předěl mezi týdny, ať se „Po“ nepletou.
                        if index > 0, Calendar.prague.component(.weekday, from: day) == 2 {
                            Capsule()
                                .fill(.quaternary)
                                .frame(width: 2, height: 36)
                                .padding(.horizontal, 3)
                        }
                        dayCell(day)
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)

            if !presentKinds.isEmpty {
                legend.padding(.horizontal, 22)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let summary = summary(day)
        let isToday = day == Date.startOfSchoolDay()
        let isWeekend = Calendar.prague.isDateInWeekend(day)

        return Button {
            onSelect(day)
            Haptics.selection()
        } label: {
            VStack(spacing: 4) {
                Text(day.shortWeekdayName())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                Text("\(Calendar.prague.component(.day, from: day))")
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                TaskDayDots(summary: summary, onAccent: isToday, showsAddHint: !isWeekend)
            }
            .frame(width: 44, height: 64)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                if isToday {
                    shape.fill(Theme.accent.gradient)
                } else if summary.hasTest {
                    // Den s testem je podbarvený, i když je až za týden.
                    shape.fill(Color.orange.opacity(0.14))
                    shape.strokeBorder(Color.orange.opacity(0.45), lineWidth: 1)
                } else {
                    shape.fill(.background.secondary)
                }
            }
            .opacity(isWeekend && summary.isEmpty ? 0.45 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DateFormatter.jecnaWeekdayLong.string(from: day)), \(summary.description)")
        .accessibilityHint(summary.isEmpty ? "Přidá nový záznam na tento den" : "Přejde na záznamy tohoto dne")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(presentKinds) { kind in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.taskColor(for: kind))
                        .frame(width: 6, height: 6)
                    Text(kind.title.lowercased())
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

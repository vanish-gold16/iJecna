import SwiftUI

/// Založení nebo úprava úkolu, testu či poznámky.
///
/// Předmět i hodinu nabízí z rozvrhu, ale nevynucuje je — úkol může vzniknout
/// i na den, kdy se předmět neučí, nebo pro předmět, který v rozvrhu není.
struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyTaskStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var draft: StudyTask
    @State private var showsDeleteConfirmation = false
    @FocusState private var isTitleFocused: Bool

    private let isNew: Bool

    init(task: StudyTask, isNew: Bool) {
        _draft = State(initialValue: task)
        self.isNew = isNew
    }

    /// Nový záznam předvyplněný podle hodiny v rozvrhu.
    init(newTaskFor lesson: Lesson?, periodNumber: Int?, date: Date, kind: StudyTaskKind = .homework) {
        let task = StudyTask(
            kind: kind,
            subjectName: lesson?.subject.full ?? "",
            subjectShort: lesson?.subject.short,
            dueDate: Date.startOfSchoolDay(date),
            periodNumber: periodNumber,
            reminderPreset: kind.defaultReminder
        )
        _draft = State(initialValue: task)
        self.isNew = true
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.subjectName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                contentSection
                scheduleSection
                reminderSection

                if !isNew {
                    Section {
                        Button("Smazat", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Nový záznam" : "Upravit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit", action: save)
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Smazat záznam?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Smazat", role: .destructive) {
                    store.delete(draft)
                    dismiss()
                }
                Button("Zrušit", role: .cancel) {}
            }
            .onAppear {
                if isNew && draft.title.isEmpty {
                    isTitleFocused = true
                }
            }
        }
    }

    // MARK: - Sekce

    private var kindSection: some View {
        Section {
            Picker("Druh", selection: $draft.kind) {
                ForEach(StudyTaskKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbolName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: draft.kind) { _, newValue in
                // Test si zaslouží dřívější upozornění než domácí úkol.
                if isNew { draft.reminderPreset = newValue.defaultReminder }
            }
        }
    }

    private var contentSection: some View {
        Section("Zadání") {
            TextField("Co je potřeba udělat", text: $draft.title, axis: .vertical)
                .lineLimit(1...3)
                .focused($isTitleFocused)

            TextField("Podrobnosti (nepovinné)", text: $draft.details, axis: .vertical)
                .lineLimit(1...6)
        }
    }

    private var scheduleSection: some View {
        Section {
            DatePicker(
                "Termín",
                selection: Binding(
                    get: { draft.dueDate },
                    set: { draft.dueDate = Date.startOfSchoolDay($0) }
                ),
                displayedComponents: .date
            )

            Picker("Hodina", selection: $draft.periodNumber) {
                Text("Bez konkrétní hodiny").tag(Int?.none)
                ForEach(lessonOptions) { option in
                    Text(option.label).tag(Int?.some(option.periodNumber))
                }
            }
            .onChange(of: draft.periodNumber) { _, newValue in
                // Výběr hodiny rovnou doplní předmět — nejčastější případ použití.
                guard let newValue, let option = lessonOptions.first(where: { $0.periodNumber == newValue }) else { return }
                draft.subjectName = option.subject.full
                draft.subjectShort = option.subject.short
            }

            subjectPicker
        } header: {
            Text("Zařazení")
        } footer: {
            if lessonOptions.isEmpty {
                Text("Na vybraný den nemáš v rozvrhu žádnou výuku, hodinu proto nelze zvolit.")
            }
        }
    }

    private var subjectPicker: some View {
        HStack {
            Text("Předmět")
            Spacer()
            Menu {
                ForEach(subjectSuggestions, id: \.full) { subject in
                    Button(subject.full) {
                        draft.subjectName = subject.full
                        draft.subjectShort = subject.short
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(draft.subjectName.isEmpty ? "Vybrat" : draft.subjectName)
                        .foregroundStyle(draft.subjectName.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            Picker("Upozornit", selection: $draft.reminderPreset) {
                ForEach(ReminderPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            if draft.reminderPreset == .custom {
                DatePicker(
                    "Čas upozornění",
                    selection: Binding(
                        get: { draft.reminderDate ?? defaultCustomReminder },
                        set: { draft.reminderDate = $0 }
                    )
                )
            } else if let preview = previewReminderDate {
                LabeledContent("Upozorní") {
                    Text(preview, format: .dateTime.day().month().hour().minute())
                        .foregroundStyle(preview > .now ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                }
            }
        } header: {
            Text("Upozornění")
        } footer: {
            if let preview = previewReminderDate, preview <= .now {
                Text("Zvolený čas už uplynul, upozornění se nenaplánuje.")
            } else {
                Text("Upozornění vzniká na tomhle zařízení. Funguje i offline, protože čas je známý dopředu.")
            }
        }
    }

    // MARK: - Nabídky

    private struct LessonOption: Identifiable, Hashable {
        let periodNumber: Int
        let subject: DisplayName
        let start: TimeOfDay

        var id: Int { periodNumber }
        var label: String { "\(periodNumber). • \(subject.abbreviation) • \(start.formatted)" }
    }

    /// Hodiny z rozvrhu pro zvolený den. U dělených hodin bereme skupinu studenta.
    private var lessonOptions: [LessonOption] {
        guard let page = model.timetable.value,
              let weekday = Weekday.from(calendarWeekday: Calendar.prague.component(.weekday, from: draft.dueDate)),
              let day = page.timetable.day(weekday) else { return [] }

        let group = model.profile.value?.primaryGroup

        return day.lessonSpots.compactMap { spot in
            guard let lesson = spot.lesson(preferringGroup: group),
                  let period = page.timetable.period(number: spot.periodRange.lowerBound) else { return nil }
            return LessonOption(periodNumber: period.number, subject: lesson.subject, start: period.from)
        }
    }

    /// Předměty z rozvrhu i ze známek — úkol může být i z předmětu, který dnes není.
    private var subjectSuggestions: [DisplayName] {
        var seen = Set<String>()
        var result: [DisplayName] = []

        for option in lessonOptions where seen.insert(option.subject.full).inserted {
            result.append(option.subject)
        }
        for subject in model.grades.value?.subjects ?? [] where seen.insert(subject.name.full).inserted {
            result.append(subject.name)
        }
        return result.sorted { $0.full.localizedStandardCompare($1.full) == .orderedAscending }
    }

    private var previewReminderDate: Date? {
        let lessonStart = draft.periodNumber.flatMap { number in
            lessonOptions.first { $0.periodNumber == number }?.start
        }
        return draft.reminderPreset.reminderDate(forDueDate: draft.dueDate, lessonStart: lessonStart)
    }

    private var defaultCustomReminder: Date {
        Calendar.prague.date(bySettingHour: 18, minute: 0, second: 0, of: draft.dueDate) ?? draft.dueDate
    }

    // MARK: - Uložení

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)

        if isNew {
            store.add(draft)
        } else {
            store.update(draft)
        }
        Haptics.notify(.success)
        dismiss()
    }
}

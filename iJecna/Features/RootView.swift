import SwiftUI

enum AppTab: Hashable {
    case today, grades, timetable, more

    /// Umožňuje spustit aplikaci rovnou na dané záložce:
    /// `SIMCTL_CHILD_INITIAL_TAB=grades xcrun simctl launch booted …`
    /// Slouží k pořizování snímků obrazovek, v běžném provozu se neuplatní.
    static var launchDefault: AppTab {
        switch ProcessInfo.processInfo.environment["INITIAL_TAB"] {
        case "grades": .grades
        case "timetable": .timetable
        case "more": .more
        default: .today
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.session.isSignedIn {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: model.session)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .launchDefault

    var body: some View {
        @Bindable var model = model

        TabView(selection: $selection) {
            Tab("Dnes", systemImage: "sun.horizon", value: AppTab.today) {
                DashboardView(selection: $selection)
            }

            Tab("Známky", systemImage: "chart.bar.doc.horizontal", value: AppTab.grades) {
                GradesView()
            }
            .badge(model.newGrades.unseenCount)

            Tab("Rozvrh", systemImage: "calendar", value: AppTab.timetable) {
                TimetableView()
            }

            Tab("Více", systemImage: "square.grid.2x2", value: AppTab.more) {
                MoreView()
            }
        }
        // Tab bar se na scrollu smrskne a nechá obsah vyniknout — chování iOS 26.
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NextLessonAccessory()
        }
        .onChange(of: selection) { _, newValue in
            Haptics.selection()
            if newValue == .grades {
                // Otevření záložky se známkami je potvrzení, že je uživatel viděl.
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    model.newGrades.markAllSeen()
                }
            }
        }
    }
}

/// Pruh nad tab barem s aktuální nebo nejbližší hodinou.
/// Ve zmenšeném stavu ukazuje jen zkratku a učebnu.
struct NextLessonAccessory: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let moment = model.currentMoment, let lesson = moment.lesson {
            switch placement {
            case .inline:
                inlineContent(moment: moment, lesson: lesson)
            default:
                expandedContent(moment: moment, lesson: lesson)
            }
        } else {
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyText: String {
        switch model.currentMoment?.kind {
        case .weekend: "Víkend — žádná výuka"
        case .dayFinished: "Dnes už máš odučeno"
        default: "Rozvrh se načítá…"
        }
    }

    private func inlineContent(moment: LessonMoment, lesson: Lesson) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(for: moment.kind))
                .font(.caption)
                .foregroundStyle(Theme.accent)
            Text(lesson.subject.abbreviation)
                .font(.subheadline.weight(.semibold))
            if let classroom = lesson.classroom {
                Text(classroom)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func expandedContent(moment: LessonMoment, lesson: Lesson) -> some View {
        HStack(spacing: 12) {
            SubjectMonogram(name: lesson.subject, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.subject.full)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(statusText(moment))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if case .ongoing(let progress) = moment.kind {
                LessonProgressRing(progress: progress)
                    .frame(width: 22, height: 22)
            } else if let classroom = lesson.classroom {
                Text(classroom)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 12)
    }

    private func symbol(for kind: LessonMoment.Kind) -> String {
        switch kind {
        case .ongoing: "play.circle.fill"
        case .intermission: "pause.circle"
        case .upcoming, .freePeriod: "clock"
        case .dayFinished: "checkmark.circle"
        case .weekend: "sun.max"
        }
    }

    private func statusText(_ moment: LessonMoment) -> String {
        let room = moment.lesson?.classroom
        let separator = " • "
        switch moment.kind {
        case .ongoing:
            let end = moment.endPeriod?.to.formatted ?? ""
            return ["Probíhá", room, "do \(end)"].compactMap { $0 }.joined(separator: separator)
        case .intermission(let minutes):
            // Bez učebny — do zúženého pruhu se delší text nevejde.
            return "Přestávka" + separator + "pokračuje za \(minutes) min"
        case .upcoming(let minutes):
            let start = moment.startPeriod?.from.formatted ?? ""
            return ["Za \(minutes) min", room, start].compactMap { $0 }.joined(separator: separator)
        case .freePeriod(let minutes):
            return "Volná hodina" + separator + "další za \(minutes) min"
        case .dayFinished:
            return "Konec vyučování"
        case .weekend:
            return "Víkend"
        }
    }
}

import SwiftUI

struct TeachersView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle("Učitelé")
        .searchable(text: $query, prompt: "Jméno nebo zkratka")
        .task { await model.loadTeachers() }
    }

    private func filtered(_ teachers: [TeacherRef]) -> [TeacherRef] {
        let sorted = teachers.sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.fullName.localizedCaseInsensitiveContains(query) || $0.tag.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.teachers {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.loadTeachers(force: true) } }
        case .loaded(let teachers, _):
            let results = filtered(teachers)
            if results.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "Nic nenalezeno", message: "Zkus jiné jméno nebo zkratku.")
            } else {
                ScrollView {
                    ContentCard {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, teacher in
                                if index > 0 { Divider().padding(.leading, 62) }
                                NavigationLink {
                                    TeacherDetailView(reference: teacher)
                                } label: {
                                    TeacherRow(teacher: teacher)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
    }
}

struct TeacherRow: View {
    let teacher: TeacherRef

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.indigo.gradient)
                .frame(width: 38, height: 38)
                .overlay {
                    Text(teacher.initials)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(teacher.fullName)
                    .font(.subheadline)
                Text(teacher.tag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

struct TeacherDetailView: View {
    let reference: TeacherRef
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<Teacher> = .idle

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    switch state {
                    case .idle, .loading:
                        ProgressView().padding(.top, 40)
                    case .failed(let error):
                        ErrorStateView(error: error) { Task { await load(force: true) } }
                    case .loaded(let teacher, _):
                        details(teacher)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle(reference.tag)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        GlassCard(tint: .indigo) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.indigo.gradient)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Text(reference.initials)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(reference.fullName)
                        .font(.headline)
                    if let tutorClass = state.value?.tutorOfClass {
                        Label("Třídní \(tutorClass)", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func details(_ teacher: Teacher) -> some View {
        ContentCard {
            VStack(spacing: 0) {
                InfoRow(label: "Školní e-mail", value: teacher.schoolMail, symbol: "envelope", link: .mail(teacher.schoolMail))
                ForEach(teacher.phoneNumbers, id: \.self) { phone in
                    Divider().padding(.leading, 52)
                    InfoRow(label: "Telefon", value: phone, symbol: "phone", link: .phone(phone))
                }
                if let cabinet = teacher.cabinet {
                    Divider().padding(.leading, 52)
                    InfoRow(label: "Kabinet", value: cabinet, symbol: "door.left.hand.closed")
                }
                if let hours = teacher.consultationHours {
                    Divider().padding(.leading, 52)
                    InfoRow(label: "Konzultační hodiny", value: hours, symbol: "clock")
                }
            }
        }
    }

    private func load(force: Bool = false) async {
        guard force || state.isIdle else { return }
        state = .loading
        do {
            state = .loaded(try await model.service.teacher(tag: reference.tag))
        } catch let error as JecnaError {
            state = .failed(error)
        } catch {
            state = .failed(.network(error.localizedDescription))
        }
    }
}

/// Řádek „popisek → hodnota“ s volitelnou akcí (mail / telefon).
struct InfoRow: View {
    enum Link {
        case mail(String), phone(String)

        var url: URL? {
            switch self {
            case .mail(let address): URL(string: "mailto:\(address)")
            case .phone(let number): URL(string: "tel:\(number.filter { $0.isNumber || $0 == "+" })")
            }
        }
    }

    let label: String
    let value: String
    var symbol: String
    var link: Link?

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if let link, let url = link.url {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Učebny

struct RoomsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle("Učebny")
        .searchable(text: $query, prompt: "Číslo nebo název")
        .task { await model.loadRooms() }
    }

    private func grouped(_ rooms: [Room]) -> [(floor: String, rooms: [Room])] {
        let filtered = query.isEmpty ? rooms : rooms.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.roomCode.localizedCaseInsensitiveContains(query)
        }
        let groups = Dictionary(grouping: filtered) { $0.floor ?? "Ostatní" }
        return groups
            .map { (floor: $0.key, rooms: $0.value.sorted { $0.roomCode < $1.roomCode }) }
            .sorted { $0.floor.localizedStandardCompare($1.floor) == .orderedAscending }
    }

    @ViewBuilder
    private var content: some View {
        switch model.rooms {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.loadRooms(force: true) } }
        case .loaded(let rooms, _):
            let sections = grouped(rooms)
            if sections.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "Nic nenalezeno")
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(sections, id: \.floor) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(section.floor)
                                ContentCard {
                                    VStack(spacing: 0) {
                                        ForEach(Array(section.rooms.enumerated()), id: \.element.id) { index, room in
                                            if index > 0 { Divider().padding(.leading, 62) }
                                            RoomRow(room: room)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
    }
}

struct RoomRow: View {
    let room: Room

    var body: some View {
        HStack(spacing: 12) {
            Text(room.roomCode)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 38, height: 38)
                .background(Color.teal.gradient, in: .rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(room.name)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let homeroom = room.homeroomOf {
                        Text("kmenová \(homeroom)")
                    }
                    if let manager = room.manager {
                        Text("• \(manager.tag)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

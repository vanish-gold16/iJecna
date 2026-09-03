import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        profileCard

                        ForEach(MoreSection.all) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(section.title)
                                ContentCard {
                                    VStack(spacing: 0) {
                                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                            if index > 0 {
                                                Divider().padding(.leading, 56)
                                            }
                                            MoreRow(item: item, badge: badge(for: item))
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
            .navigationTitle("Více")
            .task {
                await model.loadProfile()
                await model.loadNotifications()
            }
        }
    }

    // MARK: - Profil

    private var profileCard: some View {
        NavigationLink {
            ProfileView()
        } label: {
            GlassCard(tint: Theme.accent) {
                HStack(spacing: 14) {
                    avatar

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.profile.value?.fullName ?? "Načítám…")
                            .font(.headline)
                            .redacted(reason: model.profile.value == nil ? .placeholder : [])
                        if let student = model.profile.value {
                            Text([student.className, student.classGroups]
                                .compactMap { $0 }
                                .joined(separator: " • "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(student.schoolMail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.accent.gradient)
            .frame(width: 54, height: 54)
            .overlay {
                Text(model.profile.value?.initials ?? "—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
    }

    private func badge(for item: MoreItem) -> Int? {
        item == .notifications ? model.notifications.value?.count : nil
    }
}

// MARK: - Struktura nabídky

/// Položky rozcestníku. Datový popis místo ručně skládaných řádků,
/// aby oddělovač nevyčníval pod poslední položkou karty.
enum MoreItem: String, Identifiable, CaseIterable {
    case news, teachers, rooms, profile, locker, notifications, settings, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .news: "Aktuality"
        case .teachers: "Učitelé"
        case .rooms: "Učebny"
        case .profile: "Profil studenta"
        case .locker: "Skříňka"
        case .notifications: "Poznámky a pochvaly"
        case .settings: "Nastavení"
        case .about: "O aplikaci"
        }
    }

    var symbol: String {
        switch self {
        case .news: "newspaper"
        case .teachers: "person.2"
        case .rooms: "door.left.hand.open"
        case .profile: "person.text.rectangle"
        case .locker: "lock.square"
        case .notifications: "bell.badge"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .news: .orange
        case .teachers: .indigo
        case .rooms: .teal
        case .profile: Theme.accent
        case .locker: .brown
        case .notifications: .pink
        case .settings, .about: .gray
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .news: NewsView()
        case .teachers: TeachersView()
        case .rooms: RoomsView()
        case .profile: ProfileView()
        case .locker: LockerView()
        case .notifications: NotificationsView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }
}

struct MoreSection: Identifiable {
    let title: String
    let items: [MoreItem]

    var id: String { title }

    static let all: [MoreSection] = [
        MoreSection(title: "Škola", items: [.news, .teachers, .rooms]),
        MoreSection(title: "Já", items: [.profile, .locker, .notifications]),
        MoreSection(title: "Aplikace", items: [.settings, .about]),
    ]
}

struct MoreRow: View {
    let item: MoreItem
    var badge: Int?

    var body: some View {
        NavigationLink {
            item.destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(item.tint.gradient, in: .rect(cornerRadius: 8, style: .continuous))

                Text(item.title)
                    .font(.subheadline)

                Spacer()

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

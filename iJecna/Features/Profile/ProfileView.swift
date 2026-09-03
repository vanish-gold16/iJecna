import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadProfile() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.profile {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.loadProfile(force: true) } }
        case .loaded(let student, _):
            ScrollView {
                VStack(spacing: 18) {
                    header(student)
                    basics(student)
                    if !student.guardians.isEmpty {
                        guardians(student)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private func header(_ student: Student) -> some View {
        GlassCard(tint: Theme.accent) {
            VStack(spacing: 12) {
                Circle()
                    .fill(Theme.accent.gradient)
                    .frame(width: 84, height: 84)
                    .overlay {
                        Text(student.initials)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                    }

                VStack(spacing: 3) {
                    Text(student.fullName)
                        .font(.title3.weight(.semibold))
                    if let className = student.className {
                        Text(className)
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func basics(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Údaje")
            ContentCard {
                VStack(spacing: 0) {
                    InfoRow(label: "Uživatelské jméno", value: student.username, symbol: "person")
                    Divider().padding(.leading, 52)
                    InfoRow(label: "Školní e-mail", value: student.schoolMail, symbol: "envelope", link: .mail(student.schoolMail))
                    if let groups = student.classGroups {
                        Divider().padding(.leading, 52)
                        InfoRow(label: "Skupiny", value: groups, symbol: "person.2")
                    }
                    if let birthDate = student.birthDate {
                        Divider().padding(.leading, 52)
                        InfoRow(
                            label: "Datum narození",
                            value: DateFormatter.jecnaShortDate.string(from: birthDate),
                            symbol: "birthday.cake"
                        )
                    }
                    if let address = student.permanentAddress {
                        Divider().padding(.leading, 52)
                        InfoRow(label: "Trvalé bydliště", value: address, symbol: "house")
                    }
                }
            }
        }
    }

    private func guardians(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Zákonní zástupci")
            ContentCard {
                VStack(spacing: 0) {
                    ForEach(Array(student.guardians.enumerated()), id: \.element.id) { index, guardian in
                        if index > 0 { Divider().padding(.leading, 14) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(guardian.name)
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 14) {
                                if let phone = guardian.phoneNumber {
                                    Label(phone, systemImage: "phone")
                                }
                                if let email = guardian.email {
                                    Label(email, systemImage: "envelope")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                }
            }
        }
    }
}

struct LockerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 18) {
                    switch model.locker {
                    case .idle, .loading:
                        ProgressView().padding(.top, 60)
                    case .failed(let error):
                        ErrorStateView(error: error) { Task { await model.loadLocker(force: true) } }
                    case .loaded(let locker, _):
                        if let locker {
                            GlassCard(tint: .brown) {
                                VStack(spacing: 10) {
                                    Text(locker.number)
                                        .font(.system(size: 56, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.brown)
                                    Text("číslo skříňky")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            ContentCard {
                                VStack(spacing: 0) {
                                    InfoRow(label: "Umístění", value: locker.location, symbol: "mappin.and.ellipse")
                                    if let from = locker.assignedFrom {
                                        Divider().padding(.leading, 52)
                                        InfoRow(
                                            label: "Přiděleno od",
                                            value: DateFormatter.jecnaShortDate.string(from: from),
                                            symbol: "calendar"
                                        )
                                    }
                                }
                            }
                        } else {
                            EmptyStateView(
                                symbol: "lock.open",
                                title: "Bez skříňky",
                                message: "Nemáš přidělenou žádnou školní skříňku."
                            )
                            .padding(.top, 60)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle("Skříňka")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadLocker() }
    }
}

struct NotificationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle("Poznámky a pochvaly")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadNotifications() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.notifications {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.loadNotifications(force: true) } }
        case .loaded(let items, _):
            if items.isEmpty {
                EmptyStateView(
                    symbol: "checkmark.seal",
                    title: "Žádné záznamy",
                    message: "Nemáš žádné poznámky ani pochvaly."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            NotificationCard(notification: item)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .refreshable { await model.loadNotifications(force: true) }
            }
        }
    }
}

struct NotificationCard: View {
    let notification: SchoolNotification

    private var tint: Color {
        switch notification.kind {
        case .good: .green
        case .bad: .orange
        case .info: .blue
        }
    }

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: notification.kind.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(tint.gradient, in: .circle)

                    Text(notification.exactType)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text(DateFormatter.jecnaDayMonth.string(from: notification.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let issuer = notification.issuedBy {
                    Label(issuer.fullName, systemImage: "person")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
        }
    }
}

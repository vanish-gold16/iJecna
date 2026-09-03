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
        let fields = displayFields(for: student)

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Údaje")
            ContentCard {
                VStack(spacing: 0) {
                    ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                        if index > 0 { Divider().padding(.leading, 52) }
                        InfoRow(
                            label: field.label,
                            value: field.value,
                            symbol: field.symbolName,
                            link: link(for: field)
                        )
                    }
                }
            }
        }
    }

    /// Přednostně se vypisuje celá tabulka tak, jak ji web uvádí — jinak by
    /// se ztratilo všechno, co jsme nepojmenovali dopředu. Když tabulka chybí
    /// (třeba na maketě), poskládá se seznam z toho, co o studentovi víme.
    private func displayFields(for student: Student) -> [ProfileField] {
        guard student.details.isEmpty else { return student.details }

        var fields: [ProfileField] = [
            ProfileField(label: "Uživatelské jméno", value: student.username)
        ]
        if !student.schoolMail.isEmpty {
            fields.append(ProfileField(label: "E-mail", value: student.schoolMail, link: "mailto:\(student.schoolMail)"))
        }
        if let className = student.className {
            fields.append(ProfileField(label: "Třída", value: className))
        }
        if let groups = student.classGroups {
            fields.append(ProfileField(label: "Skupiny", value: groups))
        }
        if let birthDate = student.birthDate {
            fields.append(ProfileField(
                label: "Datum narození",
                value: DateFormatter.jecnaShortDate.string(from: birthDate)
            ))
        }
        if let address = student.permanentAddress {
            fields.append(ProfileField(label: "Trvalé bydliště", value: address))
        }
        return fields
    }

    private func link(for field: ProfileField) -> InfoRow.Link? {
        if let link = field.link, link.hasPrefix("mailto:") {
            return .mail(String(link.dropFirst("mailto:".count)))
        }
        if let link = field.link, link.hasPrefix("tel:") {
            return .phone(String(link.dropFirst("tel:".count)))
        }
        // Web u telefonu odkaz neuvádí, poznáme ho podle popisku.
        if field.label.localizedCaseInsensitiveContains("telefon") {
            return .phone(field.value)
        }
        if field.value.contains("@"), field.value.contains(".") {
            return .mail(field.value)
        }
        return nil
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

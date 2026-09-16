import Foundation

/// Hlídá, jestli ve škole nepřibylo něco nového, a hlásí to upozorněním.
///
/// Tohle je jediné místo, kde se rozhoduje, co je „nové“. Ječna nic takového
/// nenabízí — porovnává se s tím, co jsme viděli naposledy.
///
/// Kontrola běží buď na pozadí (`BGAppRefreshTask`), nebo při otevření aplikace.
/// Na pozadí má systém tvrdý časový strop kolem třiceti sekund, takže se stahuje
/// jen to nejnutnější a v pořadí podle důležitosti.
@MainActor
final class SchoolWatcher {

    /// Co kontrola našla.
    struct Findings: Sendable {
        var newGrades: [GradeFinding] = []
        var newNotifications: [SchoolNotification] = []
        var substitutionsChanged = false

        var isEmpty: Bool {
            newGrades.isEmpty && newNotifications.isEmpty && !substitutionsChanged
        }
    }

    struct GradeFinding: Sendable {
        let subject: DisplayName
        let grade: Grade
    }

    private let service: JecnaService
    private let tracker: NewGradesTracker
    private let settings: AppSettings
    private let scheduler: NotificationScheduler
    private let defaults: UserDefaults

    init(
        service: JecnaService,
        tracker: NewGradesTracker,
        settings: AppSettings,
        scheduler: NotificationScheduler,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.tracker = tracker
        self.settings = settings
        self.scheduler = scheduler
        self.defaults = defaults
    }

    // MARK: - Kontrola

    /// Projde, co je zapnuté, a vrátí nálezy. Upozornění rozešle sama.
    @discardableResult
    func check() async -> Findings {
        guard await service.signedInUsername() != nil else { return Findings() }

        var findings = Findings()

        if settings.notifyOnNewGrade {
            findings.newGrades = await checkGrades()
        }
        if settings.notifyOnNewNotification {
            findings.newNotifications = await checkNotifications()
        }
        if settings.notifyOnTimetableChange, settings.substitutionsEnabled {
            findings.substitutionsChanged = await checkSubstitutions()
        }

        await announce(findings)
        return findings
    }

    // MARK: - Známky

    private func checkGrades() async -> [GradeFinding] {
        guard let page = try? await service.grades(year: .current, half: .current) else { return [] }

        let fresh = tracker.register(page)
        guard !fresh.isEmpty else { return [] }

        // Známka sama o sobě neví, ke kterému předmětu patří.
        let ids = Set(fresh.map(\.id))
        return page.subjects.flatMap { subject in
            subject.allGrades
                .filter { ids.contains($0.id) }
                .map { GradeFinding(subject: subject.name, grade: $0) }
        }
    }

    // MARK: - Sdělení rodičům

    private func checkNotifications() async -> [SchoolNotification] {
        guard let all = try? await service.notifications() else { return [] }

        let known = Set(defaults.array(forKey: Key.seenNotifications) as? [Int] ?? [])

        // První spuštění jen zapíše stav, ať nepřijde upozornění na celou historii.
        guard !known.isEmpty else {
            defaults.set(all.map(\.id), forKey: Key.seenNotifications)
            return []
        }

        let fresh = all.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return [] }

        defaults.set(Array(known.union(all.map(\.id))), forKey: Key.seenNotifications)
        return fresh
    }

    // MARK: - Mimořádný rozvrh

    private func checkSubstitutions() async -> Bool {
        let service = SubstitutionService(provider: settings.substitutionProviderURL)
        guard let className = try? await self.service.profile().className,
              let schedule = try? await service.schedule(for: className) else { return false }

        // Porovnává se otisk nejbližších dnů. Celý obsah ukládat nemusíme,
        // zajímá nás jen jestli se něco pohnulo.
        let digest = schedule.upcoming
            .map { day in
                let changes = day.changes.map { $0?.text ?? "-" }.joined(separator: ",")
                return "\(day.date.timeIntervalSince1970)|\(day.isSchoolDay)|\(changes)|\(day.note ?? "")"
            }
            .joined(separator: ";")

        let previous = defaults.string(forKey: Key.substitutionDigest)
        defaults.set(digest, forKey: Key.substitutionDigest)

        // Při prvním běhu se nic nehlásí, jen se zapamatuje výchozí stav.
        guard let previous else { return false }
        return previous != digest && !digest.isEmpty
    }

    // MARK: - Upozornění

    private func announce(_ findings: Findings) async {
        await announceGrades(findings.newGrades)

        for record in findings.newNotifications {
            await scheduler.notifyNow(
                identifier: "record-\(record.id)",
                title: record.kind.title,
                body: record.exactType,
                threadIdentifier: "records"
            )
        }

        if findings.substitutionsChanged {
            await scheduler.notifyNow(
                identifier: "substitutions-\(Int(Date.now.timeIntervalSince1970))",
                title: "Změna v rozvrhu",
                body: "Mimořádný rozvrh se změnil. Podívej se, co tě čeká.",
                threadIdentifier: "substitutions"
            )
        }
    }

    private func announceGrades(_ grades: [GradeFinding]) async {
        guard !grades.isEmpty else { return }

        if grades.count == 1, let only = grades.first {
            await scheduler.notifyNow(
                identifier: "grade-\(only.grade.id)",
                title: "Nová známka — \(only.subject.abbreviation)",
                body: Self.body(for: only),
                threadIdentifier: "grades",
                userInfo: ["gradeId": String(only.grade.id)]
            )
        } else {
            // Víc známek najednou se slučuje; pět samostatných upozornění
            // po jedné kontrole je obtěžování, ne informace.
            let summary = grades
                .prefix(4)
                .map { "\($0.subject.abbreviation) \($0.grade.label)" }
                .joined(separator: ", ")
            let rest = grades.count > 4 ? " a další" : ""

            await scheduler.notifyNow(
                identifier: "grades-\(grades.map(\.grade.id).sorted().map(String.init).joined(separator: "-").hashValue)",
                title: "\(grades.count) nových známek",
                body: summary + rest,
                threadIdentifier: "grades"
            )
        }

        tracker.markNotified(grades.map(\.grade))
    }

    static func body(for finding: GradeFinding) -> String {
        var parts = [finding.grade.isNotWritten ? "Nepsal" : "Známka \(finding.grade.value)"]
        if let detail = finding.grade.detail { parts.append(detail) }
        parts.append(finding.grade.weightDescription)
        return parts.joined(separator: " • ")
    }

    private enum Key {
        static let seenNotifications = "watcher.seenNotificationIds"
        static let substitutionDigest = "watcher.substitutionDigest"
    }
}

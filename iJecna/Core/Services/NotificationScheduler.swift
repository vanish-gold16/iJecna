import Foundation
import UserNotifications

/// Plánuje lokální upozornění na úkoly a testy.
///
/// Všechno běží na zařízení — žádný server, žádné vzdálené push notifikace.
/// Systém upozornění doručí i když je aplikace zavřená, protože čas je znám dopředu;
/// tím se liší od upozornění na nové známky, která musí web aktivně kontrolovat.
@MainActor
final class NotificationScheduler {

    private let center = UNUserNotificationCenter.current()

    /// Prefix identifikátoru, aby šlo naše požadavky odlišit od budoucích jiných.
    private static let identifierPrefix = "studytask."

    private static func identifier(for taskId: UUID) -> String {
        identifierPrefix + taskId.uuidString
    }

    // MARK: - Oprávnění

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Plánování

    /// Naplánuje nebo zruší upozornění podle aktuálního stavu záznamu.
    func sync(_ task: StudyTask, quietHours: Bool) async {
        cancel(task.id)

        guard task.hasPendingReminder, let reminderDate = task.reminderDate else { return }
        guard await authorizationStatus() == .authorized else { return }

        let fireDate = quietHours ? Self.shiftedOutOfQuietHours(reminderDate) : reminderDate
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = Self.title(for: task)
        content.body = Self.body(for: task)
        content.sound = .default
        content.interruptionLevel = task.kind == .test ? .timeSensitive : .active
        content.userInfo = ["taskId": task.id.uuidString]

        let components = Calendar.prague.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: Self.identifier(for: task.id),
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    func cancel(_ taskId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: taskId)])
    }

    /// Přeplánuje všechno — po startu aplikace a po změně nastavení tichých hodin.
    func syncAll(_ tasks: [StudyTask], quietHours: Bool) async {
        let pending = await center.pendingNotificationRequests()
        let ourIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ourIdentifiers)

        for task in tasks where task.hasPendingReminder {
            await sync(task, quietHours: quietHours)
        }
    }

    /// Kolik našich upozornění čeká na doručení. Užitečné v nastavení pro kontrolu.
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
            .count
    }

    // MARK: - Texty

    private static func title(for task: StudyTask) -> String {
        let subject = task.subjectShort ?? task.subjectName
        let when = task.dueDescription()
        return switch task.kind {
        case .test: "Test \(when) — \(subject)"
        case .homework: "Úkol na \(when) — \(subject)"
        case .project: "Projekt \(when) — \(subject)"
        case .note: "\(subject) — \(when)"
        }
    }

    private static func body(for task: StudyTask) -> String {
        task.details.isEmpty ? task.title : "\(task.title)\n\(task.details)"
    }

    /// Posune upozornění z noci na ráno. Úkol zadaný na pondělí nemá pískat v neděli o půlnoci.
    private static func shiftedOutOfQuietHours(_ date: Date, calendar: Calendar = .prague) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= 21 || hour < 7 else { return date }

        // Po 21:00 přesuneme na ráno následujícího dne, před 7:00 na ráno téhož dne.
        let base = hour >= 21
            ? calendar.date(byAdding: .day, value: 1, to: date) ?? date
            : date
        return calendar.date(bySettingHour: 7, minute: 0, second: 0, of: base) ?? date
    }
}

/// Zajišťuje, že se upozornění ukáže i když je aplikace zrovna otevřená.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

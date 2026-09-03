import Foundation

enum SubstitutionError: LocalizedError, Equatable, Sendable {
    case providerUnreachable(String)
    case providerNotWorking(String)
    case malformedResponse(String)
    case classUnknown

    var errorDescription: String? {
        switch self {
        case .providerUnreachable: "Službu s mimořádným rozvrhem se nepodařilo kontaktovat."
        case .providerNotWorking(let reason): "Služba hlásí poruchu: \(reason)"
        case .malformedResponse: "Služba vrátila data v neočekávané podobě."
        case .classUnknown: "Nevíme, do které třídy chodíš, takže nejde vybrat suplování."
        }
    }
}

/// Čte mimořádný rozvrh (suplování).
///
/// Škola ho vede v tabulce na svém SharePointu za přihlášením Microsoftem —
/// tam aplikace nedosáhne. Existuje ale veřejná služba, která tu tabulku
/// převádí na JSON, a ta se používá tady.
///
/// Dvě věci stojí za zdůraznění:
///
/// - **Není to server školy.** Provozuje ho někdo třetí, proto jde adresa
///   v nastavení přepsat a proto výpadek téhle služby nesmí shodit rozvrh.
/// - **Neposílá se nic o uživateli.** Stáhne se celá veřejná tabulka a filtruje
///   se až v telefonu, takže se služba nedozví ani třídu, ani kdo se ptá.
actor SubstitutionService {

    /// Výchozí poskytovatel. Tentýž, jaký používá aplikace JecnaApp.
    static let defaultProvider = URL(string: "https://jecnarozvrh.jzitnik.dev")!

    private let provider: URL
    private let session: URLSession

    init(provider: URL = SubstitutionService.defaultProvider, timeout: TimeInterval = 12) {
        self.provider = provider

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// Suplování pro danou třídu.
    func schedule(for className: String) async throws -> SubstitutionSchedule {
        guard !className.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SubstitutionError.classUnknown
        }

        try await checkProvider()
        let response = try await fetchAll()
        return Self.schedule(from: response, className: className)
    }

    // MARK: - Síť

    private func checkProvider() async throws {
        let data = try await get("status")
        guard let status = try? JSONDecoder().decode(ProviderStatus.self, from: data) else {
            throw SubstitutionError.malformedResponse("status")
        }
        guard status.working else {
            throw SubstitutionError.providerNotWorking(status.message ?? "bez uvedení důvodu")
        }
    }

    private func fetchAll() async throws -> APIResponse {
        let data = try await get("versioned/v3")
        do {
            return try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw SubstitutionError.malformedResponse(String(describing: error))
        }
    }

    private func get(_ path: String) async throws -> Data {
        let url = provider.appendingPathComponent(path)
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw SubstitutionError.providerUnreachable("neočekávaná odpověď")
            }
            return data
        } catch let error as SubstitutionError {
            throw error
        } catch {
            throw SubstitutionError.providerUnreachable(error.localizedDescription)
        }
    }

    // MARK: - Převod na model

    /// Filtruje celou tabulku na jednu třídu. Děje se to až tady, v telefonu,
    /// takže se poskytovatel nedozví, koho se to týká.
    static func schedule(from response: APIResponse, className: String) -> SubstitutionSchedule {
        let days: [SubstitutionDay] = response.schedule.compactMap { date, daily in
            guard let day = Self.date(from: date) else { return nil }

            let announcements = (response.announcements[date] ?? [])
                .filter { $0.applies(to: className) }

            return SubstitutionDay(
                date: day,
                isSchoolDay: daily.info.inWork,
                changes: daily.changes[className] ?? [],
                absences: daily.absence,
                note: daily.takesPlace?.normalizedWhitespace.nilIfEmpty,
                announcements: announcements
            )
        }

        return SubstitutionSchedule(
            status: response.status,
            days: days.sorted { $0.date < $1.date }
        )
    }

    static func date(from raw: String) -> Date? {
        dateFormatter.date(from: raw)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .prague
        formatter.timeZone = Calendar.prague.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Podoba odpovědi

    private struct ProviderStatus: Decodable {
        let working: Bool
        let message: String?
    }

    struct APIResponse: Decodable, Sendable {
        let status: SubstitutionStatus
        let announcements: [String: [SubstitutionAnnouncement]]
        let schedule: [String: DailyData]
    }

    struct DailyData: Decodable, Sendable {
        let info: DayInfo
        /// Klíčem je název třídy, hodnotou změny po hodinách.
        let changes: [String: [SubstitutionChange?]]
        let absence: [TeacherAbsence]
        let takesPlace: String?
    }

    struct DayInfo: Decodable, Sendable {
        let inWork: Bool
    }
}

// MARK: - Ruční čtení absence

extension TeacherAbsence {
    /// Tabulka uvádí rozsah hodin třemi různými způsoby: chybí, je to číslo,
    /// nebo je to rozmezí. Proto se čte ručně.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .invalid
        teacher = try? container.decodeIfPresent(String.self, forKey: .teacher)
        teacherCode = (try? container.decode(String.self, forKey: .teacherCode)) ?? ""

        if let hour = try? container.decodeIfPresent(Int.self, forKey: .hours) {
            hours = .single(hour)
        } else if let range = try? container.decodeIfPresent(HourRange.self, forKey: .hours) {
            hours = .range(from: range.from, to: range.to)
        } else {
            hours = nil
        }

        let substitute = try? container.decodeIfPresent(Substitute.self, forKey: .substitute)
        substituteCode = substitute?.teacherCode
        substituteTeacher = substitute?.teacher
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case teacher, teacherCode, hours
        case substitute = "zastupuje"
    }

    private struct HourRange: Decodable {
        let from: Int
        let to: Int
    }

    private struct Substitute: Decodable {
        let teacher: String?
        let teacherCode: String
    }
}

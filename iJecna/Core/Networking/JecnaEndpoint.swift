import Foundation

/// Adresy stránek školního webu.
///
/// Ječná nemá API — všechno jsou HTML stránky, které se dotazují běžným GETem
/// a parametry období se předávají v query. Kódování období je popsané
/// v `iJecnaTests/Fixtures` a ověřené proti skutečným stránkám.
enum JecnaEndpoint {
    case root
    case login
    case logout
    /// Nejmenší přihlášená stránka — používá se na test, jestli relace ještě žije.
    case loginProbe

    case news
    case grades(year: SchoolYear, half: SchoolYearHalf?)
    case timetable(year: SchoolYear, periodId: Int?)
    case attendances(year: SchoolYear, month: Int)
    case absences(year: SchoolYear)
    case teachers
    case teacher(tag: String)
    case rooms
    case room(code: String)
    case student(username: String)
    case locker
    case notifications
    case notification(recordId: Int)
    case certificates

    var path: String {
        switch self {
        case .root: "/"
        case .login: "/user/login"
        case .logout: "/user/logout"
        case .loginProbe: "/user-student/record-list"
        case .news: "/akce"
        case .grades: "/score/student"
        case .timetable: "/timetable/class"
        case .attendances: "/absence/passing-student"
        case .absences: "/absence/student"
        case .teachers: "/ucitel"
        case .teacher(let tag): "/ucitel/\(tag)"
        case .rooms: "/ucebna"
        case .room(let code): "/ucebna/\(code)"
        case .student(let username): "/student/\(username)"
        case .locker: "/locker/student"
        case .notifications: "/user-student/record-list"
        case .notification: "/user-student/record"
        case .certificates: "/certification/student"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .grades(let year, let half):
            [URLQueryItem(name: Key.schoolYear, value: String(year.jecnaId))]
                + (half.map { [URLQueryItem(name: Key.schoolYearHalf, value: String($0.rawValue))] } ?? [])
        case .timetable(let year, let periodId):
            [URLQueryItem(name: Key.schoolYear, value: String(year.jecnaId))]
                + (periodId.map { [URLQueryItem(name: Key.timetable, value: String($0))] } ?? [])
        case .attendances(let year, let month):
            [
                URLQueryItem(name: Key.schoolYear, value: String(year.jecnaId)),
                URLQueryItem(name: Key.month, value: String(month)),
            ]
        case .absences(let year):
            [URLQueryItem(name: Key.schoolYear, value: String(year.jecnaId))]
        case .notification(let recordId):
            [URLQueryItem(name: Key.recordId, value: String(recordId))]
        default:
            []
        }
    }

    func url(base: URL) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url ?? base
    }

    /// Názvy query parametrů, které web používá.
    private enum Key {
        static let schoolYear = "schoolYearId"
        static let schoolYearHalf = "schoolYearHalfId"
        static let month = "schoolYearPartMonthId"
        static let timetable = "timetableId"
        static let recordId = "userStudentRecordId"
    }
}

extension JecnaEndpoint {
    /// Oficiální adresa školy.
    static let officialBase = URL(string: "https://www.spsejecna.cz")!
}

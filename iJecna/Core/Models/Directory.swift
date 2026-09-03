import Foundation

// MARK: - Aktuality

struct ArticleAttachment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let label: String
    /// Cesta relativní ke kořeni webu, např. `/soubory/plan.pdf`.
    let downloadPath: String

    init(id: UUID = UUID(), label: String, downloadPath: String) {
        self.id = id
        self.label = label
        self.downloadPath = downloadPath
    }

    var filename: String { downloadPath.split(separator: "/").last.map(String.init) ?? label }
    var fileExtension: String { (filename as NSString).pathExtension.uppercased() }

    var symbolName: String {
        switch fileExtension {
        case "PDF": "doc.richtext"
        case "DOC", "DOCX": "doc.text"
        case "XLS", "XLSX": "tablecells"
        case "ZIP", "RAR": "doc.zipper"
        case "JPG", "JPEG", "PNG": "photo"
        default: "doc"
        }
    }
}

struct Article: Identifiable, Hashable, Codable, Sendable {
    /// Id článku z adresy `/akce/{id}`. Je stabilní napříč načteními,
    /// takže se podle něj dá poznat, co je nové.
    let id: Int
    let title: String
    /// Prostý text — pro náhled a pro vyhledávání.
    let content: String
    let date: Date
    let author: String
    /// Článek viditelný jen po přihlášení.
    let schoolOnly: Bool
    let attachments: [ArticleAttachment]

    init(
        id: Int,
        title: String,
        content: String,
        date: Date,
        author: String,
        schoolOnly: Bool = false,
        attachments: [ArticleAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.date = date
        self.author = author
        self.schoolOnly = schoolOnly
        self.attachments = attachments
    }

    var preview: String {
        content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Učitelé

/// Odkaz na učitele ze seznamu — plné údaje se dotahují z `/ucitel/{tag}`.
struct TeacherRef: Identifiable, Hashable, Codable, Sendable {
    /// Zkratka učitele používaná v rozvrhu i v URL, např. „Nov“.
    let tag: String
    let fullName: String

    var id: String { tag }

    /// Příjmení pro řazení a sekce v seznamu.
    var sortKey: String {
        let stripped = fullName
            .split(separator: " ")
            .filter { !$0.hasSuffix(".") }
        return stripped.last.map(String.init) ?? fullName
    }

    var initials: String {
        let parts = fullName.split(separator: " ").filter { !$0.hasSuffix(".") }
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

struct Teacher: Identifiable, Hashable, Codable, Sendable {
    let tag: String
    let fullName: String
    let username: String
    let schoolMail: String
    let phoneNumbers: [String]
    let cabinet: String?
    /// Třídní učitel které třídy.
    let tutorOfClass: String?
    let consultationHours: String?

    var id: String { tag }

    var reference: TeacherRef { TeacherRef(tag: tag, fullName: fullName) }
}

// MARK: - Učebny

struct Room: Identifiable, Hashable, Codable, Sendable {
    let roomCode: String
    let name: String
    let floor: String?
    /// Kmenová učebna které třídy.
    let homeroomOf: String?
    let manager: TeacherRef?

    var id: String { roomCode }
}

// MARK: - Student

struct Guardian: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let phoneNumber: String?
    let email: String?

    init(id: UUID = UUID(), name: String, phoneNumber: String? = nil, email: String? = nil) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
    }
}

struct Student: Hashable, Codable, Sendable {
    let fullName: String
    let username: String
    let schoolMail: String
    let className: String?
    /// Skupiny, do kterých student patří, např. „1/2, S1“.
    let classGroups: String?
    let birthDate: Date?
    let permanentAddress: String?
    let guardians: [Guardian]
    let profilePicturePath: String?

    var initials: String {
        fullName.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    /// Skupina používaná k filtrování dělených hodin v rozvrhu.
    var primaryGroup: String? {
        classGroups?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct Locker: Hashable, Codable, Sendable {
    let number: String
    let location: String
    let assignedFrom: Date?
    let assignedUntil: Date?
}

// MARK: - Poznámky a pochvaly

struct SchoolNotification: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case good, bad, info

        var title: String {
            switch self {
            case .good: "Pochvala"
            case .bad: "Poznámka"
            case .info: "Informace"
            }
        }

        var symbolName: String {
            switch self {
            case .good: "hand.thumbsup.fill"
            case .bad: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }
    }

    /// `userStudentRecordId` z Ječné.
    let id: Int
    let kind: Kind
    let exactType: String
    let message: String
    let date: Date
    let issuedBy: TeacherRef?
    /// Číslo jednací, které web uvádí u úředních sdělení („č.j. SPSE/00179/2025“).
    var caseNumber: String? = nil
}

// MARK: - Dokumenty

struct SchoolDocument: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let isDirectory: Bool

    init(id: UUID = UUID(), name: String, path: String, isDirectory: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }
}

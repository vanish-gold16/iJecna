import Foundation
import Security

/// Přihlašovací údaje ke školnímu webu.
struct JecnaCredentials: Sendable, Equatable {
    let username: String
    let password: String

    /// Web přijímá i celý školní e-mail; my si držíme holé uživatelské jméno,
    /// protože se používá i v cestě `/student/{username}`.
    init(username: String, password: String) {
        self.username = Self.normalize(username)
        self.password = password
    }

    static func normalize(_ username: String) -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@spsejecna.cz", with: "")
    }
}

/// Uložení hesla do systémové Klíčenky.
///
/// Heslo je ke školnímu účtu, ne k naší aplikaci — nemá tedy co dělat
/// v `UserDefaults` ani v souboru. Položka je vázaná na tohle zařízení
/// a nesynchronizuje se na iCloud, aby se cizí školní účet nešířil dál.
struct CredentialStore: Sendable {

    /// Chyby Klíčenky se hlásí číselným kódem; obalíme je, ať jdou vypsat.
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "kód \(status)"
            return "Klíčenka odmítla operaci: \(message)"
        }
    }

    private let service: String

    init(service: String = "cz.spsejecna.web") {
        self.service = service
    }

    // MARK: - Zápis

    func save(_ credentials: JecnaCredentials) throws {
        guard let password = credentials.password.data(using: .utf8) else { return }

        // V Klíčence držíme vždycky jen jeden účet — přepnutí uživatele
        // ten předchozí nahradí, ne přidá vedle.
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentials.username,
            kSecValueData as String: password,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    // MARK: - Čtení

    func load() -> JecnaCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let result = item as? [String: Any],
              let username = result[kSecAttrAccount as String] as? String,
              let data = result[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }

        return JecnaCredentials(username: username, password: password)
    }

    var hasStoredCredentials: Bool { load() != nil }

    // MARK: - Mazání

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

import Foundation

/// Odpověď školního webu.
///
/// Ječná se o výsledku nevyjadřuje stavovým kódem ani tělem — rozhoduje se
/// podle přesměrování, takže hlavička `Location` je tady stejně důležitá jako obsah.
struct JecnaResponse: Sendable {
    let statusCode: Int
    let body: String
    let location: String?

    var isRedirect: Bool { (300..<400).contains(statusCode) }
    var isOK: Bool { statusCode == 200 }

    /// Cesta, kam server přesměrovává, bez ohledu na to, jestli je absolutní nebo relativní.
    var redirectPath: String? {
        guard let location else { return nil }
        if let url = URL(string: location), url.host != nil {
            return url.path.isEmpty ? "/" : url.path
        }
        return location
    }
}

/// Přenosová vrstva ke školnímu webu.
///
/// Řeší tři věci, které Ječná dělá jinak než běžné API:
///
/// 1. **Nenásleduje přesměrování.** Úspěšné přihlášení je 302 na `/`, neúspěšné
///    je 200 s chybovou stránkou. Kdyby klient přesměrování následoval, obojí by
///    skončilo stejně a nešlo by je rozlišit.
/// 2. **Drží roli.** Kořenová stránka se liší podle cookie `WTDGUID`; bez role
///    „student“ se přihlašovací formulář vůbec nezobrazí.
/// 3. **Sám se přihlašuje zpět.** Relace tiše vyprší a projeví se přesměrováním
///    na `/user/need-login`; klient se v takovém případě přihlásí znovu a požadavek zopakuje.
actor JecnaHTTPClient {

    private let baseURL: URL
    private let session: URLSession
    private let userAgent: String

    /// Údaje pro automatické přihlášení. Drží se jen v paměti;
    /// trvale je uchovává Klíčenka přes `CredentialStore`.
    private var credentials: JecnaCredentials?

    /// Pojistka proti smyčce, kdyby server po přihlášení dál posílal na `/user/need-login`.
    private var isRetryingAfterLogin = false

    private(set) var role: Role = .student

    init(
        baseURL: URL = JecnaEndpoint.officialBase,
        userAgent: String = "iJecna/0.1 (unofficial student app; +https://github.com/vanish-gold16/iJecna)",
        timeout: TimeInterval = 15
    ) {
        self.baseURL = baseURL
        self.userAgent = userAgent

        // Efemérní konfigurace znamená vlastní úložiště cookies jen v paměti:
        // relace nepřežije restart aplikace (a ani se nemíchá se Safari),
        // po startu se přihlásíme znovu z Klíčenky.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = HTTPCookieStorage()
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "cs-CZ,cs;q=0.9",
        ]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Role

    /// Role určuje podobu kořenové stránky. Hodnoty cookie jsou popsané
    /// v dokumentaci JecnaAPI k serveru školy.
    enum Role: String, Sendable {
        case interested, student, employee

        var cookieValue: String {
            switch self {
            case .interested: "0"
            case .student: "10"
            case .employee: "100"
            }
        }
    }

    func setRole(_ role: Role) {
        self.role = role
        setCookie(name: "WTDGUID", value: role.cookieValue)
    }

    // MARK: - Přihlášení

    func setCredentials(_ credentials: JecnaCredentials?) {
        self.credentials = credentials
    }

    /// Přihlásí uživatele a zapamatuje si údaje pro automatické obnovení relace.
    func logIn(_ credentials: JecnaCredentials) async throws {
        setRole(.student)

        // CSRF token je vázaný na relaci, takže musí přijít ze stejné relace jako POST.
        let form = try await plainRequest(.root)
        guard let token = Self.extractLoginToken(from: form.body) else {
            // Když na kořenové stránce není ani formulář, ani odkaz na odhlášení,
            // změnila se stránka — a to je chyba parsování, ne přihlašovacích údajů.
            if form.body.contains("/user/logout") {
                self.credentials = credentials
                return
            }
            throw JecnaError.parsing("na přihlašovací stránce chybí token3")
        }

        var request = URLRequest(url: JecnaEndpoint.login.url(base: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "user": credentials.username,
            "pass": credentials.password,
            "token3": token,
        ])

        let response = try await send(request)

        // Úspěch pozná jedině přesměrování na kořen. Špatné heslo vrací 200
        // se stránkou „login-problem“, chybějící token přesměrování jinam.
        guard response.isRedirect, let path = response.redirectPath else {
            throw JecnaError.invalidCredentials
        }
        guard path == "/" else {
            throw path.contains("login-problem")
                ? JecnaError.invalidCredentials
                : JecnaError.network("neočekávané přesměrování na \(path)")
        }

        self.credentials = credentials
    }

    func logOut() async {
        credentials = nil
        _ = try? await plainRequest(.logout)
        clearCookies()
    }

    /// Ověří, jestli relace ještě žije. Nepřihlášeného uživatele server
    /// přesměruje, přihlášenému vrátí 200.
    func isLoggedIn() async -> Bool {
        guard let response = try? await plainRequest(.loginProbe) else { return false }
        return response.isOK
    }

    // MARK: - Dotazy

    /// Načte stránku a v případě vypršelé relace se jednou přihlásí a zopakuje.
    func html(_ endpoint: JecnaEndpoint) async throws -> String {
        let response = try await request(endpoint)
        guard response.isOK else {
            // Sem se dostane jen to, co není přihlašovací přesměrování — typicky
            // stránka, na kterou student nemá právo (výuční listy mimo 4. ročník).
            if response.isRedirect { throw JecnaError.notAvailable }
            throw JecnaError.network("server odpověděl \(response.statusCode)")
        }
        return response.body
    }

    func request(_ endpoint: JecnaEndpoint) async throws -> JecnaResponse {
        let response = try await plainRequest(endpoint)

        guard Self.isLoginRedirect(response) else {
            isRetryingAfterLogin = false
            return response
        }

        guard let credentials else { throw JecnaError.sessionExpired }

        if isRetryingAfterLogin {
            // Přihlášení proběhlo, a server přesto chce přihlášení znovu.
            isRetryingAfterLogin = false
            throw JecnaError.sessionExpired
        }

        try await logIn(credentials)
        isRetryingAfterLogin = true
        defer { isRetryingAfterLogin = false }
        return try await plainRequest(endpoint)
    }

    /// Dotaz bez jakéhokoli řešení přihlášení.
    func plainRequest(_ endpoint: JecnaEndpoint) async throws -> JecnaResponse {
        try await send(URLRequest(url: endpoint.url(base: baseURL)))
    }

    // MARK: - Odesílání

    private func send(_ request: URLRequest) async throws -> JecnaResponse {
        do {
            let (data, response) = try await session.data(for: request, delegate: Self.noRedirects)
            guard let http = response as? HTTPURLResponse else {
                throw JecnaError.network("odpověď není HTTP")
            }
            return JecnaResponse(
                statusCode: http.statusCode,
                body: Self.decode(data),
                location: http.value(forHTTPHeaderField: "Location")
            )
        } catch let error as JecnaError {
            throw error
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .networkConnectionLost
                ? JecnaError.offline
                : JecnaError.network(error.localizedDescription)
        } catch {
            throw JecnaError.network(error.localizedDescription)
        }
    }

    /// Stránky jsou v UTF-8, ale starší podstránky CMS občas ujedou do windows-1250.
    private static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let windows1250 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)
        )
        if let legacy = String(data: data, encoding: String.Encoding(rawValue: windows1250)) { return legacy }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Cookies

    private func setCookie(name: String, value: String) {
        guard let host = baseURL.host,
              let cookie = HTTPCookie(properties: [
                  .name: name,
                  .value: value,
                  .domain: host,
                  .path: "/",
              ]) else { return }
        session.configuration.httpCookieStorage?.setCookie(cookie)
    }

    private func clearCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        storage.cookies?.forEach(storage.deleteCookie)
    }

    // MARK: - Pomocné

    /// Odpověď, která posílá uživatele na přihlášení.
    private static func isLoginRedirect(_ response: JecnaResponse) -> Bool {
        guard response.isRedirect, let path = response.redirectPath else { return false }
        return path.hasPrefix("/user/need-login") || path.hasPrefix("/user/login")
    }

    /// Vytáhne CSRF token z přihlašovacího formuláře.
    ///
    /// Záměrně regulárním výrazem: běží to při každém přihlášení a rozjet kvůli
    /// jednomu skrytému poli celý parser HTML by bylo zbytečné.
    static func extractLoginToken(from html: String) -> String? {
        let pattern = #"name=["']token3["'][^>]*value=["']([^"']+)["']"#
        let alternate = #"value=["']([^"']+)["'][^>]*name=["']token3["']"#
        for pattern in [pattern, alternate] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let tokenRange = Range(match.range(at: 1), in: html) {
                return String(html[tokenRange])
            }
        }
        return nil
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        // Do formuláře patří procentové kódování, kde mezera je „+“.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        return fields
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    /// Delegát, který zahazuje přesměrování, aby se dala přečíst hlavička `Location`.
    private static let noRedirects = RedirectBlocker()
}

/// Zahazuje přesměrování, takže volající dostane přímo odpověď 302 i s hlavičkou `Location`.
///
/// Musí stát mimo aktéra a být `nonisolated`: v režimu, kdy je výchozí izolace
/// `MainActor`, se pro izolovanou `async` metodu delegáta nedá vygenerovat
/// ObjC thunk a překladač na tom spadne. Varianta s completion handlerem
/// tenhle problém obchází.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

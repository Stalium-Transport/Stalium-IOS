import Foundation
import WebKit

/// Adresse du site (même API que l'appli Android et le site web).
enum Config {
    static let siteURL = "https://omsi.stalium-transport.fr"
}

/// Objet JSON souple : `j["user"]["name"].string`.
struct J {
    let raw: Any?
    init(_ raw: Any?) { self.raw = raw }

    subscript(key: String) -> J { J((raw as? [String: Any])?[key]) }
    subscript(index: Int) -> J {
        guard let a = raw as? [Any], index >= 0, index < a.count else { return J(nil) }
        return J(a[index])
    }
    var isNull: Bool { raw == nil || raw is NSNull }
    var string: String {
        switch raw {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }
    func string(or def: String) -> String { string.isEmpty ? def : string }
    var int: Int {
        switch raw {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Int(Double(s) ?? 0)
        default: return 0
        }
    }
    var double: Double {
        switch raw {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
    var bool: Bool {
        switch raw {
        case let b as Bool: return b
        case let n as NSNumber: return n.intValue != 0
        case let s as String: return s == "true" || s == "1"
        default: return false
        }
    }
    var array: [J] { (raw as? [Any])?.map { J($0) } ?? [] }
    var id: Int { self["id"].int }
}

struct ApiError: LocalizedError {
    let message: String
    let code: Int
    var errorDescription: String? { message }
}

@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    @Published var loggedIn: Bool

    private init() {
        loggedIn = HTTPCookieStorage.shared.cookies(for: URL(string: Config.siteURL)!)?.contains { $0.name == "STALIUMSESSID" } ?? false
    }
}

enum Api {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpCookieAcceptPolicy = .always
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    private static var csrf: String {
        get { UserDefaults.standard.string(forKey: "csrf") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "csrf") }
    }

    @discardableResult
    static func call(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> J {
        var req = URLRequest(url: URL(string: "\(Config.siteURL)/api/\(path)")!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("StaliumiOS/2.0 (natif)", forHTTPHeaderField: "User-Agent")
        if method != "GET" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:])
            if !csrf.isEmpty { req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token") }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ApiError(message: "Pas de connexion au serveur. Vérifiez votre réseau.", code: 0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let parsed = J(try? JSONSerialization.jsonObject(with: data))
        let msg = parsed["message"].string
        if status == 401 && !path.hasPrefix("login.php") {
            await MainActor.run { Session.shared.loggedIn = false }
            throw ApiError(message: msg.isEmpty ? "Session expirée, reconnectez-vous." : msg, code: 401)
        }
        let explicitFail = (parsed.raw as? [String: Any])?["success"] != nil && !parsed["success"].bool
        if !(200..<300).contains(status) || parsed.isNull || explicitFail {
            throw ApiError(message: msg.isEmpty ? "Erreur serveur (\(status))" : msg, code: status)
        }
        let token = parsed["csrf_token"].string
        if !token.isEmpty { csrf = token }
        return parsed
    }

    static func get(_ path: String) async throws -> J { try await call("GET", path) }
    @discardableResult static func post(_ path: String, _ body: [String: Any] = [:]) async throws -> J { try await call("POST", path, body: body) }
    @discardableResult static func put(_ path: String, _ body: [String: Any] = [:]) async throws -> J { try await call("PUT", path, body: body) }
    @discardableResult static func delete(_ path: String) async throws -> J { try await call("DELETE", path) }

    // MARK: Connexion
    static func login(_ user: String, _ pass: String) async throws -> J {
        try await post("login.php", ["username": user, "password": pass])
    }

    static func verify2fa(_ code: String) async throws {
        try await post("login.php?action=verify_2fa", ["code": code])
        _ = try? await get("mobile.php?action=me") // jeton CSRF de la nouvelle session
    }

    static func logout() async {
        _ = try? await post("login.php?action=logout")
        await clearLocal()
    }

    @MainActor
    static func clearLocal() {
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        csrf = ""
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        Session.shared.loggedIn = false
    }

    static func registerPushToken(_ token: String) async {
        _ = try? await post("mobile.php?action=device_token", ["token": token, "platform": "ios"])
    }

    /// Copie la session dans les pages web ouvertes depuis l'appli.
    @MainActor
    static func shareSession(with store: WKHTTPCookieStore) async {
        for c in HTTPCookieStorage.shared.cookies(for: URL(string: Config.siteURL)!) ?? [] {
            await store.setCookie(c)
        }
    }
}

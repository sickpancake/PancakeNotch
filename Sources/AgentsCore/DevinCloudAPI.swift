import Foundation
import Security

/// The two calls PancakeNotch makes to Devin (issue #55): who the key belongs to, and the sessions of
/// the last 30 days. Only `api.devin.ai`, only with the user's own key, nothing cached or stored on disk.
struct DevinCloudAPI: Sendable {
    enum Failure: Error, Equatable {
        /// Devin turned the key down: it's wrong, expired or revoked (401).
        case rejected
        /// The key is fine but may not do this, such as read sessions (403). Making a new key won't help.
        case forbidden
        /// Too many requests: wait longer before asking again.
        case slowDown
        /// Offline, a server error or an answer that doesn't read.
        case unavailable
    }

    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let base = URL(string: "https://api.devin.ai/v3")!
    /// At most this many pages of 100 sessions are read in one check.
    static let maxPages = 5

    let token: String
    var send: Send = Self.ephemeralSend

    /// No cookies, no cache, no saved credentials: an ephemeral session made once.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static let ephemeralSend: Send = { request in try await session.data(for: request) }

    func identity() async throws(Failure) -> DevinCloudIdentity {
        try await get(Self.base.appending(path: "self"), as: DevinCloudIdentity.self)
    }

    /// `user`'s sessions (every one the key may see when nil) that changed since `since`, not archived.
    /// Asking Devin to filter keeps the answer small and needs no right to read the whole organization.
    /// `complete` is false when there were more than `maxPages` pages.
    func sessions(org: String, user: String?, since: Date) async throws(Failure) -> (items: [DevinCloudSession], complete: Bool) {
        var items: [DevinCloudSession] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var url = Self.base.appending(path: "organizations").appending(path: org).appending(path: "sessions")
            // Changed since, not begun since: a session started long ago that still runs or waits counts.
            // Seconds: should Devin count in milliseconds, this filters nothing and the pages still end.
            var query = [URLQueryItem(name: "first", value: "100"),
                         URLQueryItem(name: "updated_after", value: String(Int(since.timeIntervalSince1970))),
                         URLQueryItem(name: "is_archived", value: "false")]
            if let user, !user.isEmpty { query.append(URLQueryItem(name: "user_ids", value: user)) }
            if let cursor { query.append(URLQueryItem(name: "after", value: cursor)) }
            url.append(queryItems: query)
            let page = try await get(url, as: DevinCloudPage.self)
            items += page.items
            guard page.hasNextPage == true else { return (items, true) }
            // More pages, but no new way to reach them: what was read is all there is, and it's not everything.
            guard let next = page.endCursor, !next.isEmpty, next != cursor else { return (items, false) }
            cursor = next
        }
        return (items, false)
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws(Failure) -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await send(request) } catch { throw .unavailable }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: break
        case 401: throw .rejected
        case 403: throw .forbidden
        case 429: throw .slowDown
        default: throw .unavailable
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) } catch { throw .unavailable }
    }
}

/// Where the Devin key is kept: the macOS Keychain, readable only by PancakeNotch on this Mac.
protocol DevinTokenStore: Sendable {
    func read() -> String?
    func save(_ token: String) -> Bool
    func delete()
}

struct DevinKeychain: DevinTokenStore {
    private static let service = "io.github.sickpancake.PancakeNotch.devin-cloud"
    private static let account = "personal-access-token"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: Self.account]
    }

    func read() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "PancakeNotch: Devin cloud"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

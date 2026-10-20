import Foundation
import GondarCore

enum FetchError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: Duration?)
    case offline
    case unreadable

    var problem: Problem {
        switch self {
        case .unauthorized: .unauthorized
        case .rateLimited: .rateLimited
        case .offline: .offline
        case .unreadable: .unreadableResponse
        }
    }

    var retryAfter: Duration? {
        if case .rateLimited(let retryAfter) = self { return retryAfter }
        return nil
    }
}

/// Follows a redirect only within api.anthropic.com, so the bearer token can never be carried to another host.
/// A refused redirect reaches the client as its 3xx response, which reads as unreadable.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.scheme == "https", request.url?.host == "api.anthropic.com" else { return nil }
        return request
    }
}

/// The two OAuth endpoints Claude Code's token can read: usage and the profile behind the token.
struct AnthropicClient: Sendable {
    private static let baseURL = URL(string: "https://api.anthropic.com/api/oauth/")!

    private let session: URLSession
    private let userAgent: String

    init() {
        // Ephemeral with no cache, so the profile (email, organisation) is never written to disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        userAgent = "Gondar/\(version)"
    }

    func usage(token: String) async -> Result<UsageReport, FetchError> {
        await get("usage", token: token, parse: OAuthUsageParser.parse)
    }

    func profile(token: String) async -> Result<Profile, FetchError> {
        await get("profile", token: token, parse: Profile.parse)
    }

    private func get<Value>(_ path: String, token: String, parse: (Data) throws -> Value) async -> Result<Value, FetchError> {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // URLSession fails only with URLError: no connection, a timeout, or a cancelled poll.
            return .failure(.offline)
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.unreadable) }
        switch http.statusCode {
        case 200:
            guard let value = try? parse(data) else { return .failure(.unreadable) }
            return .success(value)
        case 401, 403:
            return .failure(.unauthorized)
        case 429:
            // Retry-After in seconds; the HTTP-date form is not used by this API and reads as absent.
            let seconds = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let retryAfter: Duration? = seconds.flatMap { $0 >= 0 ? .seconds($0) : nil }
            return .failure(.rateLimited(retryAfter: retryAfter))
        default:
            return .failure(.unreadable)
        }
    }
}

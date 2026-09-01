import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable { case get = "GET", post = "POST" }
    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Case-insensitive header lookup (URLSession preserves server casing).
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// The only way PulseCore talks to the network. Implementations must not follow
/// cross-host redirects (tokens must never be replayed to a different host).
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    /// A session with a delegate retains it (and itself) until invalidated, so a discarded client
    /// would otherwise leak its session and delegate for the life of the process.
    deinit { session.finishTasksAndInvalidate() }

    var configuration: URLSessionConfiguration { session.configuration }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k] = v }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}

/// Refuses every redirect. A bearer token is already attached to the request, and following a
/// redirect would replay it to whatever host the `Location` header names.
internal final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Maps transport errors and non-2xx statuses to `ProviderError` the same way for every provider.
public enum HTTPStatus {
    public static func send(_ request: HTTPRequest, via http: any HTTPClient, expiredHint: String) async throws(ProviderError) -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw .network(error.localizedDescription)
        }
        switch response.status {
        case 200...299: return response
        case 401, 403: throw .credentialsExpired(hint: expiredHint)
        case 429: throw .rateLimited(retryAfter: response.header("Retry-After").flatMap(TimeInterval.init))
        default: throw .network("HTTP \(response.status)")
        }
    }
}

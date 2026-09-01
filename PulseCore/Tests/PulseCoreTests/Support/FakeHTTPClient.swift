import Foundation
@testable import PulseCore

/// A deterministic, locale/OS-independent transport failure for tests. `URLError`'s
/// `localizedDescription` resolves differently depending on whether Foundation's CFNetwork
/// string bundle is available (it isn't under `swift test`'s bare CLI context), so tests that
/// need to verify `error.localizedDescription` is forwarded verbatim should enqueue this instead.
struct StubTransportError: LocalizedError {
    var errorDescription: String? { "stub transport failure" }
}

/// Records every request and answers from a FIFO queue of results.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<HTTPResponse, Error>] = []
    private(set) var requests: [HTTPRequest] = []

    init(_ results: [Result<HTTPResponse, Error>] = []) { queue = results }

    func enqueue(_ response: HTTPResponse) { lock.withLock { queue.append(.success(response)) } }
    func enqueue(status: Int, json: String) { enqueue(HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(json.utf8))) }
    func enqueue(error: Error) { lock.withLock { queue.append(.failure(error)) } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            requests.append(request)
            guard !queue.isEmpty else { throw URLError(.badServerResponse) }
            return try queue.removeFirst().get()
        }
    }
}

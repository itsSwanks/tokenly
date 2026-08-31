import Foundation
import PulseCore

/// The HTTP client handed to app-level stores. Every provider in these tests is a fake that
/// answers from memory and never touches it, so any request reaching here is a mistake — one
/// that should fail loudly and offline rather than quietly go out to the real internet and
/// make the suite depend on the network.
struct NoNetworkHTTPClient: HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

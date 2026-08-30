import Foundation
import Testing
@testable import PulseCore

@Suite struct HTTPClientTests {
    @Test func fakeClientRecordsRequestsAndReturnsQueuedResponses() async throws {
        let fake = FakeHTTPClient()
        fake.enqueue(status: 200, json: #"{"ok":true}"#)
        let request = HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!, headers: ["A": "b"])
        let response = try await fake.send(request)
        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == #"{"ok":true}"#)
        #expect(fake.requests == [request])
    }

    @Test func fakeClientThrowsWhenQueueIsEmpty() async {
        let fake = FakeHTTPClient()
        await #expect(throws: URLError.self) {
            _ = try await fake.send(HTTPRequest(method: .get, url: URL(string: "https://example.com")!))
        }
    }

    @Test func systemClockIsRoughlyNow() {
        let delta = abs(SystemClock().now.timeIntervalSinceNow)
        #expect(delta < 1)
    }

    @Test func fakeClockAdvances() {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 100))
        clock.advance(by: 60)
        #expect(clock.now == Date(timeIntervalSince1970: 160))
    }

    @Test func urlSessionClientIsEphemeralCookielessWithTimeout() {
        let config = URLSessionHTTPClient().configuration
        #expect(config.httpCookieStorage == nil)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.timeoutIntervalForRequest == 15)
        #expect(URLSessionHTTPClient(timeout: 3).configuration.timeoutIntervalForRequest == 3)
    }

    // Calls the delegate method URLSession would actually call, rather than a testing-only seam,
    // so a redirect policy that regressed inside the real callback could not pass this.
    @Test func urlSessionClientRefusesEveryRedirect() async throws {
        let from = URL(string: "https://api.anthropic.com/x")!
        let response = try #require(HTTPURLResponse(url: from, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://evil.example/x"]))
        let redirected = URLRequest(url: URL(string: "https://evil.example/x")!)
        // Never resumed — the task exists only because the delegate signature requires one.
        let task = URLSession.shared.dataTask(with: from)

        let decision: URLRequest? = await withCheckedContinuation { continuation in
            NoRedirectDelegate().urlSession(URLSession.shared, task: task,
                                            willPerformHTTPRedirection: response,
                                            newRequest: redirected) { continuation.resume(returning: $0) }
        }
        #expect(decision == nil)
    }
}

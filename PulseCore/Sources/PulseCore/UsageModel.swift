import Foundation

public struct UsageWindow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case session
        case weekly
        case other(String)
    }

    public let kind: Kind
    public let label: String
    /// 0…100, clamped on construction.
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(kind: Kind, label: String, usedPercent: Double, resetsAt: Date?) {
        self.kind = kind
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    /// Display order. The first `.session` window drives the ring.
    public let windows: [UsageWindow]
    public let fetchedAt: Date
    /// Plan name for display only ("max", "plus", "standard-tier"); nil when unknown.
    public let plan: String?

    public init(windows: [UsageWindow], fetchedAt: Date, plan: String?) {
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.plan = plan
    }

    public var sessionWindow: UsageWindow? {
        windows.first { $0.kind == .session } ?? windows.first
    }
}

public enum ProviderError: Error, Equatable, Sendable {
    /// No credential file / Keychain item. `hint` is a full sentence for the UI.
    case credentialsMissing(hint: String)
    /// Token rejected (401) or lacks a required scope.
    case credentialsExpired(hint: String)
    case network(String)
    case rateLimited(retryAfter: TimeInterval?)
    /// The provider changed its response shape. `String` is a field path, never the payload.
    case unexpectedResponse(String)
    /// Account type the API does not report numeric quota for.
    case unsupportedAccount(String)

    /// Credential problems are terminal until the user acts; everything else is retried.
    public var isCredentialProblem: Bool {
        switch self {
        case .credentialsMissing, .credentialsExpired, .unsupportedAccount: true
        case .network, .rateLimited, .unexpectedResponse: false
        }
    }
}

public enum ProviderStatus: Equatable, Sendable {
    case loading
    case live(UsageSnapshot)
    case stale(UsageSnapshot, lastError: ProviderError)
    case disconnected(ProviderError)

    public var snapshot: UsageSnapshot? {
        switch self {
        case .live(let s), .stale(let s, _): s
        case .loading, .disconnected: nil
        }
    }
}

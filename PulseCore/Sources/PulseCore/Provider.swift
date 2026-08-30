import Foundation

public enum ProviderID: String, CaseIterable, Codable, Sendable, Hashable {
    case claude, codex, gemini

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }

    /// The CLI the user runs to sign in; used in disconnected hints.
    public var cliCommand: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        }
    }
}

/// Reads one provider's usage. Implementations locate credentials, make exactly
/// the HTTP calls they need, and normalize the answer. They never persist anything.
public protocol Provider: Sendable {
    var id: ProviderID { get }
    func fetch(using http: any HTTPClient, clock: any PulseClock) async throws(ProviderError) -> UsageSnapshot
}

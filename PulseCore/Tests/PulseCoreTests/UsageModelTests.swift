import Foundation
import Testing
@testable import PulseCore

@Suite struct UsageModelTests {
    let now = Date(timeIntervalSince1970: 1_756_500_000)

    @Test func usedPercentIsClamped() {
        #expect(UsageWindow(kind: .session, label: "s", usedPercent: -3, resetsAt: nil).usedPercent == 0)
        #expect(UsageWindow(kind: .session, label: "s", usedPercent: 140, resetsAt: nil).usedPercent == 100)
        #expect(UsageWindow(kind: .session, label: "s", usedPercent: 73.4, resetsAt: nil).usedPercent == 73.4)
    }

    @Test func sessionWindowPrefersSessionKind() {
        let weekly = UsageWindow(kind: .weekly, label: "w", usedPercent: 7, resetsAt: nil)
        let session = UsageWindow(kind: .session, label: "s", usedPercent: 73, resetsAt: nil)
        let snap = UsageSnapshot(windows: [weekly, session], fetchedAt: now, plan: nil)
        #expect(snap.sessionWindow == session)
    }

    @Test func sessionWindowFallsBackToFirstWindow() {
        let only = UsageWindow(kind: .other("gemini-2.5-pro"), label: "g", usedPercent: 18, resetsAt: nil)
        let snap = UsageSnapshot(windows: [only], fetchedAt: now, plan: nil)
        #expect(snap.sessionWindow == only)
        #expect(UsageSnapshot(windows: [], fetchedAt: now, plan: nil).sessionWindow == nil)
    }

    @Test func providerIDsHaveDisplayNamesAndCLICommands() {
        #expect(ProviderID.claude.displayName == "Claude")
        #expect(ProviderID.codex.displayName == "Codex")
        #expect(ProviderID.gemini.displayName == "Gemini")
        #expect(ProviderID.codex.cliCommand == "codex")
        #expect(ProviderID.allCases.count == 3)
    }

    @Test func statusSnapshotAccessor() {
        let snap = UsageSnapshot(windows: [], fetchedAt: now, plan: "max")
        #expect(ProviderStatus.live(snap).snapshot == snap)
        #expect(ProviderStatus.stale(snap, lastError: .network("x")).snapshot == snap)
        #expect(ProviderStatus.loading.snapshot == nil)
        #expect(ProviderStatus.disconnected(.credentialsMissing(hint: "h")).snapshot == nil)
    }
}

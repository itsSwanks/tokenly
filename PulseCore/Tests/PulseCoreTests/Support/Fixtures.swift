import Foundation

/// Loads a redacted capture fixture (`Fixtures/<name>.json`) as a UTF-8 string. Shared across
/// provider test suites so each one doesn't carry its own copy.
func fixture(_ name: String) -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! String(contentsOf: url, encoding: .utf8)
}

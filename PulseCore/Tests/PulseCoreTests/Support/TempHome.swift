import Foundation

/// A throwaway directory that stands in for the user's home in tests.
struct TempHome {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ contents: String, at relativePath: String) -> URL {
        let file = url.appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

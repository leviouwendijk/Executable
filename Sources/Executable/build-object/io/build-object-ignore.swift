import Foundation

/// Ensure generated Frame state is ignored even before the first build.
enum BuildObjectIgnore {
    static func ensure(for configuration: URL) throws {
        guard configuration.lastPathComponent == "build.frame" else { return }
        let root = configuration.deletingLastPathComponent()
        let ignoreURL = root.appendingPathComponent(".gitignore")
        try BuildObjectDiscovery.requireOwned(ignoreURL, by: root)
        var contents = FileManager.default.fileExists(atPath: ignoreURL.path)
            ? try String(contentsOf: ignoreURL, encoding: .utf8)
            : ""
        guard !contents.split(whereSeparator: \.isNewline).contains("/compiled.frame") else { return }
        if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
        contents += "/compiled.frame\n"
        try contents.write(to: ignoreURL, atomically: true, encoding: .utf8)
    }
}

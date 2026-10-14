import Foundation
import Version

extension BuildObjectConfiguration {
    public static func new(to url: URL) throws {
        let new = empty()
        do {
            try BuildObjectFile.write(new, to: url)
        } catch {
            throw PklParserError.ioError(
                "Failed to write PKL to '\(url.path)': \(error.localizedDescription)"
            )
        }
    }

    public static func empty() -> String {
        let empty = BuildObjectConfiguration(
            name: "",
            types: [],
            versions: .init(
                // built: ObjectVersion.default_version(for: .built),
                // repository: ObjectVersion.default_version(for: .repository)
                release: ObjectVersion.default_version(for: .release)
            ),
            compile: .init(),
            details: "",
            author: "",
            update: ""
        )
        return empty.string()
    }
}

import Foundation
import Version

extension CompiledLocalBuildObject {
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
        let empty = CompiledLocalBuildObject(
            version: ObjectVersion.default_version(for: .compiled),
            arguments: []
        )
        return empty.string()
    }
}

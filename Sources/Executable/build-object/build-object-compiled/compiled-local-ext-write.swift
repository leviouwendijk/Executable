import Foundation
import Version

extension CompiledLocalBuildObject {
    public func string() -> String {
        var args: String {
            return arguments
            .map { PklText.quote($0) }
            .joined(separator: " ")
        }

        let pklContent = """
        compiled {
            version {
                major = \(version.major)
                minor = \(version.minor)
                patch = \(version.patch)
            }
            arguments { \(args) }
        }
        """

        return pklContent
    }

    public func write(to url: URL) throws {
        try BuildObjectFile.write(string(), to: url)
    }
}

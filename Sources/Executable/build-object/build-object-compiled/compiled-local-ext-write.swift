import Foundation
import Version

extension CompiledLocalBuildObject {
    public func string() -> String {
        let lines = [
            "compiled {",
            "    version {",
            "        major = \(version.major)",
            "        minor = \(version.minor)",
            "        patch = \(version.patch)",
            "    }",
            PklText.collection("arguments", values: arguments, indent: 1),
            "}",
        ]
        return lines.joined(separator: "\n")
    }

    public func write(to url: URL) throws {
        try BuildObjectFile.write(string(), to: url)
    }
}

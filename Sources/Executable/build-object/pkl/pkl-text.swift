import Foundation

/// Canonical string and collection rendering for the supported build-object Pkl subset.
/// Rendering is deliberately separate from parsing; manual files are never reformatted on read.
enum PklText {
    static func quote(_ value: String) -> String {
        String(reflecting: value)
    }

    static func collection(
        _ name: String,
        values: [String],
        indent: Int = 0,
        multilineAfter: Int = 2
    ) -> String {
        let prefix = String(repeating: "    ", count: indent)
        let quoted = values.map(quote)
        if values.count <= multilineAfter {
            let body = quoted.joined(separator: " ")
            return prefix + name + " { " + body + (body.isEmpty ? "}" : " }")
        }
        let inner = String(repeating: "    ", count: indent + 1)
        return ( [prefix + name + " {"]
            + quoted.map { inner + $0 }
            + [prefix + "}"]
        ).joined(separator: "\n")
    }
}

import Foundation
import Version

public struct CompileInstructionDefaults: Codable, Sendable {
    public let use: Bool // let sbm compile like this as override or fallback
    public let arguments: [String]

    public init(use: Bool = false, arguments: [String] = []) {
        self.use = use
        self.arguments = arguments
    }

    public var args: String {
        arguments.map(PklText.quote).joined(separator: " ")
    }

    public func contents() -> String {
        "    use = \(use)\n" + PklText.collection(
            "arguments", values: arguments, indent: 1
        )
    }
}

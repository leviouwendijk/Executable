import Foundation
import Version

public struct CompileInstructionDefaults: Codable, Sendable {
    public let use: Bool // let sbm compile like this as  override or fallback
    public let arguments: [String]
    
    public init(
        use: Bool = false,
        arguments: [String] = []
    ) {
        self.use = use
        self.arguments = arguments
    }

    public var args: String {
        return arguments
        .map { PklText.quote($0) }
        .joined(separator: " ")
    }

    public func contents() -> String {
        return """
            use = \(use)
            arguments { \(args) }
        """
    }
}

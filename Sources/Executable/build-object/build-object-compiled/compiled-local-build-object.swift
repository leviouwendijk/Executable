import Foundation
import Version

// track which version was built locally (.gitignore)
public struct CompiledLocalBuildObject: Codable, Sendable {
    public var version: ObjectVersion
    public let arguments: [String]

    public init(
        version: ObjectVersion,
        arguments: [String]
    ) {
        self.version = version
        self.arguments = arguments
    }

    public init(from url: URL) throws {
        self = try Self.parse(from: url)
    }

    public init(traversingFor compiledFile: String = "compiled.pkl", maxDepth: Int = 5) throws {
        let url = try Self.traverseForCompiledObjectPkl(
            maxDepth: maxDepth,
            compiledFile: compiledFile
        )
        self = try Self.parse(from: url)
    }

    public static func parse(from url: URL) throws -> CompiledLocalBuildObject {
        try BuildObjectFile.read(from: url, decoding: Self.parse(_:))
    }
}

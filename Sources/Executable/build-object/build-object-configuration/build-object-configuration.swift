import Foundation
import Version

// for local repository build info: build-object.pkl 
public struct BuildObjectConfiguration: Codable, Sendable {
    public let uuid: UUID
    public let name: String
    public let types: [ExecutableObjectType]
    public var versions: ProjectVersions
    public let compile: CompileInstructionDefaults
    public let tests: TestConfiguration?
    public let details: String
    public let author: String
    public let update: String

    public init(
        uuid: UUID = UUID(),
        name: String,
        types: [ExecutableObjectType],
        versions: ProjectVersions,
        compile: CompileInstructionDefaults,
        details: String,
        author: String,
        update: String,
        tests: TestConfiguration? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.types = types
        self.versions = versions
        self.compile = compile
        self.tests = tests
        self.details = details
        self.author = author
        self.update = update
    }

    public init(from url: URL) throws {
        self = try BuildObjectConfiguration.parse(from: url)
    }

    public init(traversingFor buildFile: String = "build-object.pkl", maxDepth: Int = 5) throws {
        let url = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            maxDepth: maxDepth,
            buildFile: buildFile
        )
        self = try BuildObjectConfiguration.parse(from: url)
    }

    public static func parse(from url: URL) throws -> BuildObjectConfiguration {
        try BuildObjectFile.read(from: url, decoding: Self.parse(_:))
    }
}

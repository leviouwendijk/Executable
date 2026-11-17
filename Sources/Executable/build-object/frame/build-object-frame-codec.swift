import Foundation
import Frame
import Version

/// The `Executable` Frame module: what `import Executable;` makes nameable in
/// `build.frame` and `compiled.frame`. `install()` writes it where editors
/// find it.
///
///     import Executable;
///     let build: BuildObject = .{ .uuid = "…", .name = "Primitives", .types = [.library], … };
///
/// build-object.pkl keeps working beside it; discovery prefers build.frame.
public enum ExecutableFrame {
    public static let module = Frame.Module("Executable", types: [
        .decodable(BuildObjectFrameCodec.BuildFields.self, named: "BuildObject"),
        .decodable(BuildObjectFrameCodec.CompiledFields.self, named: "Compiled"),
    ])

    public static let environment = Frame.Environment([module])

    /// Writes `Executable.frame` where editors look for module files.
    @discardableResult
    public static func install(into directory: URL = Frame.modulesDirectory) throws -> URL {
        try module.install(into: directory)
    }
}

/// The written form of each file; the native types stay free of Frame.
enum BuildObjectFrameCodec {
    struct BuildFields: Codable, Sendable, FrameDescribable {
        let uuid: String
        let name: String
        let types: [ExecutableObjectType]
        let versions: ProjectVersions
        let compile: CompileFields?
        let tests: TestFields?
        let details: String
        let author: String
        let update: String

        static var frameSchema: Frame.Schema {
            .object([
                .init("uuid", .string, required: true, summary: "Identifies the project; a UUID."),
                .init("name", .string, required: true, summary: "The package name."),
                .init("types", .array(.members(of: ExecutableObjectType.self)), required: true,
                      summary: "What the project builds; at least one."),
                .init("versions", .object([
                    .init("release", .of(VersionFields.self), required: true, summary: "The released version."),
                ]), required: true),
                .init("compile", .of(CompileFields.self)),
                .init("tests", .of(TestFields.self)),
                .init("details", .string, required: true),
                .init("author", .string, required: true),
                .init("update", .string, required: true, summary: "Where the remote build object is fetched from on renewal."),
            ], summary: "A project's build configuration: the `build` binding of build.frame.")
        }
    }

    struct CompileFields: Codable, Sendable, FrameDescribable {
        let use: Bool?
        let arguments: [String]?

        static var frameSchema: Frame.Schema {
            .object([
                .init("use", .boolean, summary: "Let sbm compile with these arguments, as override or fallback; false by default."),
                .init("arguments", .array(.string), summary: "Arguments for swift build."),
            ], summary: "How sbm compiles the project.")
        }
    }

    struct TestFields: Codable, Sendable, FrameDescribable {
        let primary: String
        let groups: [String: [String]]?

        static var frameSchema: Frame.Schema {
            .object([
                .init("primary", .string, required: true, summary: "The test product run by default."),
                .init("groups", .init(.any, summary: "Named lists of test products: .{ .fast = [\"t_name\"] }.")),
            ], summary: "The project's test products.")
        }
    }

    struct CompiledFields: Codable, Sendable, FrameDescribable {
        let version: ObjectVersion
        let arguments: [String]

        static var frameSchema: Frame.Schema {
            .object([
                .init("version", .of(VersionFields.self), required: true, summary: "The version last built."),
                .init("arguments", .array(.string), required: true, summary: "The arguments it was built with."),
            ], summary: "What the last local build produced: the `compiled` binding of compiled.frame.")
        }
    }

    /// Describes `ObjectVersion`, which Version defines without Frame.
    enum VersionFields: FrameDescribable {
        static var frameSchema: Frame.Schema {
            .object([
                .init("major", .integer, required: true),
                .init("minor", .integer, required: true),
                .init("patch", .integer, required: true),
            ])
        }
    }

    static func modern(_ source: String) throws -> BuildObjectConfiguration {
        let fields = try binding("build", ofType: "BuildObject", as: BuildFields.self, in: source)
        guard let uuid = UUID(uuidString: fields.uuid) else {
            throw BuildObjectFrameError.invalid_uuid(fields.uuid)
        }
        guard !fields.types.isEmpty else {
            throw BuildObjectFrameError.empty_types
        }
        return BuildObjectConfiguration(
            uuid: uuid,
            name: fields.name,
            types: fields.types,
            versions: fields.versions,
            compile: .init(use: fields.compile?.use ?? false, arguments: fields.compile?.arguments ?? []),
            details: fields.details,
            author: fields.author,
            update: fields.update,
            tests: fields.tests.map { .init(primary: $0.primary, groups: $0.groups ?? [:]) }
        )
    }

    static func compiled(_ source: String) throws -> CompiledLocalBuildObject {
        let fields = try binding("compiled", ofType: "Compiled", as: CompiledFields.self, in: source)
        return .init(version: fields.version, arguments: fields.arguments)
    }

    static func source<T: Encodable>(_ name: String, ofType type: String, _ value: T) throws -> String {
        try Frame.document(
            imports: [ExecutableFrame.module.name],
            bindings: [(name: name, type: type, value: value)]
        ).source
    }

    private static func binding<T: Decodable>(
        _ name: String,
        ofType type: String,
        as _: T.Type,
        in source: String
    ) throws -> T {
        let document = try Frame.parse(source, environment: ExecutableFrame.environment)
        guard document.binding(named: name)?.type?.components.last == type else {
            throw BuildObjectFrameError.missing_binding("\(name): \(type)")
        }
        return try document.decode(T.self, binding: name)
    }
}

public enum BuildObjectFrameError: Error, Sendable, LocalizedError {
    case invalid_uuid(String)
    case empty_types
    case missing_binding(String)

    public var errorDescription: String? {
        switch self {
        case .invalid_uuid(let uuid): return "Invalid Frame build UUID: \(uuid)"
        case .empty_types: return "Frame build configuration must declare at least one type."
        case .missing_binding(let binding): return "Frame build configuration must declare `let \(binding)`."
        }
    }
}

public extension BuildObjectConfiguration {
    static func parseFrame(_ source: String) throws -> Self {
        try BuildObjectFrameCodec.modern(source)
    }

    func frameString() throws -> String {
        try BuildObjectFrameCodec.source("build", ofType: "BuildObject", BuildObjectFrameCodec.BuildFields(
            uuid: uuid.uuidString,
            name: name,
            types: types.sorted { $0.rawValue < $1.rawValue },
            versions: versions,
            compile: .init(use: compile.use, arguments: compile.arguments),
            tests: tests.map { .init(primary: $0.primary, groups: $0.groups.isEmpty ? nil : $0.groups) },
            details: details,
            author: author,
            update: update
        ))
    }
}

public extension CompiledLocalBuildObject {
    static func parseFrame(_ source: String) throws -> Self {
        try BuildObjectFrameCodec.compiled(source)
    }

    func frameString() throws -> String {
        try BuildObjectFrameCodec.source("compiled", ofType: "Compiled",
                                         BuildObjectFrameCodec.CompiledFields(version: version, arguments: arguments))
    }
}

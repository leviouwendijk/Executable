import Arguments
import Foundation
import plate
import Interfaces

public enum SwiftConfigCommand: ArgumentCommand {
    public static let name = "config"

    public static let children: [ArgumentCommandType] = [
        SwiftConfigInitCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Manage build-object.pkl"
            ),
        ]
    }
}

public enum SwiftConfigInitCommand: BoundArgumentCommand {
    public static let name = "init"

    public struct Options: ArgumentGroup {
        @Flag(
            "empty",
            help: "Create a minimal empty file quickly"
        )
        public var empty: Bool

        public init() {}
    }

    public enum CommandError:
        Error,
        Sendable,
        LocalizedError,
        Equatable
    {
        case invalidObjectType(String)

        public var errorDescription: String? {
            switch self {
            case .invalidObjectType(let value):
                return "Invalid type '\(value)'. Use binary/application/script."
            }
        }
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Create build-object.pkl in the current directory"
            ),
            try params(
                Options.self
            ),
        ]
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let object = existence(
            of: "build-object.pkl"
        )

        let compiled = existence(
            of: "compiled.pkl"
        )

        if !object.exists {
            if options.empty {
                try BuildObjectConfiguration.new(
                    to: object.url
                )
                print("Created empty build-object.pkl")
                return
            }

            try await setup(
                at: object.url
            )
        }

        if !compiled.exists {
            try CompiledLocalBuildObject.new(
                to: compiled.url
            )
            print("Created empty compiled.pkl")
        }
    }
}

private extension SwiftConfigInitCommand {
    static func existence(
        of file: String
    ) -> (exists: Bool, url: URL) {
        let url = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        .appendingPathComponent(file)

        let exists = FileManager.default.fileExists(
            atPath: url.path
        )

        if exists {
            print("\(file) already exists at \(url.path)")
        } else {
            print("\(file) does not yet exist at \(url.path)")
        }

        return (exists, url)
    }

    static func setup(
        at buildObjectURL: URL
    ) async throws {
        let directory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        print("Name:")
        let name = (readLine() ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        print("Types (comma-separated: binary, application, script):")
        let typeStrings = (readLine() ?? "")
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(
                    in: .whitespaces
                )
            }

        let types = try typeStrings.map { value in
            guard let type = ExecutableObjectType(
                rawValue: value
            ) else {
                throw CommandError.invalidObjectType(
                    value
                )
            }

            return type
        }

        print("Details (optional):")
        let details = readLine() ?? ""

        print("Author (optional, default: \(NSUserName())):")
        let authorInput = readLine() ?? ""
        let author = authorInput.isEmpty
            ? NSUserName()
            : authorInput

        var update = ""

        do {
            update = try await GitRepo.remoteRawBuildObjectURL(
                directory,
                file: "build-object.pkl"
            )
            print("Detected remote build-object URL:")
            print("  \(update)")
        } catch {
            print(
                "note: could not auto-detect remote build-object URL: \(error.localizedDescription)"
            )
        }

        let configuration = BuildObjectConfiguration(
            name: name.isEmpty
                ? (FileManager.default.currentDirectoryPath as NSString).lastPathComponent
                : name,
            types: types,
            versions: .init(
                release: .init(
                    major: 0,
                    minor: 1,
                    patch: 0
                )
            ),
            compile: .init(
                use: false,
                arguments: []
            ),
            details: details,
            author: author,
            update: update
        )

        try configuration.write(
            to: buildObjectURL
        )
        print("Created build-object.pkl")
    }
}

import Arguments
import Foundation
import plate

public enum SwiftModernizeCommand: BoundArgumentCommand {
    public static let name = "modernize"

    public struct Options: ArgumentGroup {
        @Flag(
            "backup",
            default: true,
            help: "Write a .bak file before overwriting"
        )
        public var backup: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Upgrade legacy build-object.pkl to the new schema"
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
        let url = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
        )

        let text = try String(
            contentsOf: url,
            encoding: .utf8
        )

        let parser = PklParser(
            text
        )

        if let modern = try? parser.parseBuildObject() {
            print(
                "Already modern: \(modern.name) (\(url.path))"
            )
            return
        }

        parser.reset()

        print("Trying to parse legacy object…")

        let legacy = try parser.parseLegacyBuildObject()
        let modern = legacy.modernize()

        if options.backup {
            let backup = url
                .deletingPathExtension()
                .appendingPathExtension(
                    "pkl.bak"
                )

            try FileManager.default.copyItem(
                at: url,
                to: backup
            )
        }

        try modern.write(
            to: url
        )

        print(
            "Modernized \(legacy.name) at \(url.path)"
        )
    }
}

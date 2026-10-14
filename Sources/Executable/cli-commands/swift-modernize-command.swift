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
        let url = try BuildObjectDiscovery.requireLocal(
            named: "build-object.pkl",
            in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )

        let text = try String(
            contentsOf: url,
            encoding: .utf8
        )

        if let modern = try? BuildObjectConfiguration.parse(text) {
            print(
                "Already modern: \(modern.name) (\(url.path))"
            )
            return
        }

        print("Trying to parse legacy object…")

        let legacy = try BuildObjectConfiguration.LegacyObject.parse(text)
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

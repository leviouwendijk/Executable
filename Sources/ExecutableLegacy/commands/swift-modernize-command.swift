import Executable
import Arguments
import Foundation

public enum SwiftModernizeCommand: BoundArgumentCommand {
    public static let name = "modernize"

    public struct Options: ArgumentGroup {
        @Opt("project", short: "p", help: "Project directory (defaults to CWD).")
        public var project: String?

        @Flag("no-tag", help: "Do not tag HEAD with the release version from build-object.pkl.")
        public var noTag: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Move build-object.pkl to package.frame: deploys, Tests/package.frame, a release tag, and .gitignore"
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
        let project = options.project.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        let result = try await PackageFrameMigration.migrate(at: project, tag: !options.noTag)

        print("wrote   \(result.packageFrame.path)")
        if let tests = result.testsFrame {
            print("wrote   \(tests.path)")
        }
        for file in result.removed {
            print("removed \(file.path)")
        }
        if result.gitignoreChanged {
            print("updated .gitignore")
        }
        switch result.tag {
        case .existing(let version):
            print("release \(ReleaseTags.name(for: version)) (already tagged)")
        case .tagged(let version):
            print("release \(ReleaseTags.name(for: version)) (tagged HEAD and pushed)")
        case .skipped(let version, let reason):
            print("release \(ReleaseTags.name(for: version)) not tagged: \(reason)")
        }
        if result.unsplitTests {
            print("tests   still in the root package; move them into Tests/ with its own package.frame")
        }
    }
}

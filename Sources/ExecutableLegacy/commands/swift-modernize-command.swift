import Executable
import Arguments
import Foundation
import Version

public enum SwiftModernizeCommand: BoundArgumentCommand {
    public static let name = "modernize"

    public struct Options: ArgumentGroup {
        @Opts(
            "project",
            short: "p",
            help: "A project, or a root to search for build-object.pkl projects (repeatable; defaults to CWD)."
        )
        public var projects: [String]

        @Opt("depth", help: "How many directory levels below each root to search (default 2).")
        public var depth: Int?

        @Flag("dry-run", help: "List the projects that would be migrated, without changing anything.")
        public var dryRun: Bool

        @Flag("no-tag", help: "Do not tag HEAD with the release version from build-object.pkl.")
        public var noTag: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Move build-object.pkl projects to package.frame: deploys, Tests/package.frame, a release tag, and .gitignore"
            ),
            try params(
                Options.self
            ),
            example(
                "sbm modernize -p ~/main/programming/libraries/swiftlibs -p ~/main/programming/binaries/swiftbins --depth 1 --dry-run",
                description: "List every build-object.pkl project directly under both roots."
            ),
        ]
    }

    public enum CommandError: Error, LocalizedError {
        case failed(Int)

        public var errorDescription: String? {
            switch self {
            case .failed(let count): return "\(count) project(s) were not migrated."
            }
        }
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let roots = (options.projects.isEmpty ? [FileManager.default.currentDirectoryPath] : options.projects)
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        let projects = try PackageFrameMigration.discover(in: roots, depth: options.depth ?? 2)

        guard !projects.isEmpty else {
            print("No build-object.pkl projects found.")
            return
        }
        if options.dryRun {
            projects.forEach { print($0.path) }
            print("\(projects.count) project(s).")
            return
        }

        var failures = 0
        var untagged: [String] = []
        var unsplit: [String] = []
        for project in projects {
            print(project.path)
            do {
                let result = try await PackageFrameMigration.migrate(at: project, tag: !options.noTag)
                report(result)
                if case .skipped = result.tag { untagged.append(project.lastPathComponent) }
                if result.unsplitTests { unsplit.append(project.lastPathComponent) }
            } catch {
                failures += 1
                print("  failed  \(error.localizedDescription)")
            }
        }

        if projects.count > 1 {
            print("")
            print("migrated \(projects.count - failures) of \(projects.count)")
            if !untagged.isEmpty { print("untagged \(untagged.joined(separator: ", "))") }
            if !unsplit.isEmpty { print("unsplit  \(unsplit.joined(separator: ", "))") }
        }
        if failures > 0 { throw CommandError.failed(failures) }
    }

    private static func report(_ result: PackageFrameMigration.Result) {
        print("  wrote   \(result.packageFrame.lastPathComponent)")
        if result.testsFrame != nil {
            print("  wrote   Tests/\(PackageFrame.fileName)")
        }
        for file in result.removed {
            print("  removed \(file.lastPathComponent)")
        }
        if result.gitignoreChanged {
            print("  updated .gitignore")
        }
        switch result.tag {
        case .existing(let version):
            print("  release \(ReleaseTag.name(for: version)) (already tagged)")
        case .tagged(let version):
            print("  release \(ReleaseTag.name(for: version)) (tagged HEAD and pushed)")
        case .skipped(let version, let reason):
            print("  release \(ReleaseTag.name(for: version)) not tagged: \(reason)")
        }
        if result.unsplitTests {
            print("  tests   still in the root package; Tests/package.frame declares them until they move into Tests/")
        }
    }
}

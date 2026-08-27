import Arguments
import Foundation
import Processes
import plate

import Interfaces

public enum SwiftRemoteCommand: ArgumentCommand {
    public static let name = "remote"

    public static let children: [ArgumentCommandType] = [
        SwiftRemoteSetCommand.self,
        SwiftRemoteOpenCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Remote helpers (set||open)"
            ),
        ]
    }
}

public enum SwiftRemoteSetCommand: BoundArgumentCommand {
    public static let name = "set"

    public struct Options: ArgumentGroup {
        @Flag(
            "force",
            help: "Overwrite an existing non-empty update URL."
        )
        public var force: Bool

        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Populate `update` with the remote raw build-object URL if missing (use --force to overwrite)."
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
        let directory = projectDirectory(
            options.project
        )

        let objectURL = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: directory
        )

        var configuration = try BuildObjectConfiguration(
            from: objectURL
        )

        if !options.force,
           !configuration.update.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty
        {
            print(
                "update already set; use --force to overwrite."
            )
            return
        }

        let remoteURL = try await GitRepo.remoteRawBuildObjectURL(
            directory,
            file: "build-object.pkl"
        )

        configuration = .init(
            uuid: configuration.uuid,
            name: configuration.name,
            types: configuration.types,
            versions: configuration.versions,
            compile: configuration.compile,
            details: configuration.details,
            author: configuration.author,
            update: remoteURL
        )

        try configuration.write(
            to: objectURL
        )

        print(
            "update set to: \(remoteURL)"
        )
    }
}

public enum SwiftRemoteOpenCommand: BoundArgumentCommand {
    public static let name = "open"

    public struct Options: ArgumentGroup {
        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        @Opt(
            "remote",
            short: "r",
            default: "origin",
            help: "Remote name (default: origin)."
        )
        public var remote: String

        @Opt(
            "path",
            help: "Optional repo path to open (e.g. issues, pulls)."
        )
        public var path: String?

        @Flag(
            "branch",
            help: "Open the current branch tree page."
        )
        public var branch: Bool

        @Opt(
            "ref",
            help: "Explicit ref/branch to use with --branch (overrides default)."
        )
        public var ref: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Open the repository's remote in the default browser."
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
        let url = try await GitRepo.repoWebURL(
            directoryURL: projectDirectory(
                options.project
            ),
            remoteName: options.remote,
            path: options.path.map {
                [$0]
            } ?? [],
            useBranchTree: options.branch,
            ref: options.ref
        )

        let result = try await ProcessRunner().run(
            .init(
                executable: .path(
                    "/usr/bin/open"
                ),
                arguments: [
                    url.absoluteString,
                ],
                io: .pipes
            )
        )

        guard result.isSuccess else {
            throw SwiftRemoteCommandError.openFailed(
                url.absoluteString
            )
        }

        print(
            "Opened \(url.absoluteString)"
        )
    }
}

public enum SwiftRemoteCommandError:
    Error,
    Sendable,
    LocalizedError,
    Equatable
{
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let url):
            return "Failed to open remote URL '\(url)'."
        }
    }
}

private func projectDirectory(
    _ path: String?
) -> URL {
    path.map {
        URL(
            fileURLWithPath: $0,
            isDirectory: true
        )
    } ?? URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
}

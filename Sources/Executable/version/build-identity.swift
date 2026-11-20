import Foundation
import Interfaces
import Readers
import Version
import Writers

/// What a binary was built from, written beside it in `<product>.metadata`: in the deploy
/// directory after a successful deploy, and in `.build/<mode>/` after every successful build.
/// It replaces compiled.pkl: a failed build, or a machine that did not update, never looks
/// current, because only a successful build or deploy writes it.
public struct BuildIdentity: Sendable, Equatable {
    /// The newest release tag reachable from the built commit; nil before the first release.
    public let version: ObjectVersion?
    public let commit: String
    public let dirty: Bool

    public init(version: ObjectVersion?, commit: String, dirty: Bool) {
        self.version = version
        self.commit = commit
        self.dirty = dirty
    }

    /// The identity of HEAD; nil outside a git repository.
    public static func current(at directory: URL) async -> BuildIdentity? {
        guard let commit = try? await GitRepo.gitOut(directory, ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !commit.isEmpty
        else { return nil }
        return .init(
            version: (try? await GitRepo.latestRelease(at: directory)) ?? nil,
            commit: commit,
            dirty: (try? await GitRepo.isDirty(directory)) ?? true
        )
    }

    var metadataLines: [String] {
        [
            "Version=\(version.map(ReleaseTag.name(for:)) ?? "")",
            "Commit=\(commit)",
            "Dirty=\(dirty)",
        ]
    }
}

extension ProductMetadata {
    /// The metadata of a product in `root` (a deploy directory or a build directory), or nil
    /// when no deploy or build recorded it there.
    public static func read(product: String, in root: URL) throws -> ProductMetadata? {
        let file = root.appendingPathComponent("\(product).metadata")
        let result = try TextFileReader(file).read(options: .init(missingFilePolicy: .returnEmpty))
        return result.existed ? .init(parsing: result.text) : nil
    }
}

/// The record a successful build leaves beside its binaries in `.build/<mode>/`, deployed or
/// not. A product that is not deployed (an app running from its own `.app`, whose binary links
/// into `.build`) is current while this records HEAD; wiping `.build` removes the binary and the
/// record together, so the next renewal builds again.
public enum BuildRecord {
    public static func directory(project: URL, mode: Build.Config.Mode) -> URL {
        project
            .standardizedFileURL
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent(Build.Config(mode: mode).buildDirComponent, isDirectory: true)
    }

    public static func write(
        products: [String],
        project: URL,
        mode: Build.Config.Mode,
        identity: BuildIdentity?
    ) throws {
        let directory = directory(project: project, mode: mode)
        let content = ([
            "ProjectRootPath=\(project.path)",
            "BuildType=\(Build.Config(mode: mode).buildDirComponent)",
            "BuiltAt=\(ISO8601DateFormatter().string(from: Date()))",
        ] + (identity?.metadataLines ?? [])).joined(separator: "\n")
        for product in products {
            try FileWriter(directory.appendingPathComponent("\(product).metadata"))
                .write(content, options: .overwriteWithoutBackup)
        }
    }
}

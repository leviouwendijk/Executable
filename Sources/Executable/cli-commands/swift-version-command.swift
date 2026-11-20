import Arguments
import Foundation
import Indentation
import plate

import Interfaces
import Version

public enum SwiftVersionCommand: RunnableArgumentCommand {
    public static let name = "version"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Show current versions (built vs repository) and repo divergence"
            ),
        ]
    }

    public static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        let current = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        if let package = try PackageFrame.package(in: current) {
            let status = try await PackageVersionStatus.inspect(at: current, configuration: package)
            print("release:  \(status.release.map(ReleaseTag.name(for:)) ?? "untagged")")
            if let head = status.head {
                print("head:     \(head.commit.prefix(12))\(head.dirty ? " (dirty)" : "")")
            }
            for entry in status.deployed {
                guard let metadata = entry.metadata else {
                    print("deployed: \(entry.product) never deployed")
                    continue
                }
                let version = metadata.version.map(ReleaseTag.name(for:)) ?? "untagged"
                let commit = metadata.commit.map { String($0.prefix(12)) } ?? "unknown commit"
                print("deployed: \(entry.product) \(version) at \(commit)\(metadata.dirty ? " (dirty)" : "")")
            }
            for entry in status.built {
                guard let metadata = entry.metadata, let commit = metadata.commit else {
                    print("built:    \(entry.product) no build record")
                    continue
                }
                print("built:    \(entry.product) at \(commit.prefix(12))\(metadata.dirty ? " (dirty)" : "")")
            }
            if !status.behind.isEmpty {
                print("behind:   \(status.behind.joined(separator: ", "))")
            }
            if let divergence = try? await GitRepo.divergence(current) {
                print("git: ahead \(divergence.ahead), behind \(divergence.behind)")
            }
            return
        }

        if let legacy = try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: current) {
            throw ConfigurationFileError.legacy(legacy)
        }
        throw BuildObjectDiscoveryError.notFound(filename: PackageFrame.fileName, maxDepth: 1, startURL: current)
    }
}

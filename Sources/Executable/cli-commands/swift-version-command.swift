import Arguments
import Foundation
import Indentation
import plate

import Interfaces

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
            print("release:  \(status.release.map(ReleaseTags.name(for:)) ?? "untagged")")
            if let head = status.head {
                print("head:     \(head.commit.prefix(12))\(head.dirty ? " (dirty)" : "")")
            }
            for entry in status.deployed {
                guard let metadata = entry.metadata else {
                    print("deployed: \(entry.product) never deployed")
                    continue
                }
                let version = metadata.version.map(ReleaseTags.name(for:)) ?? "untagged"
                let commit = metadata.commit.map { String($0.prefix(12)) } ?? "unknown commit"
                print("deployed: \(entry.product) \(version) at \(commit)\(metadata.dirty ? " (dirty)" : "")")
            }
            if !status.behind.isEmpty {
                print("behind:   \(status.behind.joined(separator: ", "))")
            }
            if let divergence = try? await GitRepo.divergence(current) {
                print("git: ahead \(divergence.ahead), behind \(divergence.behind)")
            }
            return
        }

        let objectURL = try BuildObjectDiscovery.requireLocal(named: BuildObjectDiscovery.legacyConfiguration, in: current)
        let object = try BuildObjectConfiguration(
            from: objectURL
        )

        let compiledURL = try BuildObjectDiscovery.requireLocal(
            named: BuildObjectDiscovery.legacyCompiled, in: current
        )
        let compiled = try CompiledLocalBuildObject(
            from: compiledURL
        )

        print("name: \(object.name)")
        print("types: \(object.types.map(\.rawValue).joined(separator: ", "))")
        print("versions:")
        printi(
            "compiled:   \(compiled.version.string(prefixStyle: .none))"
        )
        printi(
            "release:    \(object.versions.release.string(prefixStyle: .none))"
        )

        if let divergence = try? await GitRepo.divergence(
            objectURL.deletingLastPathComponent()
        ) {
            print(
                "git: ahead \(divergence.ahead), behind \(divergence.behind)"
            )
        }
    }
}

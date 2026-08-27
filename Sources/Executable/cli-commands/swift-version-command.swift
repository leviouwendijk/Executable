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

        let objectURL = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: current
        )
        let object = try BuildObjectConfiguration(
            from: objectURL
        )

        let compiledURL = try CompiledLocalBuildObject.traverseForCompiledObjectPkl(
            from: current
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

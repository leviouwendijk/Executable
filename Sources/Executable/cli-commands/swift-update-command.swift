import Arguments
import Foundation

public enum SwiftUpdateCommand: RunnableArgumentCommand {
    public static let name = "update"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Update and rebuild the current repo"
            ),
            flag(
                "safe",
                help: "Abort if dirty or diverged."
            ),
            arg(
                "directory",
                as: String.self,
                arity: .optional,
                help: "Repository directory (defaults to current working directory)."
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

        let directory = try invocation.value(
            "directory",
            as: String.self
        ).map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? current

        try await ObjectRenewer.check(
            object: RenewableObject(
                path: directory.path
            ),
            safe: try invocation.flag(
                "safe"
            )
        )
    }
}

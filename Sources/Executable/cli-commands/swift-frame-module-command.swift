import Arguments

public enum SwiftFrameModuleCommand: RunnableArgumentCommand {
    public static let name = "frame-module"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Write the Executable Frame module, so editors complete and check package.frame"
            ),
        ]
    }

    public static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        _ = invocation
        print(try ExecutableFrame.install().path)
    }
}

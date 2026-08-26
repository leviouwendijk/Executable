import Arguments

public enum SwiftBuildManagerCommand: ArgumentCommand {
    public static let name = "sbm"
    public static let defaultChild = SwiftBuildCommand.self

    public static let children: [ArgumentCommandType] = [
        SwiftBuildCommand.self,
        SwiftCleanCommand.self,
        SwiftPackCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Swift Build Manager (thin CLI over Executable library)."
            ),
        ]
    }
}

import Arguments

public enum SwiftBuildManagerCommand: ArgumentCommand {
    public static let name = "sbm"
    public static let defaultChild = SwiftBuildCommand.self

    public static let children: [ArgumentCommandType] = [
        SwiftAppCommand.self,
        SwiftAppExecCommand.self,
        SwiftBuildCommand.self,
        SwiftLibraryCommand.self,
        SwiftRenewRepositoriesCommand.self,
        SwiftKillSwiftPMCommand.self,
        SwiftRemoveCommand.self,
        SwiftListCommand.self,
        SwiftSetupCommand.self,
        SwiftCleanCommand.self,
        SwiftPackCommand.self,
        SwiftConfigCommand.self,
        SwiftIncrementCommand.self,
        SwiftUpdateCommand.self,
        SwiftModernizeCommand.self,
        SwiftVersionCommand.self,
        SwiftRemoteCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Swift Build Manager (thin CLI over Executable library)."
            ),
        ]
    }
}

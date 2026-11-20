import Arguments
import Executable

/// sbm while Pkl configuration remains: the core commands plus `modernize`, and `wf`/`pkg`
/// over `.sbm/workflows.pkl`. The sbm binary runs this; once every project is on package.frame
/// and workflows are derived from package sets, it runs `SwiftBuildManagerCommand` again and
/// ExecutableLegacy goes.
public enum SwiftBuildManagerMigrationCommand: ArgumentCommand {
    public static let name = SwiftBuildManagerCommand.name
    public static let defaultChild = SwiftBuildManagerCommand.defaultChild

    public static let children: [ArgumentCommandType] = SwiftBuildManagerCommand.children + [
        SwiftWorkflowCommand.self,
        SwiftPackageScopedCommand.self,
        SwiftModernizeCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        try SwiftBuildManagerCommand.components()
    }
}

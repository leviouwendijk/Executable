import Arguments
import Executable

/// sbm while build-object.pkl projects remain: the core commands plus `modernize`.
/// The sbm binary runs this; once every project is on package.frame it runs
/// `SwiftBuildManagerCommand` again and ExecutableLegacy goes.
public enum SwiftBuildManagerMigrationCommand: ArgumentCommand {
    public static let name = SwiftBuildManagerCommand.name
    public static let defaultChild = SwiftBuildManagerCommand.defaultChild

    public static let children: [ArgumentCommandType] = SwiftBuildManagerCommand.children + [
        SwiftModernizeCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        try SwiftBuildManagerCommand.components()
    }
}

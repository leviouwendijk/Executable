import Foundation

/// What a project's package.frame says about building it: the `package` binding.
///
///     let package: Package = .{
///         .build = .{ .arguments = ["--skip-products", "unifi_debug"] },
///         .deploy = .{ .products = ["unifi"] },
///     };
public struct PackageConfiguration: Sendable, Equatable {
    /// sbm build flags a flagless `sbm build` uses.
    public let buildArguments: [String]
    /// Executable products a flagless `sbm build` builds and deploys; nil without a `.deploy` clause.
    public let deployProducts: [String]?
    /// Release when nil.
    public let mode: BuildMode?
    /// Wipe the caches after a build when they exceed a size.
    public let wipe: WipePolicy?

    public init(
        buildArguments: [String] = [],
        deployProducts: [String]? = nil,
        mode: BuildMode? = nil,
        wipe: WipePolicy? = nil
    ) {
        self.buildArguments = buildArguments
        self.deployProducts = deployProducts
        self.mode = mode
        self.wipe = wipe
    }

    /// The flags a flagless `sbm build` runs with, or nil for a plain release build without deploy.
    public var flaglessArguments: [String]? {
        let arguments = (mode == .debug ? ["--debug"] : []) + buildArguments
        if let deployProducts {
            return arguments + ["--products"] + deployProducts
        }
        guard !arguments.isEmpty else { return nil }
        return arguments + ["--no-move"]
    }
}

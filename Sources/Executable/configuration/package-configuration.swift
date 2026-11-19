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

    public init(
        buildArguments: [String] = [],
        deployProducts: [String]? = nil
    ) {
        self.buildArguments = buildArguments
        self.deployProducts = deployProducts
    }

    /// The flags a flagless `sbm build` runs with, or nil for a plain release build without deploy.
    public var flaglessArguments: [String]? {
        if let deployProducts {
            return buildArguments + ["--products"] + deployProducts
        }
        guard !buildArguments.isEmpty else { return nil }
        return buildArguments + ["--no-move"]
    }
}

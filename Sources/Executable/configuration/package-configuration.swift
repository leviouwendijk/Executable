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

    /// Products a flagless `sbm build` builds without deploying them: the `--products` in
    /// `.build.arguments` of a package without `.deploy` (an app that runs from its own `.app`).
    public var localProducts: [String] {
        guard deployProducts == nil else { return [] }
        var products: [String] = []
        var collecting = false
        for argument in buildArguments {
            if argument.hasPrefix("-") {
                collecting = argument == "--products"
                continue
            }
            guard collecting else { continue }
            products += argument.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }
        return products
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

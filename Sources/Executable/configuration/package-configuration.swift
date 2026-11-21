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
    /// How a flagless `sbm build` signs the products it builds; nil leaves them unsigned.
    public let signing: PackageSigning?

    public init(
        buildArguments: [String] = [],
        deployProducts: [String]? = nil,
        mode: BuildMode? = nil,
        wipe: WipePolicy? = nil,
        signing: PackageSigning? = nil
    ) {
        self.buildArguments = buildArguments
        self.deployProducts = deployProducts
        self.mode = mode
        self.wipe = wipe
        self.signing = signing
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
        guard !arguments.isEmpty || signing != nil else { return nil }
        return arguments + ["--no-move"]
    }
}

/// `.sign` in package.frame: what the package's products are signed with.
///
///     .sign = .{
///         .identity = .apple_development,
///         .identifier = "com.example.tool",
///         .missing = .ad_hoc,
///     },
///
/// The identity is the package's preference. A machine can replace it with `.sign.identity` in
/// its settings.frame, and `--sign` replaces both for one run. When the chosen identity is not on
/// this machine, `.missing` decides: fail (default), sign ad-hoc, or leave the product unsigned.
public struct PackageSigning: Sendable, Equatable {
    public let identity: CodeSigning.IdentitySelector
    public let identifier: String?
    /// Relative to the package directory.
    public let entitlements: String?
    public let hardenedRuntime: Bool
    public let missing: CodeSigning.MissingIdentity

    public init(
        identity: CodeSigning.IdentitySelector,
        identifier: String? = nil,
        entitlements: String? = nil,
        hardenedRuntime: Bool = false,
        missing: CodeSigning.MissingIdentity = .fail
    ) {
        self.identity = identity
        self.identifier = identifier
        self.entitlements = entitlements
        self.hardenedRuntime = hardenedRuntime
        self.missing = missing
    }

    /// The signing configuration for a build of `project`, with this machine's identity (from
    /// settings.frame) in place of the package's when it has one.
    public func configuration(
        in project: URL,
        machineIdentity: CodeSigning.IdentitySelector? = nil
    ) -> CodeSigning.Configuration {
        .init(
            identity: machineIdentity ?? identity,
            identifier: identifier,
            entitlements: entitlements.map { URL(fileURLWithPath: $0, relativeTo: project) },
            hardenedRuntime: hardenedRuntime,
            missing: missing
        )
    }
}

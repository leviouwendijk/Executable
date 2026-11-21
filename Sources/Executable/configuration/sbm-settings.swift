import Foundation
import Frame
import IO
import Readers
import Roots

/// sbm's settings for this machine: `.config/sbm/settings.frame` in each root, home first.
///
///     import Executable;
///
///     let settings: Settings = .{
///         .deploy = "~/sbm-bin",
///         .sign = .{ .identity = "fingerprint:<SHA1>" },
///     };
///
/// `.deploy` is where builds deploy to and where deployed products and their metadata are
/// read from; without a settings file it is `~/sbm-bin`. `.sign.identity` is the identity this
/// machine signs with, in place of the one a package.frame `.sign` names.
/// Each field comes from the first root (home first) that sets it.
public struct SbmSettings: Sendable, Equatable {
    public static let location = RootLocation.config("sbm")
    public static let fileName = "settings.frame"
    public static let defaultDeploy = "~/sbm-bin"

    /// As written in the file; nil means the default.
    public let deploy: String?
    /// This machine's signing identity; nil keeps the package's.
    public let signIdentity: CodeSigning.IdentitySelector?
    /// The first file that set a field; nil when no root has one.
    public let source: URL?

    public init(deploy: String? = nil, signIdentity: CodeSigning.IdentitySelector? = nil, source: URL? = nil) {
        self.deploy = deploy
        self.signIdentity = signIdentity
        self.source = source
    }

    /// `.deploy` with `~` and home-relative paths expanded.
    public var deploymentDirectory: URL {
        Self.expand(deploy ?? Self.defaultDeploy)
    }

    public static func expand(_ path: String, home: URL = Roots.home) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true) }
        return home.appendingPathComponent(path, isDirectory: true)
    }

    /// Each field from the first settings file in the roots (home first) that sets it.
    public static func load(roots: RootSet = Roots.load()) throws -> SbmSettings {
        var deploy: String?
        var signIdentity: CodeSigning.IdentitySelector?
        var source: URL?
        for (_, directory) in roots.existing(location) {
            let file = directory.appendingPathComponent(fileName)
            guard FileSystem.default.exists(file) else { continue }
            let settings = try parse(TextFileReader(file).read().text, source: file)
            if settings.deploy != nil || settings.signIdentity != nil { source = source ?? file }
            deploy = deploy ?? settings.deploy
            signIdentity = signIdentity ?? settings.signIdentity
            if deploy != nil, signIdentity != nil { break }
        }
        return SbmSettings(deploy: deploy, signIdentity: signIdentity, source: source)
    }

    public static func parse(_ source: String, source file: URL? = nil) throws -> SbmSettings {
        let document = try Frame.parse(source, environment: ExecutableFrame.environment)
        guard document.binding(named: "settings")?.type?.components.last == "Settings" else {
            throw SbmSettingsError.missing_binding
        }
        let fields = try document.decode(Fields.self, binding: "settings")
        return SbmSettings(
            deploy: fields.deploy,
            signIdentity: try fields.sign.map { try CodeSigning.IdentitySelector(argument: $0.identity.value) },
            source: file
        )
    }

    /// What the commands use: the settings file, or the defaults when it is missing or broken
    /// (a broken file is reported, never silently ignored).
    public static var resolved: SbmSettings {
        do {
            return try load()
        } catch {
            fputs("warning: \(location)/\(fileName): \(error.localizedDescription); using the defaults (deploy to \(defaultDeploy), the package's signing identity)\n", stderr)
            return SbmSettings()
        }
    }

    struct Fields: Codable, Sendable, FrameDescribable {
        let deploy: String?
        let sign: SignFields?

        static var frameSchema: Frame.Schema {
            .object([
                .init("deploy", .string, summary: "Where builds deploy to and deployed products are read from; ~/sbm-bin by default. ~ and home-relative paths are expanded."),
                .init("sign", .of(SignFields.self)),
            ], summary: "sbm's settings for this machine: the `settings` binding of .config/sbm/settings.frame.")
        }
    }

    struct SignFields: Codable, Sendable, FrameDescribable {
        let identity: PackageFrame.IdentityField

        static var frameSchema: Frame.Schema {
            .object([
                .init("identity", .init(.any, summary: "The identity this machine signs with: .ad_hoc, .apple_development, .developer_id_application, .apple_distribution, or \"fingerprint:<SHA1>\"."), required: true),
            ], summary: "How this machine signs packages whose package.frame has `.sign`: its identity replaces the package's.")
        }
    }
}

public enum SbmSettingsError: Error, Sendable, LocalizedError {
    case missing_binding

    public var errorDescription: String? {
        switch self {
        case .missing_binding: return "settings.frame must declare `let settings: Settings`."
        }
    }
}

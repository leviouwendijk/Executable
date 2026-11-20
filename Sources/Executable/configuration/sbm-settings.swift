import Foundation
import Frame
import IO
import Readers
import Roots

/// sbm's settings for this machine: `.config/sbm/settings.frame` in each root, home first.
///
///     import Executable;
///
///     let settings: Settings = .{ .deploy = "~/sbm-bin" };
///
/// `.deploy` is where builds deploy to and where deployed products and their metadata are
/// read from; without a settings file it is `~/sbm-bin`.
public struct SbmSettings: Sendable, Equatable {
    public static let location = RootLocation.config("sbm")
    public static let fileName = "settings.frame"
    public static let defaultDeploy = "~/sbm-bin"

    /// As written in the file; nil means the default.
    public let deploy: String?
    /// The file it came from; nil when no root has one.
    public let source: URL?

    public init(deploy: String? = nil, source: URL? = nil) {
        self.deploy = deploy
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

    /// The first settings file in the roots (home first) that sets `.deploy`.
    public static func load(roots: RootSet = Roots.load()) throws -> SbmSettings {
        for (_, directory) in roots.existing(location) {
            let file = directory.appendingPathComponent(fileName)
            guard FileSystem.default.exists(file) else { continue }
            let settings = try parse(TextFileReader(file).read().text, source: file)
            if settings.deploy != nil { return settings }
        }
        return SbmSettings()
    }

    public static func parse(_ source: String, source file: URL? = nil) throws -> SbmSettings {
        let document = try Frame.parse(source, environment: ExecutableFrame.environment)
        guard document.binding(named: "settings")?.type?.components.last == "Settings" else {
            throw SbmSettingsError.missing_binding
        }
        let fields = try document.decode(Fields.self, binding: "settings")
        return SbmSettings(deploy: fields.deploy, source: file)
    }

    /// What the commands use: the settings file, or the defaults when it is missing or broken
    /// (a broken file is reported, never silently ignored).
    public static var resolved: SbmSettings {
        do {
            return try load()
        } catch {
            fputs("warning: \(location)/\(fileName): \(error.localizedDescription); deploying to \(defaultDeploy)\n", stderr)
            return SbmSettings()
        }
    }

    struct Fields: Codable, Sendable, FrameDescribable {
        let deploy: String?

        static var frameSchema: Frame.Schema {
            .object([
                .init("deploy", .string, summary: "Where builds deploy to and deployed products are read from; ~/sbm-bin by default. ~ and home-relative paths are expanded."),
            ], summary: "sbm's settings for this machine: the `settings` binding of .config/sbm/settings.frame.")
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

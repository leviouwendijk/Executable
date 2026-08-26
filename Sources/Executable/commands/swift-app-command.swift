import Arguments
import Foundation
import Terminal

public enum SwiftAppCommand: BoundArgumentCommand {
    public static let name = "app"

    public struct Options: ArgumentGroup {
        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        @Opt(
            "app-name",
            help: "App (bundle) name. Defaults to --app-name OR --target OR <Package.name> OR folder name."
        )
        public var appName: String?

        @Opt(
            "target",
            help: "Executable target name (defaults to appName)."
        )
        public var target: String?

        @Opt(
            "build-type",
            default: "release",
            help: "Build type: debug|release (default: release)."
        )
        public var buildType: String

        @Opt(
            "plist",
            help: "Explicit Info.plist path to link/copy."
        )
        public var plist: String?

        @Flag(
            "plist-symlink",
            default: true,
            help: "Symlink Info.plist when --plist is provided or found (default: true). Use --no-plist-symlink to copy."
        )
        public var plistSymlink: Bool

        @Opt(
            "resources-bundle",
            help: "Resources .bundle name (default: <app>_<app>.bundle if present)."
        )
        public var resourcesBundle: String?

        @Flag(
            "sym-resources",
            help: "Reset Resources symlink and exit."
        )
        public var symResources: Bool

        @Flag(
            "wizard",
            help: "Interactive step-by-step wizard to fill in missing options."
        )
        public var wizard: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Create/refresh a .app bundle wired to .build."
            ),
            try params(
                Options.self
            ),
        ]
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let project = options.project.map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        let packageName = (try? await Package.name(
            at: project
        )) ?? project.lastPathComponent

        let executableTargets = (try? await Targets.executableNames(
            in: project
        )) ?? []

        var resolved = options.wizard
            ? runWizard(
                project: project,
                packageName: packageName,
                executableTargets: executableTargets
            )
            : resolveNonInteractive(
                options: options,
                packageName: packageName,
                executableTargets: executableTargets
            )

        if let appName = options.appName {
            resolved.appName = appName
        }

        if let target = options.target {
            resolved.target = target
        }

        if let plist = options.plist {
            resolved.plist = URL(
                fileURLWithPath: plist
            )
        }

        if let resourcesBundle = options.resourcesBundle {
            resolved.bundle = resourcesBundle
        }

        let mode = mode(
            options.buildType
        ) ?? resolved.mode

        let config = Build.Config(
            mode: mode
        )

        if options.symResources {
            try AppBundle.resetResourcesSymlink(
                appName: resolved.appName,
                at: project,
                config: config,
                bundleName: resolved.bundle
            )
            return
        }

        let appDirectory = try AppBundle.createSkeleton(
            appName: resolved.appName,
            at: project
        )

        let buildDirectory = project.appendingPathComponent(
            ".build/\(config.buildDirComponent)"
        )

        try AppBundle.linkBinary(
            appName: resolved.appName,
            from: buildDirectory,
            into: appDirectory,
            targetName: resolved.target
        )

        try AppBundle.linkResourcesBundleIfPresent(
            appName: resolved.appName,
            from: buildDirectory,
            into: appDirectory,
            bundleName: resolved.bundle
        )

        if let plist = resolved.plist {
            if options.plistSymlink {
                try AppBundle.writeOrLinkInfoPlist(
                    appName: resolved.appName,
                    into: appDirectory,
                    strategy: .linkIfPresent(
                        search: [
                            plist,
                        ]
                    )
                )
            } else {
                try AppBundle.copyInfoPlist(
                    from: plist,
                    into: appDirectory
                )

                let destination = appDirectory.appendingPathComponent(
                    "Contents/Info.plist"
                )

                print(
                    "Copied Info.plist to \(destination.path)".ansi(.brightBlack)
                )
            }
        } else {
            try AppBundle.writeOrLinkInfoPlist(
                appName: resolved.appName,
                into: appDirectory,
                strategy: .linkOrWrite(
                    search: [
                        project.appendingPathComponent(".sapp/Info.plist"),
                        project.appendingPathComponent("Sources/\(resolved.target)/Info.plist"),
                        project.appendingPathComponent("Support/Info.plist"),
                        project.appendingPathComponent("Info.plist"),
                    ],
                    userComponent: nil
                )
            )
        }

        let finalApp = project.appendingPathComponent(
            "\(resolved.appName).app"
        )

        print(
            "\nApp bundle ready: \(finalApp.path)\n".ansi(.green, .bold)
        )
    }
}

private extension SwiftAppCommand {
    struct Resolution {
        var appName: String
        var target: String
        var mode: Build.Config.Mode
        var plist: URL?
        var bundle: String?
    }

    static func resolveNonInteractive(
        options: Options,
        packageName: String,
        executableTargets: [String]
    ) -> Resolution {
        let name = options.appName
            ?? options.target
            ?? packageName

        let target = options.target
            ?? (executableTargets.contains(name)
                ? name
                : (executableTargets.first ?? name))

        return Resolution(
            appName: name,
            target: target,
            mode: .release,
            plist: nil,
            bundle: nil
        )
    }

    static func runWizard(
        project: URL,
        packageName: String,
        executableTargets: [String]
    ) -> Resolution {
        print("")
        print("App bundle wizard".ansi(.bold))
        print("------------------".ansi(.brightBlack))

        let app = prompt(
            "App name",
            default: packageName
        )

        let defaultTarget = executableTargets.contains(app)
            ? app
            : (executableTargets.first ?? app)

        let target = prompt(
            "Executable target",
            default: defaultTarget,
            suggestions: executableTargets
        )

        let modeText = prompt(
            "Build type",
            default: "release",
            suggestions: [
                "release",
                "debug",
            ]
        )

        let resolvedMode = mode(
            modeText
        ) ?? .release

        let defaultBundle = "\(app)_\(app).bundle"
        let buildDirectoryName = resolvedMode == .debug
            ? "debug"
            : "release"
        let bundleExists = FileManager.default.fileExists(
            atPath: project.appendingPathComponent(
                ".build/\(buildDirectoryName)/\(defaultBundle)"
            ).path
        )

        let bundle = prompt(
            "Resources bundle name (optional)",
            default: bundleExists ? defaultBundle : ""
        )

        let plistPath = prompt(
            "Explicit Info.plist path (optional)",
            default: ""
        )

        print("")
        print("• app:    \(app)".ansi(.brightBlack))
        print("• target: \(target)".ansi(.brightBlack))
        print(
            "• build:  \(buildDirectoryName)".ansi(.brightBlack)
        )

        if !bundle.isEmpty {
            print("• bundle: \(bundle)".ansi(.brightBlack))
        }

        if !plistPath.isEmpty {
            print("• plist:  \(plistPath)".ansi(.brightBlack))
        }

        print("")

        return Resolution(
            appName: app,
            target: target,
            mode: resolvedMode,
            plist: plistPath.isEmpty
                ? nil
                : URL(fileURLWithPath: plistPath),
            bundle: bundle.isEmpty
                ? nil
                : bundle
        )
    }

    static func mode(
        _ value: String
    ) -> Build.Config.Mode? {
        switch value.lowercased() {
        case "debug":
            return .debug

        case "release":
            return .release

        default:
            return nil
        }
    }

    static func prompt(
        _ question: String,
        default defaultValue: String? = nil,
        suggestions: [String] = []
    ) -> String {
        let suggestionText = suggestions.isEmpty
            ? ""
            : " " + suggestions.map {
                $0.ansi(.brightBlack)
            }.joined(separator: ", ")

        let defaultText = defaultValue.map {
            " [\($0.ansi(.brightBlack))]"
        } ?? ""

        print(
            "\(question)\(defaultText)\(suggestionText): ",
            terminator: ""
        )

        if let line = readLine(),
           !line.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return line.trimmingCharacters(
                in: .whitespaces
            )
        }

        return defaultValue ?? ""
    }
}

import Foundation

public enum AppBundleCreation {
    public struct Request: Sendable {
        public let project: URL
        public let appName: String?
        public let target: String?
        public let configuration: Build.Config.Mode
        public let plist: URL?
        public let plistSymlink: Bool
        public let resourcesBundle: String?

        public init(
            project: URL,
            appName: String? = nil,
            target: String? = nil,
            configuration: Build.Config.Mode = .release,
            plist: URL? = nil,
            plistSymlink: Bool = true,
            resourcesBundle: String? = nil
        ) {
            self.project = project.standardizedFileURL
            self.appName = appName
            self.target = target
            self.configuration = configuration
            self.plist = plist?.standardizedFileURL
            self.plistSymlink = plistSymlink
            self.resourcesBundle = resourcesBundle
        }
    }

    public struct Result: Sendable {
        public let appDirectory: URL
        public let buildDirectory: URL
        public let appName: String
        public let target: String

        public init(
            appDirectory: URL,
            buildDirectory: URL,
            appName: String,
            target: String
        ) {
            self.appDirectory = appDirectory.standardizedFileURL
            self.buildDirectory = buildDirectory.standardizedFileURL
            self.appName = appName
            self.target = target
        }
    }

    public static func create(
        _ request: Request
    ) async throws -> Result {
        let packageName = (
            try? await Package.name(
                at: request.project
            )
        ) ?? request.project.lastPathComponent

        let executableTargets = (
            try? await Targets.executableNames(
                in: request.project
            )
        ) ?? []

        let appName =
            request.appName
            ?? request.target
            ?? packageName

        let target =
            request.target
            ?? (
                executableTargets.contains(
                    appName
                )
                    ? appName
                    : executableTargets.first
                        ?? appName
            )

        let config = Build.Config(
            mode: request.configuration
        )
        let appDirectory = try AppBundle.createSkeleton(
            appName: appName,
            at: request.project
        )
        let buildDirectory = request.project
            .appendingPathComponent(
                ".build/\(config.buildDirComponent)"
            )

        try AppBundle.linkBinary(
            appName: appName,
            from: buildDirectory,
            into: appDirectory,
            targetName: target
        )

        try AppBundle.linkResourcesBundleIfPresent(
            appName: appName,
            from: buildDirectory,
            into: appDirectory,
            bundleName: request.resourcesBundle
        )

        if let plist = request.plist {
            if request.plistSymlink {
                try AppBundle.writeOrLinkInfoPlist(
                    appName: appName,
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
            }
        } else {
            try AppBundle.writeOrLinkInfoPlist(
                appName: appName,
                into: appDirectory,
                strategy: .linkOrWrite(
                    search: [
                        request.project.appendingPathComponent(
                            ".sapp/Info.plist"
                        ),
                        request.project.appendingPathComponent(
                            "Sources/\(target)/Info.plist"
                        ),
                        request.project.appendingPathComponent(
                            "Support/Info.plist"
                        ),
                        request.project.appendingPathComponent(
                            "Info.plist"
                        ),
                    ],
                    userComponent: nil
                )
            )
        }

        return .init(
            appDirectory: appDirectory,
            buildDirectory: buildDirectory,
            appName: appName,
            target: target
        )
    }
}

import Foundation
import plate

public enum AppBundle {
    public enum InfoPlistStrategy: Sendable {
        case linkIfPresent(search: [URL])
        case writeDefault(userComponent: String?)
        case linkOrWrite(search: [URL], userComponent: String?)
    }

    @discardableResult
    public static func createSkeleton(appName: String, at projectDir: URL) throws -> URL {
        let appDir = projectDir.appendingPathComponent("\(appName).app")
        let contents = appDir.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        // `Resources` may become a symlink; ensure parent exists:
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true, attributes: nil)
        return appDir
    }

    /// Symlink `<buildDir>/<targetName>` → `<appDir>/Contents/MacOS/<appName>`
    /// Defaults `targetName` to `appName` if not provided.
    public static func linkBinary(
        appName: String,
        from buildDir: URL,
        into appDir: URL,
        targetName: String? = nil,
        force: Bool = true
    ) throws {
        let tName = targetName ?? appName
        let src = buildDir.appendingPathComponent(tName)
        let dest = appDir.appendingPathComponent("Contents/MacOS/\(appName)")

        guard FileManager.default.fileExists(atPath: src.path) else {
            throw AppBundleError.binaryNotFound(src)
        }
        try replaceWithSymlink(dest: dest, pointingTo: src, force: force)
        print("Linked binary: \(dest.path) → \(src.path)".ansi(.brightBlack))
    }

    /// If a resources bundle exists, symlink it as `<appDir>/Contents/Resources`.
    /// Defaults bundle name to "<appName>_<appName>.bundle" if not provided.
    public static func linkResourcesBundleIfPresent(
        appName: String,
        from buildDir: URL,
        into appDir: URL,
        bundleName: String? = nil,
        force: Bool = true
    ) throws {
        let expected = bundleName ?? "\(appName)_\(appName).bundle"
        let bundle = buildDir.appendingPathComponent(expected)
        let dest = appDir.appendingPathComponent("Contents/Resources")
        guard FileManager.default.fileExists(atPath: bundle.path) else {
            // Silent no-op if bundle isn't present (same behavior as your current tool)
            print("No resources bundle found at \(bundle.path). Skipping Resources link.".ansi(.brightBlack))
            return
        }
        try replaceWithSymlink(dest: dest, pointingTo: bundle, force: force)
        print("Linked resources: \(dest.path) → \(bundle.path)".ansi(.brightBlack))
    }

    /// Write or link a proper `Info.plist` at `<appDir>/Contents/Info.plist`.
    /// - `strategy` lets you link a project-specific file if present, or generate a default.
    /// - `userComponent` contributes to CFBundleIdentifier when generating.
    public static func writeOrLinkInfoPlist(
        appName: String,
        into appDir: URL,
        strategy: InfoPlistStrategy,
        force: Bool = true
    ) throws {
        let dest = appDir.appendingPathComponent("Contents/Info.plist") // proper capitalization

        switch strategy {
        case .linkIfPresent(let search):
            guard let src = firstExisting(in: search) else {
                throw AppBundleError.infoPlistNotFound(search: search)
            }
            try replaceWithSymlink(dest: dest, pointingTo: src, force: force)
            print("Linked Info.plist: \(dest.path) → \(src.path)".ansi(.brightBlack))

        case .writeDefault(let user):
            let contents = defaultPlist(appName: appName, userComponent: user)
            try writeText(contents, to: dest, force: force)
            print("Wrote default Info.plist at \(dest.path)".ansi(.brightBlack))

        case .linkOrWrite(let search, let user):
            if let src = firstExisting(in: search) {
                try replaceWithSymlink(dest: dest, pointingTo: src, force: force)
                print("Linked Info.plist: \(dest.path) → \(src.path)".ansi(.brightBlack))
            } else {
                let contents = defaultPlist(appName: appName, userComponent: user)
                try writeText(contents, to: dest, force: force)
                print("Wrote default Info.plist at \(dest.path)".ansi(.brightBlack))
            }
        }
    }

    /// Convenience for your old `-sym resources` path:
    /// re-create (or fix) the Resources symlink using the expected bundle name.
    public static func resetResourcesSymlink(
        appName: String,
        at projectDir: URL,
        config: Build.Config,
        bundleName: String? = nil,
        force: Bool = true
    ) throws {
        let appDir = projectDir.appendingPathComponent("\(appName).app")
        let buildDir = projectDir.appendingPathComponent(".build/\(config.buildDirComponent)")
        try linkResourcesBundleIfPresent(appName: appName, from: buildDir, into: appDir, bundleName: bundleName, force: force)
    }

    private static func replaceWithSymlink(dest: URL, pointingTo src: URL, force: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        if fm.fileExists(atPath: dest.path) {
            if force { try fm.removeItem(at: dest) }
        }
        try fm.createSymbolicLink(at: dest, withDestinationURL: src)
    }

    private static func writeText(_ text: String, to url: URL, force: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        if fm.fileExists(atPath: url.path) && force { try fm.removeItem(at: url) }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func firstExisting(in candidates: [URL]) -> URL? {
        let fm = FileManager.default
        for u in candidates { if fm.fileExists(atPath: u.path) { return u } }
        return nil
    }

    private static func defaultPlist(appName: String, userComponent: String?) -> String {
        let user = (userComponent ?? ProcessInfo.processInfo.environment["SAPP_BUNDLE_USER"] ?? "local")
        let bundleID = "com.\(user).\(appName.lowercased())"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key><string>\(appName)</string>
            <key>CFBundleIdentifier</key><string>\(bundleID)</string>
            <key>CFBundleExecutable</key><string>\(appName)</string>
            <key>CFBundleVersion</key><string>1</string>
            <key>CFBundleShortVersionString</key><string>1.0</string>
            <key>LSMinimumSystemVersion</key><string>13.0</string>
            <key>NSHighResolutionCapable</key><true/>
        </dict>
        </plist>
        """
    }

}

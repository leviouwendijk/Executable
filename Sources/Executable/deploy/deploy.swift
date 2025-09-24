import Foundation
import plate

public enum Deploy {
    public static func all(
        from projectDir: URL,
        config: Build.Config,
        to defaultDestination: URL
    ) async throws {
        try ensureDir(defaultDestination)
        let names = try await Targets.executableNames(in: projectDir)
        for n in names {
            try moveOne(targetName: n, from: projectDir, config: config, to: defaultDestination)
        }
    }

    public static func selected(
        from projectDir: URL,
        config: Build.Config,
        to defaultDestination: URL,
        targets: [String],
        perTargetDestinations: [String: URL] = [:]
    ) throws {
        try ensureDir(defaultDestination)
        for n in targets {
            let dest = perTargetDestinations[n] ?? defaultDestination
            try ensureDir(dest)
            try moveOne(targetName: n, from: projectDir, config: config, to: dest)
        }
    }

    private static func moveOne(
        targetName: String,
        from projectDir: URL,
        config: Build.Config,
        to destinationRoot: URL
    ) throws {
        let buildDir = projectDir.appendingPathComponent(".build/\(config.buildDirComponent)")
        let sourceURL = buildDir.appendingPathComponent(targetName)
        let destinationURL = destinationRoot.appendingPathComponent(targetName)

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DeployError.sourceMissing(sourceURL)
        }

        print("")
        print("Deploying ".ansi(.brightBlack) + targetName.ansi(.bold) + " → \(destinationRoot.path)".ansi(.brightBlack))

        let fm = FileManager.default
        var existed = false
        do {
            if fm.fileExists(atPath: destinationURL.path) {
                existed = true
                print("\(destinationURL.path)".ansi(.brightBlack, .bold) + " exists — replacing...".ansi(.brightBlack))
            }
            if let replaced = try fm.replaceItemAt(destinationURL, withItemAt: sourceURL) {
                print("Binary ".ansi(.brightBlack) + (existed ? "re".ansi(.brightBlack) : "") +
                      "placed at ".ansi(.brightBlack) + replaced.path.ansi(.bold, .brightBlack))
            } else {
                print("Binary replaced, but no new URL was returned.".ansi(.yellow))
            }
        } catch {
            throw DeployError.replaceFailed(src: sourceURL, dst: destinationURL, underlying: error.localizedDescription)
        }

        do {
            try writeMetadata(for: targetName, projectDir: projectDir, config: config, destinationRoot: destinationRoot)
        } catch {
            print(
                DeployError.metadataWriteFailed(
                    destinationRoot.appendingPathComponent("\(targetName).metadata"),
                    underlying: error.localizedDescription
                ).formatted()
            )
        }

        let banner = "\n        \(targetName) ".ansi(.bold) + "is now an executable binary for " + projectDir.lastPathComponent.ansi(.italic) + "\n    "
        print(banner)
    }

    private static func ensureDir(_ dir: URL) throws {
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { throw DeployError.createDirectoryFailed(dir, underlying: error.localizedDescription) }
    }

    private static func writeMetadata(
        for targetName: String,
        projectDir: URL,
        config: Build.Config,
        destinationRoot: URL
    ) throws {
        let metaURL = destinationRoot.appendingPathComponent("\(targetName).metadata")
        let content =
        """
        ProjectRootPath=\(projectDir.path)
        BuildType=\(config.buildDirComponent)
        DeployedAt=\(ISO8601DateFormatter().string(from: Date()))
        DestinationRoot=\(destinationRoot.path)
        """
        try content.write(to: metaURL, atomically: true, encoding: .utf8)
        print("Metadata written: ".ansi(.brightBlack) + metaURL.path.ansi(.brightBlack, .bold))
    }
}

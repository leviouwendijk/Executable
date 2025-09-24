import Foundation
import plate

public enum DeployedList {
    public struct DeployedBinary: Sendable {
        public let name: String
        public let path: URL
        public let metadata: Metadata?
    }

    public struct Metadata: Sendable {
        public let projectRootPath: String
        public let buildType: String
        public let deployedAt: String
        public let destinationRoot: String
    }

    /// List binaries in a destination root (e.g. ~/sbm-bin), optionally reading sidecar metadata files.
    public static func listBinaries(at destinationRoot: URL, includeDetails: Bool) throws -> [DeployedBinary] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: destinationRoot, includingPropertiesForKeys: nil) else {
            return []
        }

        // binaries: files without extension + executable bit (best-effort)
        let binaries = items.filter { url in
            url.pathExtension.isEmpty && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }

        return try binaries.map { bin in
            let metaURL = destinationRoot.appendingPathComponent(bin.lastPathComponent + ".metadata")
            let md = includeDetails && fm.fileExists(atPath: metaURL.path) ? try parseMetadata(metaURL) : nil
            return DeployedBinary(name: bin.lastPathComponent, path: bin, metadata: md)
        }
    }

    private static func parseMetadata(_ url: URL) throws -> Metadata {
        let text = try String(contentsOf: url)
        var dict: [String:String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { dict[parts[0]] = parts[1] }
        }
        return Metadata(
            projectRootPath: dict["ProjectRootPath"] ?? "",
            buildType: dict["BuildType"] ?? "",
            deployedAt: dict["DeployedAt"] ?? "",
            destinationRoot: dict["DestinationRoot"] ?? ""
        )
    }
}

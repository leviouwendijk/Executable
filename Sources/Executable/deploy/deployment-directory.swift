import Foundation

public enum DeploymentDirectory {
    @discardableResult
    public static func ensureExists(
        at directory: URL = Build.defaultDeploymentDirectory
    ) throws -> Bool {
        if FileManager.default.fileExists(
            atPath: directory.path
        ) {
            return false
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return true
    }
}

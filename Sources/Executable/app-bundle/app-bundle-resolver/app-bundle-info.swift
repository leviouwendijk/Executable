import Foundation

public struct AppBundleInfo: Sendable {
    public let appBundleURL: URL
    public let bundleIdentifier: String?
    public let executableName: String
}

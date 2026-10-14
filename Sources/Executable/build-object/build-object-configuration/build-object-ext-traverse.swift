import Foundation

extension BuildObjectConfiguration {
    public static func traverseForBuildObjectPkl(
        from startURL: URL = Bundle.main.bundleURL,
        maxDepth: Int = 5,
        buildFile: String = "build-object.pkl"
    ) throws -> URL {
        try BuildObjectDiscovery.nearest(named: buildFile, from: startURL, maxDepth: maxDepth)
    }
}

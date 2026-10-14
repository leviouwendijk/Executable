import Foundation
import Testing
import Executable

extension ExecutableTestSuite {
    static let discoverySuite = TestSuite(
        "discovery",
        title: "Build-object ancestor discovery",
        tags: ["executable", "path"]
    ) {
        Test("nearest ancestor wins, preserving maxDepth convention") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let parent = root.appendingPathComponent("parent")
            let child = parent.appendingPathComponent("child")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            let inRoot = parent.appendingPathComponent("build-object.pkl")
            try "parent".write(to: inRoot, atomically: true, encoding: .utf8)
            let nearest = try BuildObjectDiscovery.nearest(named: "build-object.pkl", from: child, maxDepth: 2)
            try Expect.equal(nearest.standardizedFileURL, inRoot.standardizedFileURL)
            _ = try Expect.throwsError(BuildObjectDiscoveryError.self) {
                _ = try BuildObjectDiscovery.nearest(named: "build-object.pkl", from: child, maxDepth: 1)
            }
            let local = child.appendingPathComponent("build-object.pkl")
            try "child".write(to: local, atomically: true, encoding: .utf8)
            let result = try BuildObjectConfiguration.traverseForBuildObjectPkl(from: child, maxDepth: 2)
            try Expect.equal(result.standardizedFileURL, local.standardizedFileURL)
        }

        Test("non-positive depth is rejected") {
            _ = try Expect.throwsError(BuildObjectDiscoveryError.self) {
                _ = try BuildObjectDiscovery.nearest(named: "compiled.pkl", from: FileManager.default.temporaryDirectory, maxDepth: 0)
            }
        }
    }
}

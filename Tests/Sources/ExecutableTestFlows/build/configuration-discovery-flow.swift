import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var configurationDiscoveryFlow: TestFlow {
        TestFlow("configuration-discovery", tags: ["build", "pkl", "boundary"]) {
            Step("implicit configuration lookup never inherits from a parent") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let child = fixture.root.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                let ancestor = fixture.root.appendingPathComponent("build-object.pkl")
                try fixtureConfig().write(to: ancestor, atomically: true, encoding: .utf8)
                let request = try SwiftBuildCommand.projectDefaultRequest(
                    from: child, updateBuiltOnSuccess: false
                )
                switch request.source {
                case .direct:
                    break
                case .buildObject:
                    try Expect.false(true, "must not adopt ancestor implicitly")
                }
                try Expect.equal(request.project, child, "project stays nested")
            }

            Step("approved ancestor retains source provenance but pins nested project") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let child = fixture.root.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                let ancestor = fixture.root.appendingPathComponent("build-object.pkl")
                try fixtureConfig().write(to: ancestor, atomically: true, encoding: .utf8)
                let request = try SwiftBuildCommand.projectDefaultRequest(
                    from: child, updateBuiltOnSuccess: false,
                    approvedAncestorConfiguration: ancestor
                )
                switch request.source {
                case .direct:
                    try Expect.false(true, "approved ancestor should be used")
                case .buildObject(let url, _):
                    try Expect.equal(url, ancestor, "explicit parent source recorded")
                }
                try Expect.equal(request.project, child, "build target must not become ancestor")
            }

            Step("local configuration shadows approved ancestor") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let child = fixture.root.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                let ancestor = fixture.root.appendingPathComponent("build-object.pkl")
                let local = child.appendingPathComponent("build-object.pkl")
                try fixtureConfig().write(to: ancestor, atomically: true, encoding: .utf8)
                try fixtureConfig().write(to: local, atomically: true, encoding: .utf8)
                let request = try SwiftBuildCommand.projectDefaultRequest(
                    from: child, updateBuiltOnSuccess: false,
                    approvedAncestorConfiguration: ancestor
                )
                switch request.source {
                case .direct:
                    try Expect.false(true, "local config should be used")
                case .buildObject(let url, _):
                    try Expect.equal(url, local, "local config takes precedence")
                }
            }

            Step("symlinked compiled file outside project is rejected") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let child = fixture.root.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                let ancestorCompiled = fixture.root.appendingPathComponent("compiled.pkl")
                try "do-not-touch".write(to: ancestorCompiled, atomically: true, encoding: .utf8)
                let nestedCompiled = child.appendingPathComponent("compiled.pkl")
                try FileManager.default.createSymbolicLink(at: nestedCompiled, withDestinationURL: ancestorCompiled)
                try Expect.false(
                    (try? BuildObjectDiscovery.requireOwned(nestedCompiled, by: child)) != nil,
                    "out-of-root symlink must be denied"
                )
                try Expect.equal(
                    try String(contentsOf: ancestorCompiled, encoding: .utf8),
                    "do-not-touch", "no metadata altered"
                )
            }

            Step("nested build does not rewrite parent's compiled snapshot") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let child = fixture.root.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                try FileManager.default.copyItem(
                    at: fixture.root.appendingPathComponent("Package.swift"),
                    to: child.appendingPathComponent("Package.swift")
                )
                try FileManager.default.copyItem(
                    at: fixture.root.appendingPathComponent("Sources", isDirectory: true),
                    to: child.appendingPathComponent("Sources", isDirectory: true)
                )
                let parentObject = fixture.root.appendingPathComponent("build-object.pkl")
                let parentCompiled = fixture.root.appendingPathComponent("compiled.pkl")
                try fixtureConfig().write(to: parentObject, atomically: true, encoding: .utf8)
                try "parent-snapshot-must-survive".write(to: parentCompiled, atomically: true, encoding: .utf8)
                _ = try await Build.captured(
                    at: child,
                    config: .init(mode: .debug, updateBuiltOnSuccess: true)
                )
                try Expect.equal(
                    try String(contentsOf: parentCompiled, encoding: .utf8),
                    "parent-snapshot-must-survive", "parent compiled metadata untouched"
                )
                try Expect.false(
                    FileManager.default.fileExists(atPath: child.appendingPathComponent("compiled.pkl").path),
                    "do not synthesize compiled.pkl for nested package without local configuration"
                )
            }

            Step("successful locally configured build writes only local compiled snapshot") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let child = fixture.root.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                try FileManager.default.copyItem(
                    at: fixture.root.appendingPathComponent("Package.swift"),
                    to: child.appendingPathComponent("Package.swift")
                )
                try FileManager.default.copyItem(
                    at: fixture.root.appendingPathComponent("Sources", isDirectory: true),
                    to: child.appendingPathComponent("Sources", isDirectory: true)
                )
                let parentCompiled = fixture.root.appendingPathComponent("compiled.pkl")
                try "parent-snapshot-must-survive".write(to: parentCompiled, atomically: true, encoding: .utf8)
                try fixtureConfig().write(
                    to: child.appendingPathComponent("build-object.pkl"), atomically: true, encoding: .utf8
                )
                _ = try await Build.captured(
                    at: child,
                    config: .init(mode: .debug, updateBuiltOnSuccess: true)
                )
                let compiled = try CompiledLocalBuildObject(from: child.appendingPathComponent("compiled.pkl"))
                try Expect.equal(compiled.version.major, 1, "local release version is snapshotted")
                try Expect.equal(
                    try String(contentsOf: parentCompiled, encoding: .utf8),
                    "parent-snapshot-must-survive", "parent snapshot untouched"
                )
            }

            Step("stored Pkl arguments cannot redirect the project root") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let source = fixture.root.appendingPathComponent("build-object.pkl")
                let text = fixtureConfig().replacingOccurrences(
                    of: "--debug" , with: "--project"
                ).replacingOccurrences(
                    of: "--local", with: ".."
                )
                try text.write(to: source, atomically: true, encoding: .utf8)
                let result = try? SwiftBuildCommand.projectDefaultRequest(
                    from: fixture.root, updateBuiltOnSuccess: false
                )
                try Expect.false(result != nil, "configuration may not override project")
            }
        }
    }
}

private func fixtureConfig() -> String {
    """
    uuid = "00000000-0000-0000-0000-000000000001"
    name = "DiscoveryFixture"
    types { "binary" }
    versions { release { major = 1 minor = 0 patch = 0 } }
    compile { use = true arguments { "--debug" "--local" } }
    details = ""
    author = ""
    update = ""
    """
}

import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var configurationDiscoveryFlow: TestFlow {
        TestFlow("configuration-discovery", tags: ["build", "frame", "boundary"]) {
            Step("implicit configuration lookup never inherits from a parent") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let child = fixture.root.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                let ancestor = fixture.root.appendingPathComponent("package.frame")
                try fixtureConfig().write(to: ancestor, atomically: true, encoding: .utf8)
                let request = try SwiftBuildCommand.projectDefaultRequest(
                    from: child
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
                let ancestor = fixture.root.appendingPathComponent("package.frame")
                try fixtureConfig().write(to: ancestor, atomically: true, encoding: .utf8)
                let request = try SwiftBuildCommand.projectDefaultRequest(
                    from: child,
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
                let ancestor = fixture.root.appendingPathComponent("package.frame")
                let local = child.appendingPathComponent("package.frame")
                try fixtureConfig().write(to: ancestor, atomically: true, encoding: .utf8)
                try fixtureConfig().write(to: local, atomically: true, encoding: .utf8)
                let request = try SwiftBuildCommand.projectDefaultRequest(
                    from: child,
                    approvedAncestorConfiguration: ancestor
                )
                switch request.source {
                case .direct:
                    try Expect.false(true, "local config should be used")
                case .buildObject(let url, _):
                    try Expect.equal(url, local, "local config takes precedence")
                }
            }

            Step("a build leaves no compiled state in the project") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                try fixtureConfig().write(
                    to: fixture.root.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8
                )
                _ = try await Build.captured(
                    at: fixture.root,
                    config: .init(mode: .debug)
                )
                for name in ["compiled.pkl", "compiled.frame"] {
                    try Expect.false(
                        FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(name).path),
                        "\(name) is not written; deploy metadata records what was built"
                    )
                }
            }

            Step("stored build arguments cannot redirect the project root") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let text = fixtureConfig().replacingOccurrences(
                    of: #""--debug""#, with: #""--project", "..""#
                )
                try text.write(to: fixture.root.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8)
                let result = try? SwiftBuildCommand.projectDefaultRequest(
                    from: fixture.root
                )
                try Expect.false(result != nil, "configuration may not override project")
            }

            Step("a legacy build-object.pkl is refused with the way out") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                try "name = \"Legacy\"".write(
                    to: fixture.root.appendingPathComponent("build-object.pkl"), atomically: true, encoding: .utf8
                )
                do {
                    _ = try SwiftBuildCommand.projectDefaultRequest(from: fixture.root)
                    try Expect.false(true, "build-object.pkl must not be read by core")
                } catch ConfigurationFileError.legacy {
                    try Expect.true(true, "legacy configuration points at sbm modernize")
                }
            }
        }
    }
}

private func fixtureConfig() -> String {
    """
    import Executable;

    let package: Package = .{
        .build = .{ .arguments = ["--debug"] },
    };
    """
}

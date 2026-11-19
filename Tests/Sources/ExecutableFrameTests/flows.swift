import Foundation
import Executable
import Frame
import Testing

enum ExecutableFrameTests {
    static let binary = """
        import Executable;

        let package: Package = .{
            .build = .{ .arguments = ["--skip-products", "unifi_debug"] },
            .deploy = .{ .products = ["unifi", "unifi_agent"] },
        };
        """

    static let library = """
        import Executable;

        let package: Package = .{};
        """

    static let tests = """
        import Executable;

        let tests: Tests = .{
            .primary = "t_unifi",
            .groups = .{ .live = ["t_unifi_live"] },
            .interactive = ["t_unifi_shell"],
        };
        """

    static let suite = TestSuite("executable-frame", title: "Executable Frame module") {
        Test("a package with build and deploy clauses becomes flagless build arguments") {
            guard case .package(let package) = try PackageFrame.parse(binary) else {
                throw ExpectationError("binary declares a package")
            }
            try Expect.equal(package.buildArguments, ["--skip-products", "unifi_debug"], "build arguments")
            try Expect.equal(package.deployProducts, ["unifi", "unifi_agent"], "deployed products")
            try Expect.equal(
                package.flaglessArguments,
                ["--skip-products", "unifi_debug", "--products", "unifi", "unifi_agent"],
                "a flagless build builds and deploys the listed products"
            )
        }

        Test("an empty package builds plainly; build arguments alone never deploy") {
            guard case .package(let package) = try PackageFrame.parse(library) else {
                throw ExpectationError("library declares a package")
            }
            try Expect.isNil(package.flaglessArguments, "no clauses means a plain release build")
            let local = PackageConfiguration(buildArguments: ["--skip-products", "x"])
            try Expect.equal(local.flaglessArguments, ["--skip-products", "x", "--no-move"], "no .deploy keeps the build local")
        }

        Test("a test package declares its primary, groups and interactive products") {
            guard case .tests(let configuration) = try PackageFrame.parse(tests) else {
                throw ExpectationError("tests declares a test package")
            }
            try Expect.equal(configuration.primary, "t_unifi", "primary")
            try Expect.equal(configuration.groups["live"], ["t_unifi_live"], "groups")
            try Expect.equal(configuration.interactive, ["t_unifi_shell"], "interactive products")
            guard case .tests(let empty) = try PackageFrame.parse("import Executable;\n\nlet tests: Tests = .{};\n") else {
                throw ExpectationError("an empty test package is a test package")
            }
            try Expect.isNil(empty.primary, "primary is optional")
        }

        Test("written package.frame reads back the same") {
            let package = PackageConfiguration(buildArguments: ["--skip-products", "x"], deployProducts: ["gm"])
            try Expect.equal(try PackageFrame.parse(PackageFrame.source(package)), .package(package), "package round-trips")
            try Expect.equal(
                try PackageFrame.parse(PackageFrame.source(PackageConfiguration())), .package(PackageConfiguration()),
                "empty package round-trips"
            )
            let configuration = TestConfiguration(primary: "t_a", groups: ["b": ["t_b", "t_c"]], interactive: ["t_shell"])
            try Expect.equal(
                try PackageFrame.parse(PackageFrame.source(configuration)), .tests(configuration),
                "test package round-trips"
            )
        }

        Test("package.frame is a package or a test package, never neither or both") {
            try Expect.throwsError("no recognised binding") {
                _ = try PackageFrame.parse("import Executable;\n\nlet build: Package = .{};\n")
            }
            try Expect.throwsError("both bindings") {
                _ = try PackageFrame.parse(library + "\nlet tests: Tests = .{};\n")
            }
            try Expect.throwsError("deploy without products") {
                _ = try PackageFrame.parse("import Executable;\n\nlet package: Package = .{ .deploy = .{ .products = [] } };\n")
            }
            try Expect.throwsError("missing terminator") {
                _ = try PackageFrame.parse(library.replacingOccurrences(of: "};", with: "}"))
            }
        }

        Test("package.frame wins within a directory but does not shadow a nearer Pkl ancestor") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("frame-discovery-\(UUID().uuidString)", isDirectory: true)
            let child = root.appendingPathComponent("child", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let legacy = root.appendingPathComponent("build-object.pkl")
            try "legacy".write(to: legacy, atomically: true, encoding: .utf8)
            try Expect.equal(try BuildObjectDiscovery.configuration(in: root)?.lastPathComponent,
                             "build-object.pkl", "Pkl remains available")
            try library.write(to: root.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8)
            try Expect.equal(try BuildObjectDiscovery.configuration(in: root)?.lastPathComponent,
                             "package.frame", "package.frame wins within a directory")
            try "child".write(to: child.appendingPathComponent("build-object.pkl"), atomically: true, encoding: .utf8)
            try Expect.equal(try BuildObjectDiscovery.nearestConfiguration(from: child).lastPathComponent,
                             "build-object.pkl", "nearer Pkl wins over farther package.frame")
        }

        Test("legacy initialization writes Pkl and refuses beside package.frame") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("frame-init-\(UUID().uuidString)", isDirectory: true)
            let legacy = root.appendingPathComponent("legacy", isDirectory: true)
            let modern = root.appendingPathComponent("modern", isDirectory: true)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: modern, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let created = try BuildObjectLifecycle.initializeEmpty(at: legacy)
            try Expect.equal(created.configurationURL.lastPathComponent, "build-object.pkl", "legacy configuration")
            try Expect.equal(created.compiledURL.lastPathComponent, "compiled.pkl", "legacy sidecar")
            try library.write(to: modern.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8)
            try Expect.throwsError("no build-object.pkl beside package.frame") {
                _ = try BuildObjectLifecycle.initializeEmpty(at: modern)
            }
        }

        Test("the Executable module file describes package.frame on its own") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("executable-modules-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = try ExecutableFrame.install(into: directory)
            try Expect.equal(file.lastPathComponent, "Executable.frame", "written by module name")
            let loaded = Frame.Environment.loading(modulesIn: directory)
            try Expect.equal(loaded.failures.count, 0, "the module file reads back")

            for (label, source) in [
                ("binary", binary),
                ("library", library),
                ("tests", tests),
                ("written package", try PackageFrame.source(PackageConfiguration(buildArguments: ["-d"], deployProducts: ["gm"]))),
                ("written tests", try PackageFrame.source(TestConfiguration(primary: "t_a", interactive: ["t_b"]))),
            ] {
                try Expect.equal(
                    Frame.problems(in: try Frame.parse(source), environment: loaded.environment).map(\.message), [],
                    "\(label) passes the module file alone"
                )
            }

            let typo = binary
                .replacingOccurrences(of: ".deploy = .{ .products", with: ".deploy = .{ .product")
                .replacingOccurrences(of: ".build = ", with: ".biuld = ")
            try Expect.equal(
                Frame.problems(in: try Frame.parse(typo), environment: loaded.environment).map(\.message),
                [
                    "'package': unknown field 'biuld'",
                    "'package.deploy': unknown field 'product'",
                    "'package.deploy': missing field 'products'",
                ],
                "every mistake, by field"
            )
        }
    }
}

struct ExpectationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

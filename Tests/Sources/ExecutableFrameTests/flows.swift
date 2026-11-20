import Foundation
import Executable
import Frame
import Roots
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
            .groups = .{ .client = ["t_unifi_client"] },
            .interactive = ["t_unifi_shell"],
            .live = ["t_unifi_live"],
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

        Test("a test package declares its primary, groups, interactive and live products") {
            guard case .tests(let configuration) = try PackageFrame.parse(tests) else {
                throw ExpectationError("tests declares a test package")
            }
            try Expect.equal(configuration.primary, "t_unifi", "primary")
            try Expect.equal(configuration.groups["client"], ["t_unifi_client"], "groups")
            try Expect.equal(configuration.interactive, ["t_unifi_shell"], "interactive products")
            try Expect.equal(configuration.live, ["t_unifi_live"], "live products")
            guard case .tests(let empty) = try PackageFrame.parse("import Executable;\n\nlet tests: Tests = .{};\n") else {
                throw ExpectationError("an empty test package is a test package")
            }
            try Expect.isNil(empty.primary, "primary is optional")
        }

        Test("a benchmark package declares its products like a test package") {
            let source = "import Executable;\n\nlet benchmarks: Benchmarks = .{ .primary = \"b_io_fs\", .groups = .{ .hazard = [\"b_io_hazard\"] } };\n"
            guard case .benchmarks(let configuration) = try PackageFrame.parse(source) else {
                throw ExpectationError("benchmarks declares a benchmark package")
            }
            try Expect.equal(configuration.primary, "b_io_fs", "primary")
            try Expect.equal(configuration.groups["hazard"], ["b_io_hazard"], "groups")
            try Expect.equal(
                try PackageFrame.parse(PackageFrame.source(benchmarks: configuration)), .benchmarks(configuration),
                "benchmark package round-trips"
            )
            try Expect.throwsError("tests and benchmarks in one file") {
                _ = try PackageFrame.parse(source + "let tests: Tests = .{};\n")
            }
        }

        Test("mode: packages build in release unless .debug; test packages may override their default") {
            guard case .package(let debug) = try PackageFrame.parse("import Executable;\n\nlet package: Package = .{ .mode = .debug };\n") else {
                throw ExpectationError("a package with a mode")
            }
            try Expect.equal(debug.flaglessArguments, ["--debug", "--no-move"], ".debug builds locally in debug")
            guard case .package(let deployed) = try PackageFrame.parse("import Executable;\n\nlet package: Package = .{ .mode = .debug, .deploy = .{ .products = [\"gm\"] } };\n") else {
                throw ExpectationError("a deployed package with a mode")
            }
            try Expect.equal(deployed.flaglessArguments, ["--debug", "--products", "gm"], ".debug still deploys what .deploy names")
            guard case .package(let plain) = try PackageFrame.parse(library) else {
                throw ExpectationError("library")
            }
            try Expect.isNil(plain.mode, "release is the default, so nothing is written")

            guard case .tests(let tests) = try PackageFrame.parse("import Executable;\n\nlet tests: Tests = .{ .mode = .release };\n") else {
                throw ExpectationError("tests with a mode")
            }
            try Expect.equal(tests.mode, .release, "a test package may build in release")
            try Expect.equal(try PackageFrame.parse(PackageFrame.source(tests)), .tests(tests), "mode round-trips")
            try Expect.throwsError("an unknown mode") {
                _ = try PackageFrame.parse("import Executable;\n\nlet tests: Tests = .{ .mode = .fast };\n")
            }
        }

        Test("settings.frame sets where sbm deploys; without it, ~/sbm-bin") {
            let home = FileManager.default.temporaryDirectory
                .appendingPathComponent("sbm-settings-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let roots = Roots.load(file: home.appendingPathComponent(".config/roots.frame"), home: home)

            let none = try SbmSettings.load(roots: roots)
            try Expect.isNil(none.deploy, "no settings file means the default")
            try Expect.equal(none.deploymentDirectory, SbmSettings.expand("~/sbm-bin"), "the default is ~/sbm-bin")

            let directory = home.appendingPathComponent(".config/sbm", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "import Executable;\n\nlet settings: Settings = .{ .deploy = \"/opt/sbm-bin\" };\n"
                .write(to: directory.appendingPathComponent("settings.frame"), atomically: true, encoding: .utf8)
            let set = try SbmSettings.load(roots: roots)
            try Expect.equal(set.deploy, "/opt/sbm-bin", "the file's .deploy is used")
            try Expect.equal(set.deploymentDirectory.path, "/opt/sbm-bin", "absolute paths are kept")

            try Expect.equal(SbmSettings.expand("~/bin", home: home).path, home.appendingPathComponent("bin").path, "~ is the home directory")
            try Expect.equal(SbmSettings.expand("bin", home: home).path, home.appendingPathComponent("bin").path, "relative paths are relative to home")
            try Expect.throwsError("a settings file without its binding") {
                _ = try SbmSettings.parse("import Executable;\n\nlet package: Package = .{};\n")
            }
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

        Test("initialize writes package.frame and Tests/package.frame once, and refuses beside Pkl") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("frame-init-\(UUID().uuidString)", isDirectory: true)
            let tests = root.appendingPathComponent("Tests", isDirectory: true)
            try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try "// swift-tools-version: 6.2".write(to: tests.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

            let first = try PackageFrame.initialize(in: root)
            try Expect.equal(first.package?.lastPathComponent, "package.frame", "package.frame is written")
            try Expect.equal(first.tests?.deletingLastPathComponent().lastPathComponent, "Tests", "Tests/package.frame is written")
            guard case .tests = try PackageFrame.read(tests.appendingPathComponent("package.frame")) else {
                throw ExpectationError("Tests/package.frame declares tests")
            }
            let again = try PackageFrame.initialize(in: root)
            try Expect.isNil(again.package, "existing package.frame is kept")
            try Expect.isNil(again.tests, "existing Tests/package.frame is kept")

            let legacy = root.appendingPathComponent("legacy", isDirectory: true)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            try "name = \"Legacy\"".write(to: legacy.appendingPathComponent("build-object.pkl"), atomically: true, encoding: .utf8)
            try Expect.throwsError("no package.frame beside build-object.pkl") {
                _ = try PackageFrame.initialize(in: legacy)
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
                ("written tests", try PackageFrame.source(TestConfiguration(primary: "t_a", interactive: ["t_b"], live: ["t_c"]))),
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

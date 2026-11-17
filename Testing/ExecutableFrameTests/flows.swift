import Foundation
import Executable
import Frame
import Testing

enum ExecutableFrameTests {
    static let example = """
        import Executable;

        let build: BuildObject = .{
            .uuid = "1D096F39-F17E-4C38-A193-04B8A3A5079A",
            .name = "Primitives",
            .types = [.library],
            .versions = .{ .release = .{ .major = 0, .minor = 1, .patch = 0 } },
            .compile = .{ .use = false, .arguments = [] },
            .tests = .{ .primary = "t_primitives", .groups = .{ .fast = ["t_primitives"] } },
            .details = "",
            .author = "levi",
            .update = "https://raw.githubusercontent.com/leviouwendijk/Primitives/master/build-object.pkl",
        };
        """

    static let suite = TestSuite("executable-frame", title: "Executable Frame migration") {
        Test("Frame takes precedence locally but does not shadow a nearer Pkl ancestor") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("frame-discovery-\(UUID().uuidString)", isDirectory: true)
            let child = root.appendingPathComponent("child", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let legacy = root.appendingPathComponent("build-object.pkl")
            let frame = root.appendingPathComponent("build.frame")
            try "legacy".write(to: legacy, atomically: true, encoding: .utf8)
            try Expect.equal(try BuildObjectDiscovery.configuration(in: root)?.lastPathComponent,
                             "build-object.pkl", "Pkl remains available")
            try "frame".write(to: frame, atomically: true, encoding: .utf8)
            try Expect.equal(try BuildObjectDiscovery.configuration(in: root)?.lastPathComponent,
                             "build.frame", "Frame wins within a directory")
            let childPkl = child.appendingPathComponent("build-object.pkl")
            try "child".write(to: childPkl, atomically: true, encoding: .utf8)
            try Expect.equal(try BuildObjectDiscovery.nearestConfiguration(from: child).lastPathComponent,
                             "build-object.pkl", "nearer Pkl wins over farther Frame")
            try Expect.equal(BuildObjectDiscovery.compiledName(for: frame), "compiled.frame", "Frame sidecar")
            try Expect.equal(BuildObjectDiscovery.compiledName(for: legacy), "compiled.pkl", "Pkl sidecar")
        }

        Test("new projects initialize as Frame; existing Pkl projects retain Pkl") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("frame-init-\(UUID().uuidString)", isDirectory: true)
            let modern = root.appendingPathComponent("modern", isDirectory: true)
            let legacy = root.appendingPathComponent("legacy", isDirectory: true)
            try FileManager.default.createDirectory(at: modern, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let created = try BuildObjectLifecycle.initializeEmpty(at: modern)
            try Expect.equal(created.configurationURL.lastPathComponent, "build.frame", "new configuration")
            try Expect.equal(created.compiledURL.lastPathComponent, "compiled.frame", "new sidecar")
            _ = try BuildObjectConfiguration(from: created.configurationURL)
            let ignore = try String(contentsOf: modern.appendingPathComponent(".gitignore"), encoding: .utf8)
            try Expect.true(ignore.contains("/compiled.frame"), "generated state is ignored")
            try BuildObjectConfiguration.new(to: legacy.appendingPathComponent("build-object.pkl"))
            let preserved = try BuildObjectLifecycle.initializeEmpty(at: legacy)
            try Expect.equal(preserved.configurationURL.lastPathComponent, "build-object.pkl", "legacy source")
            try Expect.equal(preserved.compiledURL.lastPathComponent, "compiled.pkl", "legacy sidecar")
            try Expect.equal(preserved.createdConfiguration, false, "no new Frame beside Pkl")
        }

        Test("Primitives build.frame decodes into native build configuration") {
            let configuration = try BuildObjectConfiguration.parseFrame(example)
            try Expect.equal(configuration.uuid.uuidString, "1D096F39-F17E-4C38-A193-04B8A3A5079A", "UUID")
            try Expect.equal(configuration.name, "Primitives", "package name")
            try Expect.equal(configuration.types, [.library], "object types")
            try Expect.equal(configuration.versions.release.major, 0, "major")
            try Expect.equal(configuration.versions.release.minor, 1, "minor")
            try Expect.equal(configuration.versions.release.patch, 0, "patch")
            try Expect.equal(configuration.compile.use, false, "compile toggle")
            try Expect.equal(configuration.compile.arguments, [], "empty arguments")
            try Expect.equal(configuration.tests?.primary, "t_primitives", "declared test product")
        }

        Test("Frame build configuration round-trips with escaped strings and test groups") {
            let original = try BuildObjectConfiguration.parseFrame(example)
            let rendered = try original.frameString()
            let again = try BuildObjectConfiguration.parseFrame(rendered)
            try Expect.equal(again.uuid, original.uuid, "UUID")
            try Expect.equal(again.types, original.types, "types")
            try Expect.equal(again.tests?.primary, original.tests?.primary, "primary")
            try Expect.equal(again.update, original.update, "remote update URL")
            try Expect.equal(again.compile.arguments, original.compile.arguments, "arguments")
        }

        Test("compiled.frame retains release version and exact invocation arguments") {
            let original = CompiledLocalBuildObject(
                version: .init(major: 3, minor: 2, patch: 1),
                arguments: ["--configuration", "release", "a\nb", "quote\"here"]
            )
            let text = try original.frameString()
            let again = try CompiledLocalBuildObject.parseFrame(text)
            try Expect.equal(again.version.major, 3, "major")
            try Expect.equal(again.version.minor, 2, "minor")
            try Expect.equal(again.version.patch, 1, "patch")
            try Expect.equal(again.arguments, original.arguments, "arguments")
        }

        Test("URL dispatch preserves Pkl while recognizing Frame") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("executable-frame-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let frame = directory.appendingPathComponent("build.frame")
            let pkl = directory.appendingPathComponent("build-object.pkl")
            let compiled = directory.appendingPathComponent("compiled.frame")
            let configuration = try BuildObjectConfiguration.parseFrame(example)
            try configuration.write(to: frame)
            try configuration.write(to: pkl)
            try Expect.equal(try BuildObjectConfiguration.parse(from: frame).name, "Primitives", "Frame file")
            try Expect.equal(try BuildObjectConfiguration.parse(from: pkl).name, "Primitives", "Pkl file")
            let state = CompiledLocalBuildObject(version: .init(major: 0, minor: 1, patch: 0), arguments: [])
            try state.write(to: compiled)
            try Expect.equal(try CompiledLocalBuildObject.parse(from: compiled).version.minor, 1, "compiled Frame file")
        }

        Test("the Executable module file describes what build and compiled files hold") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("executable-modules-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = try ExecutableFrame.install(into: directory)
            try Expect.equal(file.lastPathComponent, "Executable.frame", "written by module name")
            let loaded = Frame.Environment.loading(modulesIn: directory)
            try Expect.equal(loaded.failures.count, 0, "the module file reads back")

            let configuration = try BuildObjectConfiguration.parseFrame(example)
            let compiled = CompiledLocalBuildObject(version: .init(major: 1, minor: 2, patch: 3), arguments: ["-c", "release"])
            for (label, source) in [
                ("example", example),
                ("written build", try configuration.frameString()),
                ("written compiled", try compiled.frameString()),
            ] {
                try Expect.equal(
                    Frame.problems(in: try Frame.parse(source), environment: loaded.environment).map(\.message), [],
                    "\(label) passes the module file alone"
                )
            }

            let typo = example
                .replacingOccurrences(of: ".types = [.library]", with: ".types = [.libary]")
                .replacingOccurrences(of: ".primary = \"t_primitives\"", with: ".primry = \"t_primitives\"")
            try Expect.equal(
                Frame.problems(in: try Frame.parse(typo), environment: loaded.environment).map(\.message),
                [
                    "'build.types[0]': unknown member '.libary'; expected .binary, .application, .script, .library, .specification, .resource",
                    "'build.tests': unknown field 'primry'",
                    "'build.tests': missing field 'primary'",
                ],
                "every mistake, by field"
            )
        }

        Test("Frame rejects unknown fields, invalid UUIDs and missing semicolons") {
            try Expect.throwsError("unknown root fields") {
                _ = try BuildObjectConfiguration.parseFrame(example.replacingOccurrences(
                    of: ".details = \"\",", with: ".details = \"\", .unsupported = true,"))
            }
            try Expect.throwsError("invalid UUID") {
                _ = try BuildObjectConfiguration.parseFrame(example.replacingOccurrences(
                    of: "1D096F39-F17E-4C38-A193-04B8A3A5079A", with: "invalid-uuid"))
            }
            try Expect.throwsError("missing terminator") {
                _ = try BuildObjectConfiguration.parseFrame(example.replacingOccurrences(
                    of: "};", with: "}"))
            }
        }
    }
}

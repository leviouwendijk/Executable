import Foundation
import Testing
@_spi(Testing) import Executable

extension ExecutableTestSuite {
    static let wipeSuite = TestSuite(
        "wipe",
        title: "sbm wipe and the keep list",
        tags: ["executable", "wipe", "keep"]
    ) {
        Test("keep.frame entries parse; relative paths and empty packages are rejected") {
            let entries = try KeepList.parse("""
                import Executable;

                // a comment that must survive edits
                let io: Keep = .{ .packages = ["~/main/IO"] };
                let bins: Keep = .{ .packages = ["/x/swiftbins/*"], .caches = ["build"], .reason = "slow" };
                """)
            try Expect.equal(entries.map(\.name), ["io", "bins"])
            try Expect.equal(entries[1].caches, [.build])
            try Expect.equal(entries[1].reason, "slow")
            try Expect.equal(entries[0].caches, Set(KeepEntry.Cache.allCases))

            _ = try Expect.throwsError(KeepError.self) {
                _ = try KeepList.parse("import Executable;\nlet a: Keep = .{ .packages = [\"relative/IO\"] };")
            }
            _ = try Expect.throwsError(KeepError.self) {
                _ = try KeepList.parse("import Executable;\nlet a: Keep = .{ .packages = [] };")
            }
        }

        Test("entries match directories and patterns, resolved through symlinks, with ~ expanded") {
            let fixture = try WipeFixture()
            defer { fixture.remove() }
            let io = try fixture.package("libs/IO")
            let bin = try fixture.package("bins/tool")
            let linked = fixture.root.appendingPathComponent("linked")
            try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: fixture.root.appendingPathComponent("bins"))

            let exact = KeepEntry(name: "io", packages: ["~/libs/IO"])
            try Expect.true(exact.matches(io, home: fixture.root), "~ expands against home")
            try Expect.false(exact.matches(bin, home: fixture.root), "another package does not match")

            let glob = KeepEntry(name: "bins", packages: [fixture.root.path + "/linked/*"])
            try Expect.true(glob.matches(bin, home: fixture.root), "a pattern under a symlinked prefix matches the real path")
            try Expect.false(glob.matches(io, home: fixture.root), "the pattern stays inside its directory")

            let deep = KeepEntry(name: "all", packages: [fixture.root.path + "/**/IO"])
            try Expect.true(deep.matches(io, home: fixture.root), "** spans directories")
        }

        Test("keep add appends one binding; keep rm removes only that binding") {
            let original = """
                import Executable;

                // a comment that must survive edits
                let io: Keep = .{ .packages = ["~/main/IO"] };

                // trailing note
                """
            let entry = KeepEntry(name: "swiftbins", packages: ["~/bins/*"], caches: [.build], reason: "slow \"full\" rebuilds")
            let added = KeepList.adding(entry, to: original)
            let parsed = try KeepList.parse(added)
            try Expect.equal(parsed.map(\.name), ["io", "swiftbins"])
            try Expect.equal(parsed[1].reason, "slow \"full\" rebuilds", "reason is escaped and round-trips")
            try Expect.true(added.hasPrefix(original), "everything before the new binding is untouched")

            let removed = try KeepList.removing("io", from: added)
            try Expect.equal(try KeepList.parse(removed).map(\.name), ["swiftbins"])
            try Expect.true(removed.contains("// a comment that must survive edits"), "comments stay")
            try Expect.true(removed.contains("// trailing note"), "later lines stay")
            try Expect.false(removed.contains("let io"), "the binding's line is gone")

            let fresh = KeepList.adding(KeepEntry(name: "io", packages: ["/x/IO"]), to: nil)
            try Expect.equal(try KeepList.parse(fresh).map(\.name), ["io"], "a new file gets the import header")
            _ = try Expect.throwsError(KeepError.self) { _ = try KeepList.removing("missing", from: fresh) }

            try Expect.equal(KeepList.defaultName(for: "~/main/libs/IO"), "io")
            try Expect.equal(KeepList.defaultName(for: "~/main/swift-bins/*"), "swift_bins")
        }

        Test("a package plan covers nested Tests/ and Benchmarks/, keep, running builds and leftovers") {
            let fixture = try WipeFixture()
            defer { fixture.remove() }
            let package = try fixture.package("IO", caches: [".build", ".index-build", ".build.clean-1-2"])
            _ = try fixture.package("IO/Tests", caches: [".build"])
            _ = try fixture.package("IO/Benchmarks", caches: [".build", ".index-build"])
            _ = try fixture.directory("IO/Sources/IO")

            let keep = KeepList(entries: [KeepEntry(name: "bench", packages: [package.path + "/Benchmarks"], caches: [.index])])
            let tests = package.appendingPathComponent("Tests/.build").standardizedFileURL
            let holder = SwiftPMBuildLock.Holder(pid: 42, executable: "swift-build")
            let plan = try Wipe.plan(.init(root: package, measure: true), keep: keep) { directory in
                directory.standardizedFileURL.path == FileManager.default.resolvingPath(tests) ? holder : nil
            }

            try Expect.equal(plan.packages.map(\.lastPathComponent), ["IO", "Tests", "Benchmarks"])
            try Expect.equal(plan.leftovers.map(\.directory.lastPathComponent), [".build.clean-1-2"])
            func decision(_ path: String) -> Wipe.Decision? {
                plan.items.first { $0.directory.path.hasSuffix(path) }?.decision
            }
            try Expect.equal(decision("IO/.build"), .delete)
            try Expect.equal(decision("IO/.index-build"), .delete)
            try Expect.equal(decision("Tests/.build"), .running(holder), "a running build is never deleted under")
            try Expect.equal(decision("Benchmarks/.build"), .delete, "a keep entry for index leaves build to delete")
            try Expect.equal(decision("Benchmarks/.index-build"), .kept(entry: "bench", reason: nil))
            try Expect.true(plan.measuredTotal > 0, "measured plans size their deletions")

            let ignored = try Wipe.plan(.init(root: package, ignoreKeep: true), keep: keep) { _ in nil }
            try Expect.true(ignored.items.allSatisfy { $0.decision == .delete }, "--ignore-keep deletes kept caches")

            _ = try Expect.throwsError(WipeError.self) {
                _ = try Wipe.plan(.init(root: package.appendingPathComponent("Sources")), keep: keep) { _ in nil }
            }
        }

        Test("-r finds packages by depth and skips caches, .git and dot-directories") {
            let fixture = try WipeFixture()
            defer { fixture.remove() }
            _ = try fixture.package("a", caches: [".build"])
            _ = try fixture.package("a/Tests", caches: [".build"])
            _ = try fixture.package("group/b", caches: [".build"])
            _ = try fixture.package("a/.build/checkouts/dep")
            _ = try fixture.package(".hidden/c")

            let all = try Wipe.plan(.init(root: fixture.root, recursive: true), keep: KeepList()) { _ in nil }
            try Expect.equal(all.packages.map { $0.path.replacingOccurrences(of: FileManager.default.resolvingPath(fixture.root) + "/", with: "") },
                             ["a", "a/Tests", "group/b"])

            let shallow = try Wipe.plan(.init(root: fixture.root, recursive: true, depth: 1), keep: KeepList()) { _ in nil }
            try Expect.equal(shallow.packages.map(\.lastPathComponent), ["a"])
        }

        Test("main and extra split a package; extra needs package.frame to confirm Tests/ and Benchmarks/") {
            let fixture = try WipeFixture()
            defer { fixture.remove() }
            let package = try fixture.package("IO", caches: [".build"])
            let tests = try fixture.package("IO/Tests", caches: [".build"])
            let benchmarks = try fixture.package("IO/Benchmarks", caches: [".build"])
            try "import Executable;\nlet tests: Tests = .{};\n".write(to: tests.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8)
            try "import Executable;\nlet benchmarks: Benchmarks = .{};\n".write(to: benchmarks.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8)
            _ = try fixture.package("other/Tests", caches: [".build"])

            func names(_ scope: Wipe.Scope, recursive: Bool = false, root: URL? = nil) throws -> [String] {
                try Wipe.plan(.init(root: root ?? package, scope: scope, recursive: recursive), keep: KeepList()) { _ in nil }
                    .packages.map { $0.path.replacingOccurrences(of: FileManager.default.resolvingPath(fixture.root) + "/", with: "") }
            }
            try Expect.equal(try names(.all), ["IO", "IO/Tests", "IO/Benchmarks"])
            try Expect.equal(try names(.main), ["IO"])
            try Expect.equal(try names(.extra), ["IO/Tests", "IO/Benchmarks"])
            try Expect.equal(try names(.extra, recursive: true, root: fixture.root), ["IO/Benchmarks", "IO/Tests"],
                             "a Tests/ without package.frame saying tests is not wiped by extra")
            try Expect.equal(try names(.main, recursive: true, root: fixture.root), ["IO", "other/Tests"])
        }

        Test("sizes parse in binary units; anything else is rejected") {
            try Expect.equal(try ByteCount("2G").bytes, 2 << 30)
            try Expect.equal(try ByteCount("500m").bytes, 500 << 20)
            try Expect.equal(try ByteCount("1.5GiB").bytes, 3 << 29)
            try Expect.equal(try ByteCount("2GB").bytes, 2 << 30)
            try Expect.equal(try ByteCount("4096").bytes, 4096)
            try Expect.equal(try ByteCount("2G").raw, "2G", "the raw value is kept as written")
            for bad in ["", "G", "-1G", "2X", "two"] {
                try Expect.true((try? ByteCount(bad)) == nil, "'\(bad)' is rejected")
            }
        }

        Test(".wipe.above parses in all three kinds, round-trips, and rejects a bad size") {
            let package = try PackageFrame.parse("import Executable;\nlet package: Package = .{ .wipe = .{ .above = \"2G\" } };")
            try Expect.equal(package, .package(.init(wipe: .init(above: try ByteCount("2G")))))
            let tests = try PackageFrame.parse("import Executable;\nlet tests: Tests = .{ .primary = \"t_x\", .wipe = .{ .above = \"500M\" } };")
            try Expect.equal(tests, .tests(.init(primary: "t_x", wipe: .init(above: try ByteCount("500M")))))
            let benchmarks = try PackageFrame.parse("import Executable;\nlet benchmarks: Benchmarks = .{ .wipe = .{ .above = \"1G\" } };")
            try Expect.equal(benchmarks, .benchmarks(.init(wipe: .init(above: try ByteCount("1G")))))

            let written = try PackageFrame.source(PackageConfiguration(wipe: .init(above: try ByteCount("3G"))))
            try Expect.true(written.contains("\"3G\""), "the size is written as given")
            try Expect.equal(try PackageFrame.parse(written), .package(.init(wipe: .init(above: try ByteCount("3G")))))

            _ = try Expect.throwsError(Error.self) {
                _ = try PackageFrame.parse("import Executable;\nlet package: Package = .{ .wipe = .{ .above = \"lots\" } };")
            }
        }

        Test("after a run, caches over .wipe.above are wiped and caches under it stay") {
            let fixture = try WipeFixture()
            defer { fixture.remove() }
            let small = try fixture.package("small", caches: [".build"])
            let large = try fixture.package("large", caches: [".build", ".index-build"])
            try Data(repeating: 1, count: 2 << 20).write(to: large.appendingPathComponent(".build/blob"))
            for package in [small, large] {
                try "import Executable;\nlet package: Package = .{ .wipe = .{ .above = \"1M\" } };\n"
                    .write(to: package.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8)
            }
            let none = try fixture.package("none", caches: [".build"])
            try Data(repeating: 1, count: 2 << 20).write(to: none.appendingPathComponent(".build/blob"))

            try await SwiftBuildSteps.tidyAfter([small, large, none], clean: false, wipe: false)

            try Expect.true(FileManager.default.fileExists(atPath: small.appendingPathComponent(".build").path), "under the threshold stays")
            try Expect.false(FileManager.default.fileExists(atPath: large.appendingPathComponent(".build").path), "over the threshold is wiped")
            try Expect.false(FileManager.default.fileExists(atPath: large.appendingPathComponent(".index-build").path), "both caches count and go")
            try Expect.true(FileManager.default.fileExists(atPath: none.appendingPathComponent(".build").path), "no policy, no wipe")
        }

        Test("remove detaches then deletes; the cache name is free again") {
            let fixture = try WipeFixture()
            defer { fixture.remove() }
            let package = try fixture.package("p", caches: [".build"])
            try Data(repeating: 1, count: 4096).write(to: package.appendingPathComponent(".build/blob"))
            let plan = try Wipe.plan(.init(root: package), keep: KeepList()) { _ in nil }

            for item in plan.deletions {
                try await Wipe.remove(item)
            }
            let left = try FileManager.default.contentsOfDirectory(atPath: package.path)
            try Expect.equal(left.sorted(), ["Package.swift"], "no .build and no detached leftovers remain")
        }

        Test("the SwiftPM lock counts only a live SwiftPM process") {
            let fixture = try WipeFixture()
            defer { fixture.remove() }
            let build = try fixture.directory("p/.build")
            try Expect.equal(SwiftPMBuildLock.holder(of: build), nil, "no lock file")
            try "999999".write(to: build.appendingPathComponent(".lock"), atomically: true, encoding: .utf8)
            try Expect.equal(SwiftPMBuildLock.holder(of: build), nil, "a dead pid is a stale lock")
            try "\(getpid())".write(to: build.appendingPathComponent(".lock"), atomically: true, encoding: .utf8)
            try Expect.equal(SwiftPMBuildLock.holder(of: build), nil, "a live pid that is not SwiftPM is a reused pid")
        }
    }
}

private struct WipeFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func package(_ path: String, caches: [String] = []) throws -> URL {
        let url = try directory(path)
        try "// swift-tools-version: 6.2\n".write(to: url.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        for cache in caches {
            _ = try directory("\(path)/\(cache)")
            try "x".write(to: url.appendingPathComponent("\(cache)/file"), atomically: true, encoding: .utf8)
        }
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private extension FileManager {
    func resolvingPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

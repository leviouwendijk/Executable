import Arguments
import Foundation
import IO

/// What runs around a build, test or benchmark run, so disk space is managed from the command
/// itself: `sbm -t --wipe`, `sbm test --wipe`, `sbm build --clean-before`, `sbm pack -b -t --bench`.
///
/// Before: `--wipe-before` or `--clean-before`, then (build and pack) the tests, so a failing
/// test stops the build and deploy. After: (build and pack) the benchmarks, then `--wipe` or
/// `--clean`. A wipe makes a clean at the same moment unnecessary, so `--clean --wipe` only
/// wipes. Each command tidies the packages it worked in: build the root (plus Tests/ with -t,
/// Benchmarks/ with --bench), test the Tests/ package, bench the Benchmarks/ package. The keep
/// list applies (`sbm keep`). After-steps run only when the command succeeded. Without
/// `--wipe`, a package whose package.frame says `.wipe = .{ .above = "2G" }` is wiped after a
/// successful run when its caches exceed that size.
public struct SwiftBuildSteps: Sendable, Equatable {
    /// Flags that choose what runs around the build, not how it builds, so they don't count as
    /// explicit build input: `sbm -t --wipe` still builds the way package.frame says.
    static let flagNames: Set<ParamName> = [
        "test", "bench", "build", "clean", "wipe", "clean-before", "wipe-before",
    ]

    public var test: Bool
    public var bench: Bool
    public var cleanBefore: Bool
    public var wipeBefore: Bool
    public var clean: Bool
    public var wipe: Bool

    public init(
        test: Bool = false,
        bench: Bool = false,
        cleanBefore: Bool = false,
        wipeBefore: Bool = false,
        clean: Bool = false,
        wipe: Bool = false
    ) {
        self.test = test
        self.bench = bench
        self.cleanBefore = cleanBefore
        self.wipeBefore = wipeBefore
        self.clean = clean
        self.wipe = wipe
    }

    /// Before a build of `project`: tidy, then the tests.
    public func before(at project: URL) async throws {
        try await Self.tidy(packages(of: project), clean: cleanBefore, wipe: wipeBefore)
        guard test else { return }
        try await SwiftTestCommand.run(at: project, selection: .primary, kind: .tests)
    }

    /// After a build of `project`: the benchmarks, then tidy.
    public func after(at project: URL) async throws {
        if bench {
            try await SwiftTestCommand.run(at: project, selection: .primary, kind: .benchmarks)
        }
        try await Self.tidyAfter(packages(of: project), clean: clean, wipe: wipe)
    }

    /// The root, and the nested packages this run uses.
    func packages(of project: URL) -> [URL] {
        let layout = PackageLayout()
        let nested = [(test, layout.tests), (bench, layout.benchmarks)]
            .filter(\.0)
            .map { PackageLayout.url($0.1.root, in: project) }
            .filter { FileSystem.default.exists($0.appendingPathComponent("Package.swift")) }
        return [project] + nested
    }

    func with(_ tidy: SwiftTidyOptions) -> Self {
        var steps = self
        steps.cleanBefore = tidy.cleanBefore
        steps.wipeBefore = tidy.wipeBefore
        steps.clean = tidy.clean
        steps.wipe = tidy.wipe
        return steps
    }

    /// After a successful run: `--wipe`, or else each package's own `.wipe = .{ .above = … }`
    /// when its caches have grown past it, then `--clean` for what wasn't wiped.
    @_spi(Testing) public static func tidyAfter(_ packages: [URL], clean: Bool, wipe: Bool) async throws {
        guard !wipe else {
            try await tidy(packages, clean: false, wipe: true)
            return
        }
        var wiped: [URL] = []
        for package in packages {
            guard let policy = try? PackageFrame.wipe(in: package) else { continue }
            if try await wipeAbove(policy.above, package: package) {
                wiped.append(package)
            }
        }
        try await tidy(packages.filter { !wiped.contains($0) }, clean: clean, wipe: false)
    }

    /// Measures the package's caches and wipes them when they exceed `above`. One walk.
    static func wipeAbove(_ above: ByteCount, package: URL) async throws -> Bool {
        let plan = try Wipe.plan([package], root: package, keep: KeepList.load(), measure: true)
        let total = plan.measuredTotal
        let name = package.lastPathComponent
        guard total > above.bytes else {
            print("\(name): caches \(total.humanBytes), within .wipe.above \(above.raw)")
            return false
        }
        print("\(name): caches \(total.humanBytes) exceed .wipe.above \(above.raw) (package.frame); wiping")
        try await SwiftWipePackageCommand.execute(plan, dryRun: false, interactive: false)
        return true
    }

    static func tidy(_ packages: [URL], clean: Bool, wipe: Bool) async throws {
        guard let root = packages.first else { return }
        if wipe {
            let plan = try Wipe.plan(packages, root: root, keep: KeepList.load())
            try await SwiftWipePackageCommand.execute(plan, dryRun: false, interactive: false)
        } else if clean {
            for package in packages {
                try await Build.clean(at: package)
            }
        }
    }
}

/// `--clean`, `--wipe`, `--clean-before`, `--wipe-before`: the same four flags on build, test,
/// bench and pack.
public struct SwiftTidyOptions: ArgumentGroup {
    @Flag("clean", help: "swift package clean afterwards.")
    public var clean: Bool

    @Flag("wipe", help: "Delete .build and .index-build afterwards (keep list applies); replaces --clean.")
    public var wipe: Bool

    @Flag("clean-before", help: "swift package clean first.")
    public var cleanBefore: Bool

    @Flag("wipe-before", help: "Delete .build and .index-build first, for a fresh build; replaces --clean-before.")
    public var wipeBefore: Bool

    public init() {}
}

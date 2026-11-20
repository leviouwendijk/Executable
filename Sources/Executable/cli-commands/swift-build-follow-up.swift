import Arguments
import Foundation

/// Tests and benchmarks around a build: `sbm -t`, `sbm build -t -b`, `sbm pack -b -t --bench`.
/// The meaning lives here; each command declares the flags, because their short forms differ
/// (`-b` is bench on build but build on pack).
///
/// Tests run before the build, so a failing test stops the deploy. Benchmarks run after it,
/// in release, like `sbm bench`. Both run their package's primary products.
public struct SwiftBuildFollowUp: Sendable, Equatable {
    /// The long flag names. They choose what runs around the build, not how it builds, so they
    /// don't count as explicit build input: `sbm -t` still applies package.frame.
    static let flagNames: Set<ParamName> = ["test", "bench"]

    public var test: Bool
    public var bench: Bool

    public init(test: Bool = false, bench: Bool = false) {
        self.test = test
        self.bench = bench
    }

    public func before(at project: URL) async throws {
        guard test else { return }
        try await SwiftTestCommand.run(at: project, selection: .primary, kind: .tests)
    }

    public func after(at project: URL) async throws {
        guard bench else { return }
        try await SwiftTestCommand.run(at: project, selection: .primary, kind: .benchmarks)
    }
}

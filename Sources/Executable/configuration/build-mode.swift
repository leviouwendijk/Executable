import Frame

/// `.mode` in package.frame. Without it a package builds in release, tests run in debug and
/// benchmarks in release.
public enum BuildMode: String, Codable, Sendable, CaseIterable, FrameDescribable {
    case debug
    case release

    public var config: Build.Config.Mode {
        self == .debug ? .debug : .release
    }
}

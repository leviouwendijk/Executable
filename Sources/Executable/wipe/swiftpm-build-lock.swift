import Foundation
import IO
import Readers

#if canImport(Darwin)
import Darwin
#endif

/// Whether SwiftPM is working in a `.build` directory right now.
///
/// SwiftPM (6.3) writes its pid into `.build/.lock` while it runs and leaves the file behind
/// afterwards, without holding an OS lock on it. So the file alone says nothing: the pid must
/// still be alive and still be a SwiftPM executable (a reused pid is something else).
/// One read, one `kill(pid, 0)`, one `proc_pidpath`.
public enum SwiftPMBuildLock {
    public struct Holder: Sendable, Equatable {
        public let pid: Int32
        public let executable: String

        public init(pid: Int32, executable: String) {
            self.pid = pid
            self.executable = executable
        }
    }

    static let executables: Set<String> = ["swift-build", "swift-package", "swift-run", "swift-test", "swift"]

    public static func holder(of buildDirectory: URL) -> Holder? {
        let lock = buildDirectory.appendingPathComponent(".lock")
        guard FileSystem.default.exists(lock),
              let text = try? TextFileReader(lock).read().text,
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0
        else { return nil }
        guard let executable = executable(of: pid), executables.contains(executable) else { return nil }
        return .init(pid: pid, executable: executable)
    }

    /// The executable name of a live process; nil when it is gone.
    static func executable(of pid: Int32) -> String? {
        guard kill(pid, 0) == 0 || errno == EPERM else { return nil }
        #if canImport(Darwin)
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path).lastPathComponent
        #else
        return FileSystem.default.resolve(URL(fileURLWithPath: "/proc/\(pid)/exe")).lastPathComponent
        #endif
    }
}

import Foundation
import Interfaces
#if canImport(AppKit)
import AppKit
#endif

public struct ProcessEvaluator: Sendable {
    public struct Options: Sendable {
        public var launchEvenIfNotRunning: Bool

        public var graceMicroseconds: useconds_t
        public init(launchEvenIfNotRunning: Bool = false, graceMicroseconds: useconds_t = 200_000) {
            self.launchEvenIfNotRunning = launchEvenIfNotRunning
            self.graceMicroseconds = graceMicroseconds
        }
    }
    
    public init() {}
    
    public func relaunch(
        _ directoryURL: URL,
        target: String? = nil,
        options: Options = .init()
    ) async throws {
        let resolved = try AppBundleResolver().resolve(directoryURL: directoryURL, target: target)
        
        var didTerminate = false
        #if canImport(AppKit)
        if let bid = resolved.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if !running.isEmpty {
                print("    [RUNNING] \(bid) → \(running.map { String($0.processIdentifier) }.joined(separator: ","))")
                for app in running { _ = app.terminate() }
                for app in running {
                    if app.isTerminated == false {
                        usleep(options.graceMicroseconds)
                        if app.isTerminated == false {
                            _ = app.forceTerminate()
                        }
                    }
                }
                didTerminate = true
                print("    [STOPPED] \(bid)")
            } else {
                print("    [NOT RUNNING] \(bid)")
            }
        } else {
            print("    [INFO] No bundle identifier; using CLI fallbacks.")
        }
        #else
        #endif
        
        // fallback stop path: pgrep/killall by exec name or -f bundle path
        if didTerminate == false {
            var opt = Shell.Options(); opt.cwd = directoryURL
            
            let p1 = try? await Shell(.path("/usr/bin/pgrep"))
                .run("/usr/bin/pgrep", ["-x", resolved.executableName], options: opt)
            let pidText = p1?.stdoutText().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let exactHit = (p1?.exitCode == 0) && !pidText.isEmpty
            
            print("    [CHECK pgrep -x] \(exactHit ? "\(resolved.executableName) \(pidText)" : "(no exact name match)")")
            
            if exactHit {
                _ = try? await Shell(.path("/usr/bin/killall"))
                    .run("/usr/bin/killall", ["-TERM", resolved.executableName], options: opt)
                print("    [STOPPED] \(resolved.executableName)")
                didTerminate = true
            } else {
                let p2 = try? await Shell(.path("/usr/bin/pgrep"))
                    .run("/usr/bin/pgrep", ["-f", resolved.appBundleURL.path], options: opt)
                let pid2 = p2?.stdoutText().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if (p2?.exitCode == 0) && !pid2.isEmpty {
                    print("    [CHECK pgrep -f] \(pid2)")
                    _ = try? await Shell(.path("/usr/bin/killall"))
                        .run("/usr/bin/killall", ["-TERM", resolved.executableName], options: opt)
                    print("    [STOPPED] \(resolved.executableName)")
                    didTerminate = true
                } else {
                    print("    [NOT RUNNING] \(resolved.executableName)")
                }
            }
        }
        
        if didTerminate || options.launchEvenIfNotRunning {
            var optOpen = Shell.Options(); optOpen.cwd = directoryURL
            _ = try await Shell(.path("/usr/bin/open"))
                .run("/usr/bin/open", [resolved.appBundleURL.path], options: optOpen)
            print("    [RE-LAUNCHED] \(resolved.appBundleURL.lastPathComponent)".ansi(.green))
        }
    }
}

// import Foundation
// import Interfaces
// // import plate
// import Darwin
// import Indentation

// public struct SwiftPMProcess: Sendable, Hashable {
//     public let pid: pid_t
//     public let commandLine: String

//     public init(pid: pid_t, commandLine: String) {
//         self.pid = pid
//         self.commandLine = commandLine
//     }
// }

// public enum SwiftPMProcessError: Swift.Error, LocalizedError, Sendable {
//     case failedToParsePID(String)
//     case killFailed(pid: pid_t, signal: Int32, errno: Int32)

//     public var errorDescription: String? {
//         switch self {
//         case .failedToParsePID(let raw):
//             return "Failed to parse PID from line: \(raw)"
//         case .killFailed(let pid, let signal, let err):
//             return "kill(\(pid), \(signal)) failed with errno=\(err)"
//         }
//     }
// }

// public struct SwiftPMProcesses: Sendable {
//     public init() {}

//     /// Discover running Swift / SwiftPM-related processes.
//     public func list(
//         cwd overrideCWD: URL? = nil
//     ) async throws -> [SwiftPMProcess] {
//         let cwd = overrideCWD ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

//         let result = try await sh(
//             .zsh,
//             "ps",
//             ["ax", "-o", "pid=,command="],
//             cwd: cwd
//         )

//         let text = result.stdoutText()
//         var processes: [SwiftPMProcess] = []

//         for rawLine in text.split(whereSeparator: \.isNewline) {
//             let line = rawLine.trimmingCharacters(in: .whitespaces)
//             guard !line.isEmpty else { continue }

//             let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
//             guard let pidPart = parts.first else { continue }
//             let cmdPart = parts.count > 1 ? String(parts[1]) : ""

//             guard let pidInt = Int32(pidPart) else {
//                 continue
//             }

//             guard Self.isSwiftPMCommandLine(cmdPart) else { continue }

//             processes.append(
//                 SwiftPMProcess(
//                     pid: pidInt,
//                     commandLine: cmdPart
//                 )
//             )
//         }

//         return processes
//     }

//     /// Kill a single SwiftPM process.
//     /// If `dryRun` is true, only logs what *would* be done, no signal is sent.
//     public func kill(
//         _ process: SwiftPMProcess,
//         force: Bool = false,
//         dryRun: Bool = false
//     ) throws {
//         let signal: Int32 = force ? SIGKILL : SIGTERM
//         let sigName = force ? "SIGKILL" : "SIGTERM"

//         if dryRun {
//             printi("[dry-run] Would send \(sigName) to pid \(process.pid) – \(process.commandLine)")
//             return
//         }

//         let r = Darwin.kill(process.pid, signal)
//         if r != 0 {
//             throw SwiftPMProcessError.killFailed(
//                 pid: process.pid,
//                 signal: signal,
//                 errno: errno
//             )
//         }

//         printi("Sent \(sigName) to pid \(process.pid) – \(process.commandLine)")
//     }

//     /// Kill all discovered SwiftPM processes.
//     /// Returns the list of processes it inspected.
//     /// If `dryRun` is true, no signals are sent; only prints what it would kill.
//     @discardableResult
//     public func killAll(
//         force: Bool = false,
//         dryRun: Bool = false,
//         cwd overrideCWD: URL? = nil
//     ) async throws -> [SwiftPMProcess] {
//         let procs = try await list(cwd: overrideCWD)
//         if procs.isEmpty {
//             printi("No SwiftPM processes detected.")
//             return []
//         }

//         let sigName = force ? "SIGKILL" : "SIGTERM"
//         if dryRun {
//             printi("Dry run: found \(procs.count) SwiftPM processes. Would send \(sigName) to:")
//         } else {
//             printi("Found \(procs.count) SwiftPM processes. Sending \(sigName)…")
//         }

//         for p in procs {
//             do {
//                 try kill(p, force: force, dryRun: dryRun)
//             } catch {
//                 printi("Failed to kill pid \(p.pid): \(error)")
//             }
//         }

//         return procs
//     }

//     private static func isSwiftPMCommandLine(_ cmd: String) -> Bool {
//         guard !cmd.isEmpty else { return false }

//         let tokens = cmd.split(whereSeparator: { $0 == " " || $0 == "\t" })
//         guard let firstToken = tokens.first else { return false }

//         let binaryName = String(firstToken.split(separator: "/").last ?? firstToken)

//         guard binaryName == "swift" || binaryName.hasPrefix("swift-") else {
//             return false
//         }

//         if binaryName == "swift" {
//             if tokens.count >= 2 {
//                 let sub = tokens[1].lowercased()
//                 let pmSubcommands: Set<String> = ["build", "test", "package", "run"]
//                 if pmSubcommands.contains(sub) {
//                     return true
//                 }
//             }
//             return false
//         }

//         if binaryName.hasPrefix("swift-") {
//             return true
//         }

//         return false
//     }
// }


import Foundation
import Interfaces
import Darwin
import Indentation

public struct SwiftPMProcess: Sendable, Hashable {
    public let pid: pid_t
    public let commandLine: String

    public init(pid: pid_t, commandLine: String) {
        self.pid = pid
        self.commandLine = commandLine
    }
}

public enum SwiftPMProcessError: Swift.Error, LocalizedError, Sendable {
    case failedToParsePID(String)
    case killFailed(pid: pid_t, signal: Int32, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .failedToParsePID(let raw):
            return "Failed to parse PID from line: \(raw)"
        case .killFailed(let pid, let signal, let err):
            return "kill(\(pid), \(signal)) failed with errno=\(err)"
        }
    }
}

public struct SwiftPMProcesses: Sendable {
    public init() {}

    private struct ProcRow: Sendable, Hashable {
        let pid: pid_t
        let ppid: pid_t
        let command: String
    }

    private func snapshot(cwd: URL) async throws -> [ProcRow] {
        let result = try await sh(
            .zsh,
            "ps",
            ["ax", "-o", "pid=,ppid=,command="],
            cwd: cwd
        )

        let text = result.stdoutText()
        var rows: [ProcRow] = []
        rows.reserveCapacity(256)

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Expect: "<pid> <ppid> <command...>"
            let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }

            guard let pidInt = Int32(parts[0]), let ppidInt = Int32(parts[1]) else { continue }
            let cmd = parts.count >= 3 ? String(parts[2]) : ""

            rows.append(.init(pid: pidInt, ppid: ppidInt, command: cmd))
        }

        return rows
    }

    public func list(
        cwd overrideCWD: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let cwd = overrideCWD ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let rows = try await snapshot(cwd: cwd)

        return rows.compactMap { row in
            guard Self.isSwiftPMCommandLine(row.command) else { return nil }
            return SwiftPMProcess(pid: row.pid, commandLine: row.command)
        }
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        errno = 0
        let r = Darwin.kill(pid, 0)
        if r == 0 { return true }
        return errno != ESRCH
    }

    private func killPID(_ pid: pid_t, command: String, signal: Int32, sigName: String, dryRun: Bool) throws {
        if dryRun {
            printi("[dry-run] Would send \(sigName) to pid \(pid) – \(command)")
            return
        }

        errno = 0
        let r = Darwin.kill(pid, signal)
        if r != 0 {
            throw SwiftPMProcessError.killFailed(pid: pid, signal: signal, errno: errno)
        }

        printi("Sent \(sigName) to pid \(pid) – \(command)")
    }

    private func descendants(of root: pid_t, childrenByParent: [pid_t: [pid_t]]) -> [pid_t] {
        // Post-order: children first, then parent
        var visited = Set<pid_t>()
        var order: [pid_t] = []

        func dfs(_ pid: pid_t) {
            if visited.contains(pid) { return }
            visited.insert(pid)

            for c in childrenByParent[pid, default: []] {
                dfs(c)
            }

            order.append(pid)
        }

        dfs(root)
        return order
    }

    @discardableResult
    public func killAll(
        force: Bool = false,
        dryRun: Bool = false,
        cwd overrideCWD: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let cwd = overrideCWD ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let rows = try await snapshot(cwd: cwd)

        let matchedRoots = rows.filter { Self.isSwiftPMCommandLine($0.command) }
        if matchedRoots.isEmpty {
            printi("No SwiftPM processes detected.")
            return []
        }

        // Build parent -> children map from the SAME snapshot
        var childrenByParent: [pid_t: [pid_t]] = [:]
        childrenByParent.reserveCapacity(256)
        for r in rows {
            childrenByParent[r.ppid, default: []].append(r.pid)
        }

        let signal: Int32 = force ? SIGKILL : SIGTERM
        let sigName = force ? "SIGKILL" : "SIGTERM"

        printi("Found \(matchedRoots.count) SwiftPM roots. Killing process trees with \(sigName)…")

        // Kill each root’s subtree (children-first)
        for root in matchedRoots {
            let subtree = descendants(of: root.pid, childrenByParent: childrenByParent)

            for pid in subtree {
                // If already gone, skip
                if !isAlive(pid) { continue }

                // Lookup command for nicer logs
                let cmd = rows.first(where: { $0.pid == pid })?.command ?? root.command

                do {
                    try killPID(pid, command: cmd, signal: signal, sigName: sigName, dryRun: dryRun)
                } catch {
                    printi("Failed to kill pid \(pid): \(error)")
                }
            }
        }

        return matchedRoots.map { SwiftPMProcess(pid: $0.pid, commandLine: $0.command) }
    }

    private static func isSwiftPMCommandLine(_ cmd: String) -> Bool {
        guard !cmd.isEmpty else { return false }

        let tokens = cmd.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let firstToken = tokens.first else { return false }

        let binaryName = String(firstToken.split(separator: "/").last ?? firstToken)

        // Keep your existing behavior:
        guard binaryName == "swift" || binaryName.hasPrefix("swift-") else {
            return false
        }

        if binaryName == "swift" {
            if tokens.count >= 2 {
                let sub = tokens[1].lowercased()
                let pmSubcommands: Set<String> = ["build", "test", "package", "run"]
                return pmSubcommands.contains(sub)
            }
            return false
        }

        if binaryName.hasPrefix("swift-") {
            return true
        }

        return false
    }
}

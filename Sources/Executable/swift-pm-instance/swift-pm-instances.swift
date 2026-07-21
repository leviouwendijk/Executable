import Darwin
import Foundation
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
    case processSnapshotFailed(exitCode: Int32, stderr: String)
    case killFailed(pid: pid_t, signal: Int32, errno: Int32)
    case processesSurvived([SwiftPMProcess])

    public var errorDescription: String? {
        switch self {
        case .processSnapshotFailed(let exitCode, let stderr):
            return """
            Failed to inspect running processes.
            ps exited with \(exitCode): \(stderr)
            """

        case .killFailed(let pid, let signal, let errorNumber):
            return """
            kill(\(pid), \(signal)) failed with errno \(errorNumber): \
            \(String(cString: strerror(errorNumber)))
            """

        case .processesSurvived(let processes):
            let rendered = processes
                .map { "pid \($0.pid) – \($0.commandLine)" }
                .joined(separator: "\n")

            return """
            SwiftPM processes survived termination:
            \(rendered.indent())
            """
        }
    }
}

public struct SwiftPMProcesses: Sendable {
    private static let gracefulTerminationNanoseconds: UInt64 = 1_500_000_000
    private static let forcedTerminationNanoseconds: UInt64 = 500_000_000

    public init() {}

    private struct ProcRow: Sendable, Hashable {
        let pid: pid_t
        let ppid: pid_t
        let command: String
    }

    public func list(
        cwd overrideCWD: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let rows = try snapshot()

        return rows.compactMap { row in
            guard Self.isSwiftPMCommandLine(row.command) else {
                return nil
            }

            return SwiftPMProcess(
                pid: row.pid,
                commandLine: row.command
            )
        }
    }

    @discardableResult
    public func killAll(
        force: Bool = false,
        dryRun: Bool = false,
        cwd overrideCWD: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let initialRows = try snapshot()
        let matchedRoots = initialRows.filter {
            Self.isSwiftPMCommandLine($0.command)
        }

        guard !matchedRoots.isEmpty else {
            printi("No SwiftPM processes detected.")
            return []
        }

        let matchedProcesses = matchedRoots.map {
            SwiftPMProcess(
                pid: $0.pid,
                commandLine: $0.command
            )
        }

        let childrenByParent = makeChildrenByParent(from: initialRows)
        let processByPID = Dictionary(
            uniqueKeysWithValues: initialRows.map {
                ($0.pid, $0)
            }
        )

        let orderedPIDs = orderedProcessTreePIDs(
            roots: matchedRoots.map(\.pid),
            childrenByParent: childrenByParent
        )

        if dryRun {
            let signalName = force ? "SIGKILL" : "SIGTERM followed by SIGKILL"

            printi(
                "Found \(matchedRoots.count) SwiftPM roots. " +
                "Would terminate \(orderedPIDs.count) processes using \(signalName):"
            )

            for pid in orderedPIDs {
                let command = processByPID[pid]?.command ?? "<unknown>"
                printi("pid \(pid) – \(command)".indent())
            }

            return matchedProcesses
        }

        if force {
            printi(
                "Found \(matchedRoots.count) SwiftPM roots. " +
                "Killing \(orderedPIDs.count) processes with SIGKILL…"
            )

            try signal(
                orderedPIDs,
                signal: SIGKILL,
                signalName: "SIGKILL",
                processByPID: processByPID
            )

            try await Task.sleep(
                nanoseconds: Self.forcedTerminationNanoseconds
            )
        } else {
            printi(
                "Found \(matchedRoots.count) SwiftPM roots. " +
                "Terminating \(orderedPIDs.count) processes…"
            )

            try signal(
                orderedPIDs,
                signal: SIGTERM,
                signalName: "SIGTERM",
                processByPID: processByPID
            )

            try await Task.sleep(
                nanoseconds: Self.gracefulTerminationNanoseconds
            )

            let survivors = orderedPIDs.filter(isAlive)

            if !survivors.isEmpty {
                printi(
                    "\(survivors.count) processes ignored SIGTERM. " +
                    "Escalating to SIGKILL…"
                )

                try signal(
                    survivors,
                    signal: SIGKILL,
                    signalName: "SIGKILL",
                    processByPID: processByPID
                )

                try await Task.sleep(
                    nanoseconds: Self.forcedTerminationNanoseconds
                )
            }
        }

        let survivors = orderedPIDs
            .filter(isAlive)
            .map { pid in
                SwiftPMProcess(
                    pid: pid,
                    commandLine: processByPID[pid]?.command ?? "<unknown>"
                )
            }

        guard survivors.isEmpty else {
            throw SwiftPMProcessError.processesSurvived(survivors)
        }

        printi(
            "Terminated all detected SwiftPM processes."
        )

        return matchedProcesses
    }

    private func snapshot() throws -> [ProcRow] {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = [
            "ax",
            "-o",
            "pid=,ppid=,command="
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            throw SwiftPMProcessError.processSnapshotFailed(
                exitCode: process.terminationStatus,
                stderr: String(
                    data: stderrData,
                    encoding: .utf8
                ) ?? ""
            )
        }

        let text = String(
            data: stdoutData,
            encoding: .utf8
        ) ?? ""

        var rows: [ProcRow] = []
        rows.reserveCapacity(256)

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(
                in: .whitespaces
            )

            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(
                maxSplits: 2,
                whereSeparator: {
                    $0 == " " || $0 == "\t"
                }
            )

            guard
                parts.count == 3,
                let pid = pid_t(parts[0]),
                let ppid = pid_t(parts[1])
            else {
                continue
            }

            rows.append(
                ProcRow(
                    pid: pid,
                    ppid: ppid,
                    command: String(parts[2])
                )
            )
        }

        return rows
    }

    private func makeChildrenByParent(
        from rows: [ProcRow]
    ) -> [pid_t: [pid_t]] {
        var childrenByParent: [pid_t: [pid_t]] = [:]
        childrenByParent.reserveCapacity(rows.count)

        for row in rows {
            childrenByParent[row.ppid, default: []].append(
                row.pid
            )
        }

        return childrenByParent
    }

    private func orderedProcessTreePIDs(
        roots: [pid_t],
        childrenByParent: [pid_t: [pid_t]]
    ) -> [pid_t] {
        var visited = Set<pid_t>()
        var ordered: [pid_t] = []

        func appendTree(_ pid: pid_t) {
            guard visited.insert(pid).inserted else {
                return
            }

            for child in childrenByParent[pid, default: []] {
                appendTree(child)
            }

            ordered.append(pid)
        }

        for root in roots {
            appendTree(root)
        }

        return ordered
    }

    private func signal(
        _ pids: [pid_t],
        signal: Int32,
        signalName: String,
        processByPID: [pid_t: ProcRow]
    ) throws {
        for pid in pids {
            guard isAlive(pid) else {
                continue
            }

            errno = 0
            let result = Darwin.kill(pid, signal)

            if result != 0 {
                let errorNumber = errno

                if errorNumber == ESRCH {
                    continue
                }

                throw SwiftPMProcessError.killFailed(
                    pid: pid,
                    signal: signal,
                    errno: errorNumber
                )
            }

            let command = processByPID[pid]?.command ?? "<unknown>"
            printi(
                "Sent \(signalName) to pid \(pid) – \(command)"
            )
        }
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        errno = 0

        if Darwin.kill(pid, 0) == 0 {
            return true
        }

        return errno != ESRCH
    }

    private static func isSwiftPMCommandLine(
        _ command: String
    ) -> Bool {
        guard !command.isEmpty else {
            return false
        }

        let tokens = command.split(
            whereSeparator: {
                $0 == " " || $0 == "\t"
            }
        )

        guard let executableToken = tokens.first else {
            return false
        }

        let executableName = String(
            executableToken
                .split(separator: "/")
                .last ?? executableToken
        )

        if executableName == "swift" {
            guard tokens.count >= 2 else {
                return false
            }

            let subcommand = tokens[1].lowercased()

            return [
                "build",
                "package",
                "run",
                "test"
            ].contains(subcommand)
        }

        return [
            "swift-build",
            "swift-package",
            "swift-run",
            "swift-test"
        ].contains(executableName)
    }
}

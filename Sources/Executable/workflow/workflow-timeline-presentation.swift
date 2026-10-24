import Foundation
import Terminal
#if canImport(Darwin)
import Darwin
#endif

/// A terminal projection of the resolved plan and WorkflowExecution lifecycle.
/// WorkflowExecution remains responsible for all execution and authorization decisions.
public enum WorkflowTimelinePresentation {
    public static func present(_ plan: WorkflowPlanning.Plan) {
        var items: [TerminalTimelineItem<String>] = []
        for (stage_index, stage) in plan.stages.enumerated() {
            let group = "\(stage.id)  [\(stage.package)]"
            let metadata = "path: \(stage.directory.path)" +
                (stage.needs.isEmpty ? "" : "\nneeds: \(stage.needs.joined(separator: ", "))")
            if stage.operations.isEmpty {
                items.append(.init(
                    id: "stage:\(stage_index)",
                    title: group,
                    detail: metadata,
                    state: .pending
                ))
            }
            for (operation_index, operation) in stage.operations.enumerated() {
                items.append(.init(
                    id: "operation:\(stage_index):\(operation_index)",
                    title: operation.description,
                    detail: operation_index == 0 ? metadata : nil,
                    state: WorkflowTimelineProjection.disabled(operation) ? .skipped : .pending,
                    groups: [group]
                ))
            }
        }
        let output = "SBM / WORKFLOW  \(plan.name)\nWorkspace: \(plan.root.path)\nSource: \(plan.source.path)\nMode: dry-run\n\n" +
            TerminalTimeline(items: items, style: .plain).render(width: max(20, Terminal.size(for: .standardOutput).columns - 2)) +
            "\n\nNo operations executed.\n"
        Terminal.write(output)
    }

    public static func run(
        _ plan: WorkflowPlanning.Plan,
        message: String?,
        allowPublish: Bool,
        verbose: Bool = false
    ) async throws {
        #if canImport(Darwin)
        let interactive = !verbose && Terminal.isInteractive && isatty(STDOUT_FILENO) != 0
        #else
        let interactive = false
        #endif
        let projection = WorkflowTimelineProjection(plan: plan, interactive: interactive)
        let report_output: (@Sendable (WorkflowExecution.Output) async -> Void)?
        if verbose {
            report_output = { @Sendable output in
                await projection.acceptOutput(output)
            }
        } else {
            report_output = nil
        }
        let ticker: Task<Void, Never>? = interactive ? Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { break }
                await projection.tick()
            }
        } : nil
        do {
            try await WorkflowExecution.execute(
                plan,
                message: message,
                allowPublish: allowPublish,
                performer: LiveWorkflowOperationPerformer(onOutput: report_output),
                onEvent: { event in await projection.accept(event) }
            )
            ticker?.cancel()
            await projection.close()
        } catch {
            ticker?.cancel()
            await projection.close()
            throw error
        }
    }
}

/// Each operation has a stable stage/operation index; repeated operation kinds cannot collide.
private actor WorkflowTimelineProjection {
    private let plan: WorkflowPlanning.Plan
    private let interactive: Bool
    private var states: [String: TerminalTimelineItemState] = [:]
    private var started_at: [String: TimeInterval] = [:]
    private var elapsed: [String: TimeInterval] = [:]
    private var failures: [String: String] = [:]
    private var not_reached: Set<String> = []
    private var current_operation: String?
    private var spinner = TerminalSpinnerState()
    private var last_row_count = 0
    private var in_place = true
    private var final_snapshot_written = false
    private var begun = false
    private var ended = false
    private var workflow_started_at: TimeInterval?
    private var workflow_elapsed: TimeInterval?
    private var outcome: String?

    init(plan: WorkflowPlanning.Plan, interactive: Bool) {
        self.plan = plan
        self.interactive = interactive
    }

    nonisolated static func disabled(_ operation: WorkflowPlanning.Operation) -> Bool {
        switch operation {
        case .update(.never): return true
        case .publish(let policy): return policy.guardCondition == .never || (!policy.commit && !policy.push)
        default: return false
        }
    }

    private func key(stage: Int, operation: Int? = nil) -> String {
        if let operation { return "operation:\(stage):\(operation)" }
        return "stage:\(stage)"
    }

    func accept(_ event: WorkflowExecution.Event) {
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case .workflowStarted:
            begun = true
            workflow_started_at = now
        case .stageStarted(let stage):
            let id = key(stage: stage)
            states[id] = .active
            started_at[id] = now
        case .operationStarted(let stage, let operation):
            let id = key(stage: stage, operation: operation)
            states[id] = .active
            started_at[id] = now
            current_operation = "\(plan.stages[stage].id) / \(plan.stages[stage].operations[operation].description)"
            if case .publish = plan.stages[stage].operations[operation] {
                // Existing Git helpers may write directly to stdout. Stop cursor rewrites.
                in_place = false
            }
        case .operationCompleted(let stage, let operation, let skipped):
            let id = key(stage: stage, operation: operation)
            states[id] = skipped ? .skipped : .completed
            current_operation = nil
            if let start = started_at[id] { elapsed[id] = now - start }
        case .operationFailed(let stage, let operation, let details):
            let id = key(stage: stage, operation: operation)
            states[id] = .failed
            current_operation = nil
            failures[id] = failureDetail(details)
            if let start = started_at[id] { elapsed[id] = now - start }
        case .stageCompleted(let stage):
            let id = key(stage: stage)
            states[id] = .completed
            if let start = started_at[id] { elapsed[id] = now - start }
        case .stageFailed(let stage):
            let id = key(stage: stage)
            states[id] = .failed
            if let start = started_at[id] { elapsed[id] = now - start }
        case .workflowCompleted:
            ended = true
            workflow_elapsed = workflow_started_at.map { now - $0 }
            outcome = "WORKFLOW COMPLETED"
        case .workflowFailed(let detail):
            ended = true
            workflow_elapsed = workflow_started_at.map { now - $0 }
            for (stage_index, stage) in plan.stages.enumerated() {
                let stage_id = key(stage: stage_index)
                if states[stage_id] == nil {
                    states[stage_id] = .skipped
                    not_reached.insert(stage_id)
                }
                for (operation_index, operation) in stage.operations.enumerated() {
                    let id = key(stage: stage_index, operation: operation_index)
                    if states[id] == nil {
                        states[id] = .skipped
                        // Disabled by policy is distinct from blocked by failure.
                        if !Self.disabled(operation) {
                            not_reached.insert(id)
                        }
                    }
                }
            }
            outcome = failures.isEmpty
                ? "WORKFLOW FAILED: \(failureDetail(detail))"
                : "WORKFLOW FAILED"
        }
        if interactive && in_place {
            draw()
        } else {
            log(event)
        }
    }

    func acceptOutput(_ output: WorkflowExecution.Output) {
        let channel: String
        let message: String
        switch output {
        case .stdout(let text):
            channel = "stdout"
            message = text
        case .stderr(let text):
            channel = "stderr"
            message = text
        case .combined(let text):
            channel = "combined PTY"
            message = text
        }
        Terminal.write("OUTPUT [\(current_operation ?? "workflow")] [\(channel)]\n" + Self.clean(message, limit: nil) + "\n", to: .standardOutput)
    }

    func tick() {
        guard interactive, begun, !ended, in_place else { return }
        _ = spinner.advance()
        draw()
    }

    func close() {
        guard begun else { return }
        if interactive {
            if in_place {
                draw()
            } else if !final_snapshot_written {
                // An operation may have written to the terminal, or the timeline
                // may have exceeded the viewport. Append the final state once.
                var style = TerminalTimelineStyle.standard
                style.group = .bold
                let width = max(20, Terminal.size(for: .standardOutput).columns - 2)
                let summary = "SBM / WORKFLOW  \(plan.name)\n" +
                    TerminalTimeline(items: items(), style: style).render(width: width) +
                    "\n" + statusLine() + "\n"
                Terminal.write(summary, to: .standardOutput)
            }
            Terminal.write("\n", to: .standardOutput)
            last_row_count = 0
        }
    }

    private func items() -> [TerminalTimelineItem<String>] {
        var result: [TerminalTimelineItem<String>] = []
        for (stage_index, stage) in plan.stages.enumerated() {
            let stage_id = key(stage: stage_index)
            let stage_state = states[stage_id] ?? .pending
            let marker: String
            switch stage_state {
            case .pending: marker = "○"
            case .active: marker = spinner.currentFrame
            case .completed: marker = "✓"
            case .warning: marker = "!"
            case .failed: marker = "×"
            case .skipped: marker = "─"
            }
            let group = "\(marker) \(stage.id)  [\(stage.package)]" + duration(stage_id) +
                (not_reached.contains(stage_id) ? "  (not reached)" : "")
            let metadata = "path: \(stage.directory.path)" +
                (stage.needs.isEmpty ? "" : "\nneeds: \(stage.needs.joined(separator: ", "))")
            if stage.operations.isEmpty {
                result.append(.init(
                    id: stage_id,
                    title: group,
                    detail: metadata,
                    state: stage_state
                ))
            }
            for (operation_index, operation) in stage.operations.enumerated() {
                let id = key(stage: stage_index, operation: operation_index)
                let state = states[id] ?? (Self.disabled(operation) ? .skipped : .pending)
                var details = operation_index == 0 ? metadata : ""
                if not_reached.contains(id) {
                    details += "\nNot reached because workflow execution stopped."
                }
                if let failure = failures[id] {
                    details += "\n" + failure
                }
                result.append(.init(
                    id: id,
                    title: operation.description + duration(id),
                    detail: details.isEmpty ? nil : details,
                    state: state,
                    groups: [group]
                ))
            }
        }
        return result
    }

    private func statusLine() -> String {
        let operation_ids = plan.stages.enumerated().flatMap { stage_index, stage in
            stage.operations.indices.map { operation_index in
                key(stage: stage_index, operation: operation_index)
            }
        }
        let completed = operation_ids.filter { states[$0] == .completed }.count
        let skipped = operation_ids.filter {
            states[$0] == .skipped && !not_reached.contains($0)
        }.count
        let failed = operation_ids.filter { states[$0] == .failed }.count
        let blocked = operation_ids.filter { not_reached.contains($0) }.count
        let finished_stages = plan.stages.indices.filter {
            states[key(stage: $0)] == .completed
        }.count
        let seconds = workflow_elapsed ?? workflow_started_at.map {
            ProcessInfo.processInfo.systemUptime - $0
        }
        let duration = seconds.map(TerminalDurationFormatter.format) ?? "0.00s"
        return "\(outcome ?? "RUNNING") | stages \(finished_stages)/\(plan.stages.count) | " +
            "operations \(completed)/\(operation_ids.count) completed, " +
            "\(skipped) skipped, \(failed) failed, \(blocked) not reached | \(duration)"
    }

    private func duration(_ id: String) -> String {
        let seconds: TimeInterval?
        if let value = elapsed[id] {
            seconds = value
        } else if states[id] == .active, let start = started_at[id] {
            seconds = ProcessInfo.processInfo.systemUptime - start
        } else {
            seconds = nil
        }
        return seconds.map { "  " + TerminalDurationFormatter.format($0) } ?? ""
    }

    private func draw() {
        guard begun else { return }
        var style = TerminalTimelineStyle.standard
        style.activeMarker = spinner.currentFrame
        style.group = .bold
        let size = Terminal.size(for: .standardOutput)
        let lines = ("SBM / WORKFLOW  \(plan.name)\n" +
            TerminalTimeline(items: items(), style: style).render(width: max(20, size.columns - 2)) +
            "\n" + statusLine()).components(separatedBy: "\n")
        let text = lines.joined(separator: "\n") + "\n"
        // Never move the cursor above the visible viewport after a resize.
        let available_rows = max(3, size.rows - 2)
        let can_rewrite = in_place && lines.count < available_rows &&
            last_row_count < available_rows
        if can_rewrite {
            let move = last_row_count > 0 ? "\u{001B}[\(last_row_count)A\r\u{001B}[0J" : ""
            Terminal.write(move + text, to: .standardOutput)
            last_row_count = lines.count
        } else {
            in_place = false
            last_row_count = 0
            Terminal.write(text, to: .standardOutput)
            if ended { final_snapshot_written = true }
        }
    }

    private func failureDetail(_ text: String) -> String {
        let preview = Self.clean(text)
        guard text.count > 12_000 else { return preview }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbm-workflow-failure-\(UUID().uuidString).log")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return preview + "\nFull diagnostic output: \(url.path)"
        } catch {
            return preview + "\nCould not preserve full output: \(error.localizedDescription)"
        }
    }

    private static func clean(_ text: String, limit: Int? = 12_000) -> String {
        let clipped = limit.map { text.count > $0 } ?? false
        let excerpt = clipped ? String(text.suffix(limit ?? 12_000)) : text
        let safe = excerpt.unicodeScalars.map { scalar in
            if scalar == "\n" || scalar == "\t" || (scalar.value >= 32 && scalar.value != 127 && !(128...159).contains(scalar.value)) {
                return String(scalar)
            }
            return "?"
        }.joined()
        return clipped ? "[Earlier output omitted from inline preview]\n" + safe : safe
    }

    private func log(_ event: WorkflowExecution.Event) {
        let line: String?
        switch event {
        case .workflowStarted: line = "WORKFLOW STARTED  \(plan.name)"
        case .stageStarted(let index): line = "STAGE STARTED  \(plan.stages[index].id)"
        case .operationStarted(let stage, let operation):
            line = "START  \(plan.stages[stage].id) / \(plan.stages[stage].operations[operation].description)"
        case .operationCompleted(let stage, let operation, let skipped):
            line = "\(skipped ? "SKIP" : "PASS")  \(plan.stages[stage].id) / \(plan.stages[stage].operations[operation].description)"
        case .operationFailed(let stage, let operation, _):
            let id = key(stage: stage, operation: operation)
            line = "FAIL  \(plan.stages[stage].id) / \(plan.stages[stage].operations[operation].description)\n\(failures[id] ?? "No diagnostic available")"
        case .stageCompleted(let index): line = "STAGE COMPLETED  \(plan.stages[index].id)"
        case .stageFailed(let index): line = "STAGE FAILED  \(plan.stages[index].id)"
        case .workflowCompleted: line = statusLine()
        case .workflowFailed:
            let blocked = plan.stages.enumerated().flatMap { stage_index, stage in
                stage.operations.enumerated().compactMap { operation_index, operation in
                    not_reached.contains(key(stage: stage_index, operation: operation_index))
                        ? "NOT REACHED  \(stage.id) / \(operation.description)"
                        : nil
                }
            }
            line = statusLine() +
                (blocked.isEmpty ? "" : "\n" + blocked.joined(separator: "\n"))
        }
        if let line { Terminal.write(line + "\n", to: .standardOutput) }
    }
}

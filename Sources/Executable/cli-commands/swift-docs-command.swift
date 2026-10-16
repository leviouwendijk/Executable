import Arguments

/// Embedded workflow reference exposed as `sbm docs workflows`; native `help` remains owned by Arguments.
public enum SwiftDocsCommand: ArgumentCommand {
    public static let name = "docs"

    public static let children: [ArgumentCommandType] = [
        SwiftDocsWorkflowsCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Show built-in sbm reference topics.")]
    }
}

public enum SwiftDocsWorkflowsCommand: RunnableArgumentCommand {
    public static let name = "workflows"

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Display the embedded workflow syntax and execution reference.")]
    }

    public static func run(_ invocation: ParsedInvocation) async throws {
        print(reference)
    }

    public static let reference = """
    SBM WORKFLOWS

    Workspace file: <workspace>/.sbm/workflows.pkl
    Find it by searching upward from the current directory, or pass --workspace.
    Package paths in packages { } are relative to the workspace root.

    COMMANDS
      sbm docs workflows
      sbm wf list [--workspace PATH]
      sbm wf show NAME [--workspace PATH]
      sbm wf run NAME [--workspace PATH] [--dry-run]
      sbm wf run NAME --from STAGE_ID --dry-run
      sbm wf run NAME --execute [--publish] [--message TEXT]

    EXAMPLE (.sbm/workflows.pkl)
      packages {
          agentic = "Agentic"
          runtime = "AgenticRuntime"
      }

      workflows {
          agentic_debug {
              inputs { message = "required" }
              defaults {
                  branch = "master"
                  configuration = "debug"
                  onFailure = "stop"
                  update { when = "dependency_stale" }
                  publish {
                      when = "verified"
                      commit = true
                      push = true
                      message = "$message"
                  }
              }
              stages = [
                  {
                      id = "agentic"
                      package = "agentic"
                      test = "t_agentic"
                      update { when = "never" }
                  }
                  {
                      id = "runtime"
                      package = "runtime"
                      needs { "agentic" }
                      test = "t_ar_main"
                  }
              ]
          }
      }

    DECLARATIONS
      packages: alias = relative package directory
      workflows: named workflow definitions
      inputs.message: "required" requires --message for execution
      defaults: branch, configuration, onFailure, update, publish
      stages: ordered records with id, package, optional needs, test,
              update and publish overrides
      needs: prior stage IDs; prerequisite stages must succeed first
      test: SwiftPM executable product name, not a TestFlows flow name
      configuration: "debug" (default) or "release"
      onFailure: "stop" (currently the only supported policy)
      update.when: "always", "never", "dependency_stale"
      publish.when: "always", "never", "verified"
      publish: commit, push, message; a separate typed operation

    EXECUTION AND SAFETY
      Planning is the default. --dry-run explicitly previews the plan.
      --execute enables mutations; --publish additionally authorizes Git
      commit/push (it requires --execute). --execute conflicts with --dry-run.
      --message TEXT replaces the exact "$message" publish template.
      Each stage: update if enabled -> build -> test if declared -> publish
      if its guard permits. A failure stops subsequent stages.
      Publication uses GitManagerAction; package updates use SwiftPM.
      For branch-based dependencies, push upstream commits before the next
      downstream package updates its SwiftPM resolution.
      "dependency_stale" currently performs an update conservatively;
      it does not yet skip updates by comparing resolved revisions.
      --from is planning-only; executing from a later stage is unsupported.
      Automatic rollback and resume are not implemented. Git pushes are real.

    SINGLE-PACKAGE ACTIONS
      sbm pkg runtime update
      sbm p runtime update -v            # update -> build -> tests.primary
      sbm pkg runtime verify             # build -> tests.primary
      sbm p runtime ship -m "Fix runtime" --stage-all
      sbm pkg runtime update --ship -m "Refresh deps" --stage-all
      sbm pkg runtime ship --dry-run
      --workspace PATH selects a workspace explicitly.
      --configuration debug|release selects build mode (debug default).
      --branch BRANCH sets the expected Git branch (master default).
      Package aliases come from packages { }, not stage ids; no `needs` run.
      `update` means SwiftPM dependency update (unlike top-level sbm update).
      Ship always builds and runs declared tests.primary before commit/push.
      Shipping requires --stage-all and --message/-m for real execution.
      The existing Git publisher stages every change (`git add -- .`).
      Verify and ship fail closed if tests.primary is not configured.
      --dry-run previews without executing or requiring --stage-all.

    EXAMPLE EXECUTION
      sbm wf run agentic_debug --dry-run
      sbm wf run agentic_debug --execute --publish --message "Finalize Agentic integration"
    """
}

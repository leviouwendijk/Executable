import Arguments

/// Offline, embedded workflow reference; does not require a workspace checkout.
public enum SwiftHelpCommand: ArgumentCommand {
    public static let name = "help"

    public static let children: [ArgumentCommandType] = [
        SwiftHelpWorkflowsCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Show built-in sbm reference topics.")]
    }
}

public enum SwiftHelpWorkflowsCommand: RunnableArgumentCommand {
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
      sbm help workflows
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

    EXAMPLE EXECUTION
      sbm wf run agentic_debug --dry-run
      sbm wf run agentic_debug --execute --publish --message "Finalize Agentic integration"
    """
}

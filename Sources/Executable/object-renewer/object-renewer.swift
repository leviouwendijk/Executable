import Foundation
import Interfaces
import plate
import Processes
import Terminal
import Indentation

public struct ObjectRenewer: Sendable {
    public init() {}

    public static func update(
        objects: [RenewableObject],
        safe: Bool
    ) async throws {
        for obj in objects {
            // try await check(object: obj, safe: safe)

            // // quit early on ignore
            // let ignore = obj.ignore ?? false
            // if ignore {
            //     print()
            //     print("in: \(obj.path)")
            //     printi("ignore == true")
            //     printi("ignoring this directory")
            //     continue
            // }

            do {
                try await check(object: obj, safe: safe)
            } catch let e as Shell.Error {
                // concise summary
                fputs("Failed updating \(obj.path): \(e)\n", stderr)

                // full dump
                fputs(e.localizedDescription + "\n", stderr)
            } catch {
                fputs("Failed updating \(obj.path): \(String(describing: error))\n", stderr)
            }
        }
    }

    internal static let space: @Sendable () -> () = { print() }

    internal struct ResolvedPaths: Sendable {
        public let expanded: String
        public let directory: URL
    }

    public static func check(object: RenewableObject, safe: Bool) async throws {
        let ignore = object.ignore ?? false
        if ignore {
            print("in: \(object.path)")
            printi("ignore == true")
            printi("ignoring this directory")
            return
        }
        // moved for also direct invocation of check() + update()

        let expanded = (object.path as NSString).expandingTildeInPath
        let dirURL   = URL(fileURLWithPath: expanded, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ObjectRenewerError.directoryNotFound(expanded)
        }

        space()

        let resolvedPaths = ResolvedPaths(expanded: expanded, directory: dirURL)
        try await check_upstream(
            object: object,
            safe: safe,
            resolvedPaths: resolvedPaths
        )

        try await check_compiled(
            object: object,
            safe: safe,
            resolvedPaths: resolvedPaths
        )

        if object.relaunch?.enable == true {
            // try await relaunchApplication(dirURL, target: entry.relaunch?.target)
            try await ProcessEvaluator().relaunch(dirURL, target: object.relaunch?.target)
        }
        space()
    }

    internal static func check_upstream(
        object: RenewableObject,
        safe: Bool,
        resolvedPaths: ResolvedPaths
    ) async throws {
        guard object.criteria.upstream else { return }

        printi("Checking \(resolvedPaths.expanded)…")

        let isOutdated = (try? await GitRepo.outdated(resolvedPaths.directory)) == true
        if !isOutdated {
            printi("No upstream changes; continuing to version check.".ansi(.bold))
        }

        let (remote, branch) = try await GitRepo.upstream(resolvedPaths.directory)
        let div = try await GitRepo.divergence(resolvedPaths.directory)
        printi("Upstream: \(remote)/\(branch)  (ahead=\(div.ahead), behind=\(div.behind))")

        if try await GitRepo.isDirty(resolvedPaths.directory) {
            let severity: ANSIColor = safe ? .red : .yellow
            printi("Working tree is dirty.".ansi(severity))

            if safe {
                printi("Safe mode enabled in run".ansi(.yellow))
                space()
                printi("Aborting to avoid losing changes.".ansi(.red))
                printi("Hint: commit/stash or run: git reset --hard && git pull --ff-only \(remote) \(branch)")
                space()
                printi("Leaving repository scope")
                return
            } else {
                printi("No '--safe' flag enabled, proceeding compile.".ansi(.cyan))
            }
        }

        // If remote changed OR we differ from upstream in any way, make local == upstream
        if isOutdated || div.ahead > 0 || div.behind > 0 {
            if div.ahead > 0 && safe {
                // Preserve prior safe behavior: don’t drop local commits in safe mode
                printi("Branch has diverged (ahead \(div.ahead), behind \(div.behind)).".ansi(.red))
                printi("Safe mode: not discarding local commits automatically.")
                space()
                printi("To preserve local history: rebase your local commits onto upstream:")
                printi(
                    "git fetch --prune --tags && git rebase --autostash --rebase-merges \(remote)/\(branch)"
                    .ansi(.cyan),
                    times: 2
                )
                printi("To reset local changes to upstream: re-run without --safe, or do:")
                printi(
                    "updater (no --safe flag)"
                    .ansi(.cyan),
                    times: 2
                )
                printi("or:")
                printi("git fetch --prune --tags && git reset --hard @{u} && git clean -fdx"
                    .ansi(.cyan),
                    times: 2
                )
                return
            }

            printi("Updating (resetting to upstream)…")
            try await GitRepo.hardResetToUpstream(resolvedPaths.directory, cleanUntracked: false)
            printi("Reset complete.")
        }
    }

    internal static func check_compiled(
        object: RenewableObject,
        safe: Bool,
        resolvedPaths: ResolvedPaths
    ) async throws {
        guard object.criteria.compiled else { return }

        let compilable = object.compilable ?? true

        //  for strictness:
        // guard let compilable = object.compilable else {
        //     throw ObjectRenewerError.compilableNotConfigured(object.path)
        // }

        if compilable {
            let obj_url = try BuildObjectDiscovery.requireLocal(
                named: "build-object.pkl", in: resolvedPaths.directory
            )
            let obj = try BuildObjectConfiguration(from: obj_url)

            let v_release = obj.versions.release

            // soft try to get compiled.pkl
            let compl_url_soft = try BuildObjectDiscovery.local(
                named: "compiled.pkl", in: resolvedPaths.directory
            )

            var reasonToCompile = false

            if let compl_url_found = compl_url_soft {
                let compl_cfg = try CompiledLocalBuildObject(from: compl_url_found)
                let v_compiled = compl_cfg.version
                
                let c = v_compiled
                let r = v_release
                let builtIsBehind = (c.major, c.minor, c.patch) < (r.major, r.minor, r.patch)

                if !builtIsBehind {
                    printi("Built version seems up-to-date; skipping compile.")
                } else {
                    reasonToCompile = true
                    printi("Built version is now behind repository recompiling…")
                    printi("compiled:   \(v_compiled.string(prefixStyle: .none))", times: 2)
                    printi("release:    \(v_release.string(prefixStyle: .none))", times: 2)
                }
            } else {
                printi("No compiled.pkl detected; compiling…")
                reasonToCompile = true
            }

            if reasonToCompile {
                try await execute(in: resolvedPaths.directory)
            }
        }
    }

    public static func execute(in dirURL: URL) async throws {
        let bin = "sbm"

        let cmdPreview = (
            [
                "/usr/bin/env",
                bin,
            ]
        )
        .map {
            $0.isEmpty
                ? "''"
                : "'"
                    + $0.replacingOccurrences(
                        of: "'",
                        with: "'\"'\"'"
                    )
                    + "'"
        }
        .joined(
            separator: " "
        )

        printi(
            "→ \(cmdPreview)"
        )

        let duration = try await executeCommand(
            in: dirURL,
            launchPath: "/bin/zsh",
            arguments: [
                "-lc",
                "/usr/bin/env sbm",
            ],
            displayName: bin,
            teeOutput: true
        )

        let components = duration.components

        let seconds =
            Double(
                components.seconds
            )
            + Double(
                components.attoseconds
            )
            / 1_000_000_000_000_000_000

        let summary =
            "✓ exit=0  time="
            + String(
                format: "%.3fs",
                seconds
            )

        let ok =
            "Compile: "
            + "Ok".ansi(
                .green,
                .bold
            )
            + " "
            + summary

        let div = String(
            repeating: "-",
            count: 50 - 16
        )

        printi(
            div
        )

        printi(
            ok
        )

        printi(
            div
        )
    }

    @discardableResult
    package static func executeCommand(
        in dirURL: URL,
        launchPath: String,
        arguments: [String],
        displayName: String,
        teeOutput: Bool
    ) async throws -> Duration {
        let stdoutHandler: ProcessOutputHandler?
        let stderrHandler: ProcessOutputHandler?

        if teeOutput {
            stdoutHandler = { chunk in
                Terminal.write(
                    chunk,
                    to: .standardOutput
                )
            }

            stderrHandler = { chunk in
                Terminal.write(
                    chunk,
                    to: .standardError
                )
            }
        } else {
            stdoutHandler = nil
            stderrHandler = nil
        }

        let clock = ContinuousClock()
        let started = clock.now

        let result = try await ProcessRunner().run(
            .init(
                executable: .path(
                    launchPath
                ),
                arguments: arguments,
                workingDirectory: dirURL,
                io: .pipes,
                outputLimit: .max
            ),
            onStdout: stdoutHandler,
            onStderr: stderrHandler
        )

        let duration = started.duration(
            to: clock.now
        )

        switch result.exit {
        case .exited(0):
            return duration

        case .exited(
            let code
        ):
            throw ObjectRenewerError.cannotCompile(
                dirURL,
                compileFailureMessage(
                    displayName: displayName,
                    reason: "exited with \(code)",
                    stderr: result.stderr
                )
            )

        case .signaled(
            let signal
        ):
            throw ObjectRenewerError.cannotCompile(
                dirURL,
                compileFailureMessage(
                    displayName: displayName,
                    reason: "terminated by signal \(signal)",
                    stderr: result.stderr
                )
            )
        }
    }

    private static func compileFailureMessage(
        displayName: String,
        reason: String,
        stderr: Data
    ) -> String {
        let stderrText = String(
            data: stderr,
            encoding: .utf8
        ) ?? String(
            decoding: stderr,
            as: UTF8.self
        )

        guard !stderrText.isEmpty else {
            return "\(displayName) \(reason)"
        }

        return "\(displayName) \(reason)\n\(stderrText)"
    }
}

extension ObjectRenewer {
    // /// Discover Git repositories under `rootPath` up to `maxDepth`, and build RenewableObject
    // /// entries for each. `criteria` lets callers decide whether upstream/compiled logic should run.
    // public static func discover(
    //     rootPath: String,
    //     maxDepth: Int = 6,
    //     criteria: ObjectComparisonCriteria = .init()
    // ) throws -> [RenewableObject] {
    //     let expanded = (rootPath as NSString).expandingTildeInPath
    //     let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
    //     return try discover(under: rootURL, maxDepth: maxDepth, criteria: criteria)
    // }

    // /// Low-level discovery using a URL root.
    // public static func discover(
    //     under root: URL,
    //     maxDepth: Int = 6,
    //     criteria: ObjectComparisonCriteria = .init()
    // ) throws -> [RenewableObject] {
    //     let fm = FileManager.default
    //     var isDir: ObjCBool = false
    //     guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
    //         throw ObjectRenewerError.directoryNotFound(root.path)
    //     }

    //     var results: [RenewableObject] = []

    //     let rootComponentsCount = root.pathComponents.count

    //     func isGitRepo(_ dir: URL) -> Bool {
    //         var gitIsDir: ObjCBool = false
    //         let gitPath = dir.appendingPathComponent(".git").path
    //         return fm.fileExists(atPath: gitPath, isDirectory: &gitIsDir) && gitIsDir.boolValue
    //     }

    //     // Check root itself first.
    //     if isGitRepo(root) {
    //         let compilable = fm.fileExists(
    //             atPath: root.appendingPathComponent("build-object.pkl").path
    //         )

    //         results.append(
    //             RenewableObject(
    //                 path: root.path,
    //                 compilable: compilable,
    //                 relaunch: nil,
    //                 ignore: nil,
    //                 criteria: criteria
    //             )
    //         )
    //     }

    //     guard let enumerator = fm.enumerator(
    //         at: root,
    //         includingPropertiesForKeys: [.isDirectoryKey],
    //         options: [.skipsHiddenFiles, .skipsPackageDescendants]
    //     ) else {
    //         return results
    //     }

    //     for case let url as URL in enumerator {
    //         let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
    //         guard resourceValues.isDirectory == true else { continue }

    //         let depth = url.pathComponents.count - rootComponentsCount
    //         if depth > maxDepth {
    //             enumerator.skipDescendants()
    //             continue
    //         }

    //         if isGitRepo(url) {
    //             let compilable = fm.fileExists(
    //                 atPath: url.appendingPathComponent("build-object.pkl").path
    //             )

    //             results.append(
    //                 RenewableObject(
    //                     path: url.path,
    //                     compilable: compilable,
    //                     relaunch: nil,
    //                     ignore: nil,
    //                     criteria: criteria
    //                 )
    //             )

    //             // Once we mark a dir as a repo, don't go deeper into it.
    //             enumerator.skipDescendants()
    //         }
    //     }

    //     results.sort { $0.path < $1.path }
    //     return results
    // }
    
    /// Check based on presence of build-object.pkl
    public static func discover(
        rootPath: String,
        maxDepth: Int = 6,
        criteria: ObjectComparisonCriteria = .init()
    ) throws -> [RenewableObject] {
        let expanded = (rootPath as NSString).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
        return try discover(under: rootURL, maxDepth: maxDepth, criteria: criteria)
    }

    /// Low-level discovery using a URL root.
    public static func discover(
        under root: URL,
        maxDepth: Int = 6,
        criteria: ObjectComparisonCriteria = .init()
    ) throws -> [RenewableObject] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw ObjectRenewerError.directoryNotFound(root.path)
        }

        var results: [RenewableObject] = []
        var seenDirs = Set<String>()

        let rootComponentsCount = root.pathComponents.count

        // Helper to register a project directory
        func registerProject(at dir: URL) {
            let dirPath = dir.path
            guard !seenDirs.contains(dirPath) else { return }
            seenDirs.insert(dirPath)

            // If it has a build-object.pkl, it's compilable; otherwise it's not.
            let compilable = fm.fileExists(
                atPath: dir.appendingPathComponent("build-object.pkl").path
            )

            results.append(
                RenewableObject(
                    path: dirPath,
                    compilable: compilable,
                    relaunch: nil,
                    ignore: nil,
                    criteria: criteria
                )
            )
        }

        // If root itself has a build-object.pkl, treat it as a project.
        if fm.fileExists(atPath: root.appendingPathComponent("build-object.pkl").path) {
            registerProject(at: root)
        }

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootComponentsCount
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if url.lastPathComponent == "build-object.pkl" {
                let dir = url.deletingLastPathComponent()
                registerProject(at: dir)
            }
        }

        results.sort { $0.path < $1.path }
        return results
    }
}

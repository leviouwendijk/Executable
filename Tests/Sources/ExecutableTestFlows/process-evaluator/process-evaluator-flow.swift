import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var processEvaluatorFlow: TestFlow {
        TestFlow(
            "process-evaluator",
            tags: [
                "process",
                "regression",
                "relaunch",
            ]
        ) {
            Step("not-running fallback does not launch app") {
                let fixture = try ProcessEvaluatorFixture()

                defer {
                    fixture.remove()
                }

                let resolved = try AppBundleResolver().resolve(
                    directoryURL: fixture.root,
                    target: fixture.appName
                )

                try Expect.isNil(
                    resolved.bundleIdentifier,
                    "fixture uses process-name fallback"
                )

                try Expect.equal(
                    resolved.executableName,
                    fixture.executableName,
                    "fixture exposes expected executable name"
                )

                try await ProcessEvaluator().relaunch(
                    fixture.root,
                    target: fixture.appName,
                    options: .init(
                        launchEvenIfNotRunning: false
                    )
                )

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: fixture.launchMarker.path
                    ),
                    "not-running fallback does not launch app"
                )
            }
        }
    }
}

private struct ProcessEvaluatorFixture {
    let root: URL
    let appName = "FallbackFixture"
    let executableName: String
    let launchMarker: URL

    init() throws {
        let fileManager = FileManager.default

        root = fileManager
            .temporaryDirectory
            .appendingPathComponent(
                "process-evaluator-fixture-\(UUID().uuidString)",
                isDirectory: true
            )

        executableName = "pe-\(UUID().uuidString)"

        launchMarker = root.appendingPathComponent(
            "launched"
        )

        let app = root.appendingPathComponent(
            appName + ".app",
            isDirectory: true
        )

        let contents = app.appendingPathComponent(
            "Contents",
            isDirectory: true
        )

        let macOS = contents.appendingPathComponent(
            "MacOS",
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: macOS,
            withIntermediateDirectories: true
        )

        let executable = macOS.appendingPathComponent(
            executableName
        )

        let escapedMarker = launchMarker.path
            .replacingOccurrences(
                of: "'",
                with: "'\\''"
            )

        try """
        #!/bin/sh
        printf launched > '\(escapedMarker)'
        exit 0
        """
        .write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )

        try fileManager.setAttributes(
            [
                .posixPermissions: 0o755,
            ],
            ofItemAtPath: executable.path
        )

        let infoPlist = contents.appendingPathComponent(
            "Info.plist"
        )

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>\(appName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleExecutable</key>
            <string>\(executableName)</string>
        </dict>
        </plist>
        """
        .write(
            to: infoPlist,
            atomically: true,
            encoding: .utf8
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}

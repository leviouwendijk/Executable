import Testing

enum ExecutableTestSuite {
    static let suite = TestSuite("executable", title: "Executable Pkl and build-object regressions") {
        pklRegressionSuite
        discoverySuite
        remoteBuildObjectSuite
    }
}

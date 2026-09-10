import Foundation

/// Process-level environment facts that change how services behave.
///
/// The macOS Keychain prompts for the login password whenever a freshly built
/// binary touches an item created by an earlier build. Test hosts are rebuilt
/// on every run, so services that would otherwise read or write the Keychain
/// must stay in memory while tests execute. Production behavior is unchanged.
nonisolated enum AppEnvironment: Sendable {
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }()
}

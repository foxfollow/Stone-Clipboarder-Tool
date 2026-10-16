import Foundation

/// A throwaway UserDefaults suite for one test.
///
/// Never hand `.standard` to code under test: the tests run inside the app
/// (TEST_HOST), and an unsigned test run is unsandboxed, so `.standard` is the
/// installed app's real preferences.
final class IsolatedDefaults {
    let suiteName = "StoneClipboarderToolTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create UserDefaults suite \(suiteName)")
        }
        self.defaults = defaults
    }

    /// Deletes the suite, including its plist on disk.
    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

//
//  VaultManager.swift
//  StoneClipboarderTool
//
//  The Passwords vault while the app runs: lock state, the decrypted
//  entries, and every change to them.
//

import AppKit
import CryptoKit
import Foundation

/// Owns the vault for the Quick Picker's Passwords tab.
///
/// Locked at launch. `unlock` asks `VaultAuthenticator` (Touch ID or the
/// login password), then reads the key from `VaultKeyProvider` and opens the
/// entries. Locking drops the key and the decrypted entries. It locks when
/// the screen locks, the screen saver starts, the Mac or its displays sleep,
/// the user session switches, and after `vaultRelockMinutes` without use.
///
/// Vault content never goes through CBViewModel, the history store, pins,
/// Quick Look or the log: only counts and error descriptions are logged.
@MainActor
final class VaultManager: ObservableObject {
    @Published private(set) var isUnlocked = false
    /// Decrypted entries, in display order; empty while locked.
    @Published private(set) var entries: [VaultPayload] = []
    /// True while the Touch ID / password prompt is up: the Quick Picker
    /// stays open although another process has the focus.
    @Published private(set) var isAuthenticating = false
    /// Entry files that didn't open with the current key.
    @Published private(set) var unreadableCount = 0
    /// A short message for the Passwords tab, e.g. a keychain failure.
    @Published var statusMessage: String?

    enum AddResult: Equatable {
        case added(UUID)
        /// Already in the vault: the existing entry's id.
        case duplicate(UUID)
        case nothingToAdd
        case locked
        case failed
    }

    weak var settingsManager: SettingsManager?
    /// Writes pasted entries; never adds them to the history.
    weak var clipboardManager: ClipboardManager?
    /// Called with the decrypted entries after each unlock, so plaintext
    /// copies captured before an entry was saved leave the history.
    var onUnlocked: (([VaultPayload]) -> Void)?

    private let store: VaultStore
    private let keyProvider: VaultKeyProvider
    private let fingerprintKeyProvider: VaultKeyProvider
    private let authenticator: VaultAuthenticator
    private let now: () -> Date
    private var key: SymmetricKey?
    /// Kept while locked too: recognizes copies of saved entries.
    private var fingerprintKey: SymmetricKey?
    private var fingerprints: Set<String> = []
    private var policy = VaultLockPolicy()

    nonisolated(unsafe) private var expiryTimer: Timer?
    nonisolated(unsafe) private var workspaceObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var distributedObservers: [NSObjectProtocol] = []

    init(
        store: VaultStore = VaultStore(),
        keyProvider: VaultKeyProvider = KeychainVaultKeyProvider(),
        fingerprintKeyProvider: VaultKeyProvider = KeychainVaultKeyProvider(
            account: KeychainVaultKeyProvider.fingerprintAccount),
        authenticator: VaultAuthenticator? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.keyProvider = keyProvider
        self.fingerprintKeyProvider = fingerprintKeyProvider
        self.authenticator = authenticator ?? LocalAuthenticationAuthenticator()
        self.now = now
    }

    /// The app's vault. A unit-test host and demo mode get a throwaway
    /// folder and an in-memory key, never the real vault or keychain.
    static func makeForApp() -> VaultManager {
        guard AppEnvironment.isRunningUnitTests || AppEnvironment.isDemo else { return VaultManager() }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoneClipboarderTool-Vault-\(UUID().uuidString)", isDirectory: true)
        return VaultManager(
            store: VaultStore(root: root), keyProvider: InMemoryVaultKeyProvider(),
            fingerprintKeyProvider: InMemoryVaultKeyProvider())
    }

    deinit {
        expiryTimer?.invalidate()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Lock state

    /// Whether entry files exist, readable without unlocking.
    var hasStoredEntries: Bool { store.hasEntries }

    private var relockMinutes: Int {
        settingsManager?.vaultRelockMinutes ?? VaultLockPolicy.defaultTimeoutMinutes
    }

    /// Unlocks with Touch ID or the password; true when unlocked. An unlocked
    /// vault only counts as used again.
    @discardableResult
    func unlock(reason: String = "unlock your saved passwords") async -> Bool {
        checkExpiry()
        if isUnlocked {
            noteUse()
            return true
        }
        guard !isAuthenticating else { return false }

        isAuthenticating = true
        let confirmed = await authenticator.authenticate(reason: reason)
        guard confirmed else {
            isAuthenticating = false
            return false
        }

        // A keychain access prompt blocks the call; keep it off the main thread.
        let provider = keyProvider
        let fingerprintProvider = fingerprintKeyProvider
        let loaded: Result<(SymmetricKey, SymmetricKey?), Error> = await Task.detached(priority: .userInitiated) {
            Result { (try provider.loadOrCreateKey(), try? fingerprintProvider.loadOrCreateKey()) }
        }.value
        isAuthenticating = false

        switch loaded {
        case .success(let (loadedKey, loadedFingerprintKey)):
            key = loadedKey
            fingerprintKey = loadedFingerprintKey ?? fingerprintKey
            isUnlocked = true
            statusMessage = nil
            reloadEntries()
            rebuildFingerprints()
            noteUse()
            startExpiryTimer()
            onUnlocked?(entries)
            return true
        case .failure(let error):
            ErrorLogger.shared.log("Could not read the vault key", category: "Vault", error: error)
            statusMessage = "Couldn't read the key from the Keychain."
            return false
        }
    }

    /// Drops the key and the decrypted entries.
    func lock() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        key = nil
        entries = []
        isUnlocked = false
        policy.reset()
    }

    /// Restarts the unlock window (opening the tab, pasting, editing).
    func noteUse() {
        guard isUnlocked else { return }
        policy.timeout = VaultLockPolicy(timeoutMinutes: relockMinutes).timeout
        policy.touch(at: now())
    }

    /// Locks when the unlock window ran out.
    func checkExpiry() {
        guard isUnlocked else { return }
        policy.timeout = VaultLockPolicy(timeoutMinutes: relockMinutes).timeout
        if !policy.isOpen(at: now()) {
            lock()
        }
    }

    private func startExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkExpiry() }
        }
    }

    /// Locks on screen lock, screen saver, sleep, display sleep and a
    /// session switch. Called once from `AppDelegate.performSetup`.
    func startObservingSystemLocks() {
        guard workspaceObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        workspaceObservers = workspaceNames.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }
        let distributedNames = ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"]
        distributedObservers = distributedNames.map { name in
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }
    }

    // MARK: - Copies of saved entries

    /// Reads the fingerprints and their key so copies of saved entries are
    /// recognized while the vault is locked. Called once at launch; does
    /// nothing (and never touches the Keychain) for an empty vault.
    func prepareCopyDetection() async {
        let saved = store.loadFingerprints()
        guard !saved.isEmpty else { return }
        fingerprints = saved
        let provider = fingerprintKeyProvider
        let loaded = await Task.detached(priority: .utility) {
            try? provider.readKeyData().flatMap { try? VaultCrypto.key(from: $0) }
        }.value
        if fingerprintKey == nil {
            fingerprintKey = loaded
        }
    }

    /// Whether a new capture has the same content as a saved entry, so the
    /// history must not keep it in plaintext. Works while locked.
    func isStoredSecret(_ capture: ClipboardContent) -> Bool {
        guard let fingerprintKey, !fingerprints.isEmpty else { return false }
        return fingerprints.contains(VaultFingerprint.of(capture, key: fingerprintKey))
    }

    /// From the decrypted entries: covers entries from before fingerprints
    /// and drops deleted ones.
    private func rebuildFingerprints() {
        guard let fingerprintKey else { return }
        fingerprints = Set(entries.map { VaultFingerprint.of($0, key: fingerprintKey) })
        saveFingerprints()
    }

    private func saveFingerprints() {
        do {
            try store.saveFingerprints(fingerprints)
        } catch {
            ErrorLogger.shared.log("Failed to save vault fingerprints", category: "Vault", error: error)
        }
    }

    // MARK: - Entries

    /// Puts an entry on the pasteboard for ⏎ (concealed, cleared after
    /// `vaultClipboardClearSeconds`). False when locked or nothing to copy.
    func copyToPasteboard(_ id: UUID) -> Bool {
        guard isUnlocked, let entry = entry(withID: id), let clipboardManager else { return false }
        noteUse()
        return clipboardManager.copySecret(entry, clearAfter: settingsManager?.vaultClipboardClearSeconds ?? 30)
    }

    /// The text ⌘⇧⏎ types out; nil for images, files or a locked vault.
    func typeableText(of id: UUID) -> String? {
        guard isUnlocked, let text = entry(withID: id)?.typeableText else { return nil }
        noteUse()
        return text
    }

    func entry(withID id: UUID) -> VaultPayload? {
        entries.first { $0.id == id }
    }

    /// Adds a copy of `payload` at the end, unless the same content is
    /// already there. Needs an unlocked vault.
    func add(_ payload: VaultPayload) -> AddResult {
        guard isUnlocked, let key else { return .locked }
        guard payload.hasContent else { return .nothingToAdd }
        if let existing = VaultPayload.duplicate(of: payload, in: entries) {
            noteUse()
            return .duplicate(existing.id)
        }
        var entry = payload
        entry.orderIndex = (entries.map(\.orderIndex).max() ?? -1) + 1
        do {
            try store.save(entry, with: key)
        } catch {
            ErrorLogger.shared.log("Failed to save a vault entry", category: "Vault", error: error)
            return .failed
        }
        entries.append(entry)
        if let fingerprintKey {
            fingerprints.insert(VaultFingerprint.of(entry, key: fingerprintKey))
            saveFingerprints()
        }
        noteUse()
        return .added(entry.id)
    }

    /// Sets or clears (empty) the title.
    @discardableResult
    func rename(_ id: UUID, to title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return update(id) { $0.title = trimmed.isEmpty ? nil : trimmed }
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard isUnlocked, entries.contains(where: { $0.id == id }) else { return false }
        do {
            try store.delete(id: id)
        } catch {
            ErrorLogger.shared.log("Failed to delete a vault entry", category: "Vault", error: error)
            return false
        }
        entries.removeAll { $0.id == id }
        rebuildFingerprints()
        noteUse()
        return true
    }

    /// Moves an entry up (negative) or down; renumbers the order 0…n-1 and
    /// saves only the entries whose place changed.
    @discardableResult
    func move(_ id: UUID, by offset: Int) -> Bool {
        guard isUnlocked, let key, let from = entries.firstIndex(where: { $0.id == id }) else { return false }
        let to = from + offset
        guard offset != 0, entries.indices.contains(to) else { return false }

        var reordered = entries
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: to)
        for index in reordered.indices where reordered[index].orderIndex != index {
            reordered[index].orderIndex = index
            do {
                try store.save(reordered[index], with: key)
            } catch {
                ErrorLogger.shared.log("Failed to reorder the vault", category: "Vault", error: error)
                reloadEntries()
                return false
            }
        }
        entries = reordered
        noteUse()
        return true
    }

    /// Removes every entry file and the key, then locks. The next unlock
    /// starts an empty vault with a new key.
    func deleteAll() {
        lock()
        do {
            try store.deleteAll()
            try keyProvider.deleteKey()
            try fingerprintKeyProvider.deleteKey()
            fingerprints = []
            fingerprintKey = nil
            unreadableCount = 0
            statusMessage = nil
        } catch {
            ErrorLogger.shared.log("Failed to delete the vault", category: "Vault", error: error)
            statusMessage = "Couldn't delete every saved password."
        }
    }

    private func update(_ id: UUID, _ change: (inout VaultPayload) -> Void) -> Bool {
        guard isUnlocked, let key, let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        var entry = entries[index]
        change(&entry)
        do {
            try store.save(entry, with: key)
        } catch {
            ErrorLogger.shared.log("Failed to update a vault entry", category: "Vault", error: error)
            return false
        }
        entries[index] = entry
        noteUse()
        return true
    }

    private func reloadEntries() {
        guard let key else { return }
        let result = store.loadAll(with: key)
        entries = result.entries
        unreadableCount = result.unreadableCount
        if result.unreadableCount > 0 {
            ErrorLogger.shared.log(
                "\(result.unreadableCount) vault entries could not be opened", category: "Vault")
        }
    }
}

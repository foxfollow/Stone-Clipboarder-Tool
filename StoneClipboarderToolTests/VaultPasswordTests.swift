import CryptoKit
import XCTest
@testable import StoneClipboarderTool

final class VaultKeyWrapperTests: XCTestCase {

    /// Real installs use 600 000 rounds; the format doesn't care.
    private let rounds: UInt32 = 1_000

    func testRoundTrip() throws {
        let key = VaultCrypto.makeKey()
        let wrapped = try VaultKeyWrapper.wrap(key, password: "correct horse", rounds: rounds)
        XCTAssertTrue(VaultKeyWrapper.isWrapped(wrapped))
        XCTAssertFalse(VaultKeyWrapper.isWrapped(VaultCrypto.keyData(key)))
        let unwrapped = try VaultKeyWrapper.unwrap(wrapped, password: "correct horse")
        XCTAssertEqual(VaultCrypto.keyData(unwrapped), VaultCrypto.keyData(key))
    }

    func testWrongPasswordFails() throws {
        let wrapped = try VaultKeyWrapper.wrap(VaultCrypto.makeKey(), password: "right", rounds: rounds)
        XCTAssertThrowsError(try VaultKeyWrapper.unwrap(wrapped, password: "wrong")) {
            XCTAssertEqual($0 as? VaultKeyWrapper.Failure, .wrongPassword)
        }
    }

    func testRoundsAndSaltAreStoredAndAuthenticated() throws {
        let key = VaultCrypto.makeKey()
        var wrapped = try VaultKeyWrapper.wrap(key, password: "pw", rounds: rounds)
        // Rounds are read back from the blob.
        XCTAssertEqual(VaultCrypto.keyData(try VaultKeyWrapper.unwrap(wrapped, password: "pw")), VaultCrypto.keyData(key))
        // Tampering with the header (here the salt) makes it fail.
        wrapped[12] ^= 0x01
        XCTAssertThrowsError(try VaultKeyWrapper.unwrap(wrapped, password: "pw"))
    }

    func testFreshSaltEachTime() throws {
        let key = VaultCrypto.makeKey()
        XCTAssertNotEqual(
            try VaultKeyWrapper.wrap(key, password: "pw", rounds: rounds),
            try VaultKeyWrapper.wrap(key, password: "pw", rounds: rounds))
    }

    func testUnicodeFormsDeriveTheSameKey() throws {
        let key = VaultCrypto.makeKey()
        let composed = "пароль\u{00E9}"
        let decomposed = "пароль\u{0065}\u{0301}"
        let wrapped = try VaultKeyWrapper.wrap(key, password: composed, rounds: rounds)
        XCTAssertNoThrow(try VaultKeyWrapper.unwrap(wrapped, password: decomposed))
    }

    func testRejectsEmptyPasswordAndForeignData() {
        XCTAssertThrowsError(try VaultKeyWrapper.wrap(VaultCrypto.makeKey(), password: "")) {
            XCTAssertEqual($0 as? VaultKeyWrapper.Failure, .emptyPassword)
        }
        XCTAssertThrowsError(try VaultKeyWrapper.unwrap(Data(repeating: 1, count: 32), password: "pw")) {
            XCTAssertEqual($0 as? VaultKeyWrapper.Failure, .notWrapped)
        }
    }
}

final class VaultPasswordRulesTests: XCTestCase {

    func testRules() {
        XCTAssertNotNil(VaultPasswordRules.problem(password: "short", confirmation: "short", hint: "", acknowledged: true))
        XCTAssertNotNil(VaultPasswordRules.problem(password: "longer1", confirmation: "longer2", hint: "", acknowledged: true))
        XCTAssertNotNil(VaultPasswordRules.problem(password: "secret1", confirmation: "secret1", hint: "it is SECRET1!", acknowledged: true))
        XCTAssertNotNil(VaultPasswordRules.problem(password: "secret1", confirmation: "secret1", hint: "", acknowledged: false))
        XCTAssertNil(VaultPasswordRules.problem(password: "secret1", confirmation: "secret1", hint: "cat's name", acknowledged: true))
        XCTAssertNil(VaultPasswordRules.problem(password: "secret1", confirmation: "secret1", hint: "  ", acknowledged: true))
    }
}

@MainActor
final class VaultManagerPasswordTests: XCTestCase {

    private final class YesAuthenticator: VaultAuthenticator {
        var calls = 0
        func authenticate(reason: String) async -> Bool {
            calls += 1
            return true
        }
    }

    private var root: URL!
    private var keyProvider: InMemoryVaultKeyProvider!
    private var hintProvider: InMemoryVaultKeyProvider!
    private var isolated: IsolatedDefaults!
    private var settings: SettingsManager!
    private var authenticator: YesAuthenticator!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultManagerPasswordTests-\(UUID().uuidString)", isDirectory: true)
        keyProvider = InMemoryVaultKeyProvider()
        hintProvider = InMemoryVaultKeyProvider()
        isolated = IsolatedDefaults()
        settings = SettingsManager(defaults: isolated.defaults)
        authenticator = YesAuthenticator()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        isolated.remove()
        super.tearDown()
    }

    private func makeManager() -> VaultManager {
        let manager = VaultManager(
            store: VaultStore(root: root), keyProvider: keyProvider,
            fingerprintKeyProvider: InMemoryVaultKeyProvider(), hintProvider: hintProvider,
            authenticator: authenticator)
        manager.settingsManager = settings
        return manager
    }

    func testTheHintIsReadBackForTheLockScreenAndALegacyOneMoves() async {
        let manager = makeManager()
        await manager.unlock()
        await manager.setPassword("secret1", hint: "pet", rounds: 1_000)

        let relaunched = makeManager()
        XCTAssertEqual(relaunched.passwordHint, "")
        await relaunched.loadPasswordHint()
        XCTAssertEqual(relaunched.passwordHint, "pet")

        // A 1.11 beta left one in UserDefaults.
        isolated.defaults.set("old hint", forKey: "vaultPasswordHint")
        await relaunched.migrateLegacyPasswordHint()
        XCTAssertNil(isolated.defaults.object(forKey: "vaultPasswordHint"))
        XCTAssertEqual(hintProvider.storedData, Data("old hint".utf8))
    }

    func testSetPasswordWrapsTheKeyAndReplacesTouchID() async throws {
        let manager = makeManager()
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, content: "pw"))
        let didSet = await manager.setPassword("secret1", hint: "  pet  ", rounds: 1_000)
        XCTAssertTrue(didSet)
        XCTAssertTrue(settings.vaultUsesPassword)
        XCTAssertEqual(manager.passwordHint, "pet")
        XCTAssertEqual(hintProvider.storedData, Data("pet".utf8), "the hint is in the Keychain, not UserDefaults")
        XCTAssertNil(isolated.defaults.object(forKey: "vaultPasswordHint"))
        XCTAssertTrue(VaultKeyWrapper.isWrapped(try XCTUnwrap(keyProvider.storedData)))

        manager.lock()
        let byTouchID = await manager.unlock()
        XCTAssertFalse(byTouchID)
        XCTAssertEqual(authenticator.calls, 1, "Touch ID isn't asked once a password is set")

        let wrong = await manager.unlock(password: "nope")
        XCTAssertFalse(wrong)
        XCTAssertEqual(manager.statusMessage, "Wrong password.")

        let right = await manager.unlock(password: "secret1")
        XCTAssertTrue(right)
        XCTAssertEqual(manager.entries.map(\.content), ["pw"])
    }

    func testRemovePasswordGoesBackToTouchID() async throws {
        let manager = makeManager()
        await manager.unlock()
        await manager.setPassword("secret1", hint: nil, rounds: 1_000)
        let removed = await manager.removePassword()
        XCTAssertTrue(removed)
        XCTAssertFalse(settings.vaultUsesPassword)
        XCTAssertEqual(try XCTUnwrap(keyProvider.storedData).count, 32)

        manager.lock()
        let unlocked = await manager.unlock()
        XCTAssertTrue(unlocked)
    }

    func testSettingFollowsTheKeychain() async {
        // A wrapped key with the setting lost (e.g. preferences reset).
        let manager = makeManager()
        await manager.unlock()
        await manager.setPassword("secret1", hint: nil, rounds: 1_000)
        manager.lock()
        settings.vaultUsesPassword = false

        let byTouchID = await manager.unlock()
        XCTAssertFalse(byTouchID)
        XCTAssertTrue(settings.vaultUsesPassword, "the lock screen now asks for the password")
    }

    func testAPasswordNeverOpensAKeyGuardedByTouchID() async {
        // A raw key stored; the setting (UserDefaults, editable by anyone in
        // the session) claims a password is set.
        let manager = makeManager()
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, content: "pw"))
        manager.lock()
        let touchIDCalls = authenticator.calls
        settings.vaultUsesPassword = true

        let byAnyPassword = await manager.unlock(password: "x")
        XCTAssertFalse(byAnyPassword)
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertTrue(manager.entries.isEmpty)
        XCTAssertEqual(authenticator.calls, touchIDCalls)
        XCTAssertFalse(settings.vaultUsesPassword, "the lock screen goes back to Touch ID")

        let byTouchID = await manager.unlock()
        XCTAssertTrue(byTouchID)
        XCTAssertEqual(authenticator.calls, touchIDCalls + 1)
    }

    func testAPasswordCannotCreateTheFirstKey() async {
        settings.vaultUsesPassword = true
        let manager = makeManager()
        let unlocked = await manager.unlock(password: "x")
        XCTAssertFalse(unlocked)
        XCTAssertFalse(keyProvider.hasKey)
    }

    func testNeedsUnlockToChangeAndDeleteAllClearsIt() async {
        let manager = makeManager()
        let lockedSet = await manager.setPassword("secret1", hint: nil, rounds: 1_000)
        XCTAssertFalse(lockedSet)

        await manager.unlock()
        await manager.setPassword("secret1", hint: "h", rounds: 1_000)
        manager.deleteAll()
        XCTAssertFalse(settings.vaultUsesPassword)
        XCTAssertEqual(manager.passwordHint, "")
        XCTAssertFalse(hintProvider.hasKey)
    }
}

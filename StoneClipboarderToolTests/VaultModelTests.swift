import CryptoKit
import XCTest
@testable import StoneClipboarderTool

final class VaultPayloadTests: XCTestCase {

    func testTextItemBecomesPayloadWithTrimmedTitle() throws {
        let item = CBItem(timestamp: Date(), content: "s3cret", itemType: .text)
        item.title = "  Bank  "
        let payload = try XCTUnwrap(VaultPayload(item: item, orderIndex: 3))
        XCTAssertEqual(payload.itemType, .text)
        XCTAssertEqual(payload.content, "s3cret")
        XCTAssertEqual(payload.title, "Bank")
        XCTAssertEqual(payload.orderIndex, 3)
        XCTAssertEqual(payload.typeableText, "s3cret")
    }

    func testBlankTitleIsDropped() throws {
        let item = CBItem(timestamp: Date(), content: "x", itemType: .text)
        item.title = "   "
        XCTAssertNil(try XCTUnwrap(VaultPayload(item: item)).title)
    }

    func testEmptyItemsAreRejected() {
        XCTAssertNil(VaultPayload(item: CBItem(timestamp: Date(), content: "", itemType: .text)))
        XCTAssertNil(VaultPayload(item: CBItem(timestamp: Date(), itemType: .image)))
        XCTAssertNil(VaultPayload(item: CBItem(timestamp: Date(), fileData: Data([1]), itemType: .file)))
        XCTAssertNil(VaultPayload(item: CBItem(timestamp: Date(), itemType: .combined)))
    }

    func testFileAndImagePayloadsKeepTheirData() throws {
        let file = CBItem(
            timestamp: Date(), fileData: Data([1, 2]), fileName: "key.pem", fileUTI: "public.data", itemType: .file)
        let filePayload = try XCTUnwrap(VaultPayload(item: file))
        XCTAssertEqual(filePayload.fileData, Data([1, 2]))
        XCTAssertEqual(filePayload.fileName, "key.pem")
        XCTAssertEqual(filePayload.fileUTI, "public.data")
        XCTAssertNil(filePayload.typeableText)
        XCTAssertEqual(filePayload.displayName, "key.pem")

        let image = VaultPayload(itemType: .image, imageData: Data([9]))
        XCTAssertTrue(image.hasContent)
        XCTAssertNil(image.typeableText)
        XCTAssertEqual(image.displayName, "Image")
    }

    func testDisplayNameNeverShowsText() {
        XCTAssertEqual(VaultPayload(itemType: .text, content: "hunter2").displayName, "Password")
        XCTAssertEqual(VaultPayload(itemType: .text, title: "Mail", content: "hunter2").displayName, "Mail")
        XCTAssertEqual(VaultPayload(itemType: .file, fileData: Data()).displayName, "File")
    }

    func testSameContentIgnoresTitleAndId() {
        let a = VaultPayload(itemType: .text, title: "A", content: "pw")
        let b = VaultPayload(itemType: .text, title: "B", content: "pw")
        XCTAssertTrue(a.hasSameContent(as: b))
        XCTAssertFalse(a.hasSameContent(as: VaultPayload(itemType: .text, content: "other")))
        XCTAssertFalse(a.hasSameContent(as: VaultPayload(itemType: .combined, content: "pw")))

        let fileA = VaultPayload(itemType: .file, fileData: Data([1]), fileName: "a")
        XCTAssertTrue(fileA.hasSameContent(as: VaultPayload(itemType: .file, fileData: Data([1]), fileName: "a")))
        XCTAssertFalse(fileA.hasSameContent(as: VaultPayload(itemType: .file, fileData: Data([1]), fileName: "b")))

        let combined = VaultPayload(itemType: .combined, content: "t", imageData: Data([1]))
        XCTAssertTrue(combined.hasSameContent(as: VaultPayload(itemType: .combined, content: "t", imageData: Data([1]))))
        XCTAssertFalse(combined.hasSameContent(as: VaultPayload(itemType: .combined, content: "t", imageData: Data([2]))))

        let image = VaultPayload(itemType: .image, imageData: Data([1]))
        XCTAssertTrue(image.hasSameContent(as: VaultPayload(itemType: .image, imageData: Data([1]))))
    }

    func testDuplicateSkipsTheSameEntry() {
        let a = VaultPayload(itemType: .text, content: "pw")
        XCTAssertNil(VaultPayload.duplicate(of: a, in: [a]))
        let b = VaultPayload(itemType: .text, content: "pw")
        XCTAssertEqual(VaultPayload.duplicate(of: b, in: [a])?.id, a.id)
    }

    func testSearchMatchesTitleFileNameAndText() {
        let entry = VaultPayload(itemType: .text, title: "GitHub token", content: "ghp_ABC")
        XCTAssertTrue(entry.matches("github"))
        XCTAssertTrue(entry.matches("abc"))
        XCTAssertTrue(entry.matches("  "))
        XCTAssertFalse(entry.matches("gitlab"))
        XCTAssertTrue(VaultPayload(itemType: .file, fileData: Data([1]), fileName: "id_rsa").matches("RSA"))
    }

    func testLabelSearchNeverLooksAtTheSecret() {
        let entry = VaultPayload(itemType: .text, title: "test-asd", content: "hunter2")
        XCTAssertTrue(entry.matchesLabel("TEST-a"))
        XCTAssertFalse(entry.matchesLabel("hunter"))
        XCTAssertFalse(entry.matchesLabel("  "))
        XCTAssertTrue(VaultPayload(itemType: .file, fileData: Data([1]), fileName: "id_rsa").matchesLabel("rsa"))
    }

    func testEntriesFromBeforeIconsStillDecode() throws {
        // JSON as sealed by the first version: no icon, no colorHex.
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","itemType":"text","content":"pw","createdAt":1000,"orderIndex":0}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload = try decoder.decode(VaultPayload.self, from: Data(old.utf8))
        XCTAssertEqual(payload.content, "pw")
        XCTAssertNil(payload.icon)
        XCTAssertNil(payload.colorHex)
    }

    func testIconAndColorSurviveSealing() throws {
        let key = VaultCrypto.makeKey()
        let entry = VaultPayload(itemType: .text, content: "pw", icon: .symbol("creditcard"), colorHex: "#FF0000")
        let opened = try VaultCrypto.open(VaultCrypto.seal(entry, with: key), id: entry.id, with: key)
        XCTAssertEqual(opened.icon, .symbol("creditcard"))
        XCTAssertEqual(opened.colorHex, "#FF0000")
    }

    func testSortedByOrderThenAge() {
        let old = VaultPayload(itemType: .text, content: "1", createdAt: Date(timeIntervalSince1970: 1), orderIndex: 1)
        let new = VaultPayload(itemType: .text, content: "2", createdAt: Date(timeIntervalSince1970: 2), orderIndex: 1)
        let first = VaultPayload(itemType: .text, content: "3", createdAt: Date(timeIntervalSince1970: 3), orderIndex: 0)
        XCTAssertEqual(VaultPayload.sorted([new, old, first]).map(\.id), [first.id, old.id, new.id])
    }
}

final class VaultCryptoTests: XCTestCase {

    private let payload = VaultPayload(
        itemType: .combined, title: "T", content: "pw", imageData: Data([1, 2, 3]),
        createdAt: Date(timeIntervalSince1970: 1_000), orderIndex: 2)

    func testRoundTrip() throws {
        let key = VaultCrypto.makeKey()
        let sealed = try VaultCrypto.seal(payload, with: key)
        XCTAssertEqual(sealed.prefix(4), VaultCrypto.magic)
        XCTAssertEqual(try VaultCrypto.open(sealed, id: payload.id, with: key), payload)
    }

    func testSealedBytesDontContainTheSecret() throws {
        let secret = VaultPayload(itemType: .text, title: "Visible?", content: "super-secret-value")
        let sealed = try VaultCrypto.seal(secret, with: VaultCrypto.makeKey())
        XCTAssertNil(sealed.range(of: Data("super-secret-value".utf8)))
        XCTAssertNil(sealed.range(of: Data("Visible?".utf8)))
    }

    func testWrongKeyFails() throws {
        let sealed = try VaultCrypto.seal(payload, with: VaultCrypto.makeKey())
        XCTAssertThrowsError(try VaultCrypto.open(sealed, id: payload.id, with: VaultCrypto.makeKey())) {
            XCTAssertEqual($0 as? VaultCrypto.Failure, .cannotOpen)
        }
    }

    func testTamperedBytesFail() throws {
        let key = VaultCrypto.makeKey()
        var sealed = try VaultCrypto.seal(payload, with: key)
        sealed[sealed.count - 1] ^= 0xFF
        XCTAssertThrowsError(try VaultCrypto.open(sealed, id: payload.id, with: key))
    }

    func testFileUnderAnotherIdFails() throws {
        let key = VaultCrypto.makeKey()
        let sealed = try VaultCrypto.seal(payload, with: key)
        XCTAssertThrowsError(try VaultCrypto.open(sealed, id: UUID(), with: key)) {
            XCTAssertEqual($0 as? VaultCrypto.Failure, .cannotOpen)
        }
    }

    func testHeaderChecks() throws {
        let key = VaultCrypto.makeKey()
        XCTAssertThrowsError(try VaultCrypto.open(Data("nope".utf8), id: payload.id, with: key)) {
            XCTAssertEqual($0 as? VaultCrypto.Failure, .notAVaultFile)
        }
        var sealed = try VaultCrypto.seal(payload, with: key)
        sealed[4] = 9
        XCTAssertThrowsError(try VaultCrypto.open(sealed, id: payload.id, with: key)) {
            XCTAssertEqual($0 as? VaultCrypto.Failure, .unsupportedVersion(9))
        }
    }

    func testKeyDataRoundTrip() throws {
        let key = VaultCrypto.makeKey()
        let data = VaultCrypto.keyData(key)
        XCTAssertEqual(data.count, 32)
        XCTAssertEqual(VaultCrypto.keyData(try VaultCrypto.key(from: data)), data)
        XCTAssertThrowsError(try VaultCrypto.key(from: Data([1, 2]))) {
            XCTAssertEqual($0 as? VaultCrypto.Failure, .invalidKey)
        }
    }
}

final class VaultStoreTests: XCTestCase {

    private var root: URL!
    private var store: VaultStore!
    private let key = VaultCrypto.makeKey()

    override func setUp() {
        super.setUp()
        // Never the real vault folder.
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = VaultStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testEmptyStoreLoadsNothing() {
        XCTAssertFalse(store.hasEntries)
        let result = store.loadAll(with: key)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.unreadableCount, 0)
    }

    func testSaveLoadReplaceAndDelete() throws {
        var entry = VaultPayload(itemType: .text, content: "pw", orderIndex: 0)
        try store.save(entry, with: key)
        XCTAssertTrue(store.hasEntries)
        XCTAssertEqual(store.loadAll(with: key).entries, [entry])

        entry.title = "Renamed"
        try store.save(entry, with: key)
        XCTAssertEqual(store.loadAll(with: key).entries.map(\.title), ["Renamed"])

        try store.delete(id: entry.id)
        try store.delete(id: entry.id)  // a second delete is harmless
        XCTAssertTrue(store.loadAll(with: key).entries.isEmpty)
    }

    func testFilesAreOwnerOnly() throws {
        let entry = VaultPayload(itemType: .text, content: "pw")
        try store.save(entry, with: key)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL(for: entry.id).path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folderAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((folderAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testUnreadableFilesAreCountedAndKept() throws {
        try store.save(VaultPayload(itemType: .text, content: "good"), with: key)
        try store.save(VaultPayload(itemType: .text, content: "other key"), with: VaultCrypto.makeKey())
        let junk = root.appendingPathComponent("\(UUID().uuidString).sctv")
        try Data("junk".utf8).write(to: junk)
        try Data("ignored".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let result = store.loadAll(with: key)
        XCTAssertEqual(result.entries.map(\.content), ["good"])
        XCTAssertEqual(result.unreadableCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: junk.path))
    }

    func testLoadSortsByOrder() throws {
        let second = VaultPayload(itemType: .text, content: "b", orderIndex: 1)
        let first = VaultPayload(itemType: .text, content: "a", orderIndex: 0)
        try store.save(second, with: key)
        try store.save(first, with: key)
        XCTAssertEqual(store.loadAll(with: key).entries.map(\.id), [first.id, second.id])
    }

    func testDeleteAll() throws {
        try store.save(VaultPayload(itemType: .text, content: "pw"), with: key)
        try store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try store.deleteAll()  // nothing left: no error
    }
}

final class VaultLockPolicyTests: XCTestCase {

    func testLockedUntilFirstUse() {
        XCTAssertFalse(VaultLockPolicy().isOpen(at: Date()))
    }

    func testSlidingWindow() {
        var policy = VaultLockPolicy(timeoutMinutes: 60)
        let start = Date(timeIntervalSince1970: 10_000)
        policy.touch(at: start)
        XCTAssertTrue(policy.isOpen(at: start.addingTimeInterval(59 * 60)))
        XCTAssertFalse(policy.isOpen(at: start.addingTimeInterval(60 * 60)))

        policy.touch(at: start.addingTimeInterval(50 * 60))
        XCTAssertTrue(policy.isOpen(at: start.addingTimeInterval(100 * 60)))
    }

    func testClockGoingBackLocks() {
        var policy = VaultLockPolicy()
        let now = Date()
        policy.touch(at: now)
        XCTAssertFalse(policy.isOpen(at: now.addingTimeInterval(-1)))
    }

    func testResetLocks() {
        var policy = VaultLockPolicy(timeoutMinutes: 15)
        policy.touch(at: Date())
        policy.reset()
        XCTAssertNil(policy.lastUse)
        XCTAssertFalse(policy.isOpen(at: Date()))
    }

    func testTimeoutIsAtLeastOneMinute() {
        XCTAssertEqual(VaultLockPolicy(timeoutMinutes: 0).timeout, 60)
        XCTAssertEqual(VaultLockPolicy(timeoutMinutes: 15).timeout, 900)
    }
}

final class VaultFingerprintTests: XCTestCase {

    private let key = VaultCrypto.makeKey()

    func testPayloadAndCaptureOfTheSameContentMatch() {
        XCTAssertEqual(
            VaultFingerprint.of(VaultPayload(itemType: .text, title: "ignored", content: "pw"), key: key),
            VaultFingerprint.of(ClipboardContent.text("pw"), key: key))
        XCTAssertEqual(
            VaultFingerprint.of(VaultPayload(itemType: .image, imageData: Data([1, 2])), key: key),
            VaultFingerprint.of(ClipboardContent.image(Data([1, 2])), key: key))
        XCTAssertEqual(
            VaultFingerprint.of(VaultPayload(itemType: .combined, content: "a", imageData: Data([3])), key: key),
            VaultFingerprint.of(ClipboardContent.combined("a", Data([3])), key: key))
        XCTAssertEqual(
            VaultFingerprint.of(VaultPayload(itemType: .file, fileData: Data([4]), fileName: "k.pem"), key: key),
            VaultFingerprint.of(ClipboardContent.file(URL(fileURLWithPath: "/x/k.pem"), "public.data", Data([4])), key: key))
    }

    func testTypeKeyAndBoundariesMatter() {
        let text = VaultFingerprint.of(ClipboardContent.text("pw"), key: key)
        XCTAssertNotEqual(text, VaultFingerprint.of(ClipboardContent.text("pw"), key: VaultCrypto.makeKey()))
        XCTAssertNotEqual(text, VaultFingerprint.of(ClipboardContent.combined("pw", Data()), key: key))
        XCTAssertNotEqual(
            VaultFingerprint.of(ClipboardContent.combined("ab", Data("c".utf8)), key: key),
            VaultFingerprint.of(ClipboardContent.combined("a", Data("bc".utf8)), key: key))
    }

    func testFingerprintDoesNotContainTheContent() {
        let fingerprint = VaultFingerprint.of(ClipboardContent.text("hunter2"), key: key)
        XCTAssertFalse(fingerprint.contains("hunter2"))
        XCTAssertEqual(Data(base64Encoded: fingerprint)?.count, 32)
    }

    func testStoreKeepsFingerprints() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VaultStore(root: root)
        XCTAssertTrue(store.loadFingerprints().isEmpty)
        try store.saveFingerprints(["a", "b"])
        XCTAssertEqual(store.loadFingerprints(), ["a", "b"])
        XCTAssertFalse(store.hasEntries)  // not an entry file
    }
}

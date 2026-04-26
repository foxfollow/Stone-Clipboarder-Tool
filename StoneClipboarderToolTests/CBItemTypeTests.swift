import XCTest
@testable import StoneClipboarderTool

final class CBItemTypeTests: XCTestCase {

    func testRawValuesAreStable() {
        XCTAssertEqual(CBItemType.text.rawValue, "text")
        XCTAssertEqual(CBItemType.image.rawValue, "image")
        XCTAssertEqual(CBItemType.file.rawValue, "file")
        XCTAssertEqual(CBItemType.combined.rawValue, "combined")
    }

    func testAllCasesCount() {
        XCTAssertEqual(CBItemType.allCases.count, 4)
    }

    func testSFSymbolNamesAreNonEmpty() {
        for type in CBItemType.allCases {
            XCTAssertFalse(type.sfSybmolName.isEmpty, "Empty SF symbol for \(type)")
        }
    }

    func testSymbolNamesUnique() {
        let names = CBItemType.allCases.map(\.sfSybmolName)
        XCTAssertEqual(Set(names).count, names.count, "Duplicate SF symbol names")
    }

    func testSymbolColorsExistForAllCases() {
        for type in CBItemType.allCases {
            _ = type.sybmolColor
        }
    }

    func testCodableRoundTrip() throws {
        for type in CBItemType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(CBItemType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }
}

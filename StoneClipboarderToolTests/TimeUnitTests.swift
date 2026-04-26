import XCTest
@testable import StoneClipboarderTool

final class TimeUnitTests: XCTestCase {

    func testMultipliers() {
        XCTAssertEqual(TimeUnit.seconds.multiplier, 1)
        XCTAssertEqual(TimeUnit.minutes.multiplier, 60)
        XCTAssertEqual(TimeUnit.hours.multiplier, 3600)
        XCTAssertEqual(TimeUnit.days.multiplier, 86400)
    }

    func testRawValues() {
        XCTAssertEqual(TimeUnit.seconds.rawValue, "Seconds")
        XCTAssertEqual(TimeUnit.minutes.rawValue, "Minutes")
        XCTAssertEqual(TimeUnit.hours.rawValue, "Hours")
        XCTAssertEqual(TimeUnit.days.rawValue, "Days")
    }

    func testAllCasesCount() {
        XCTAssertEqual(TimeUnit.allCases.count, 4)
    }

    func testMultipliersStrictlyIncreasing() {
        let ordered: [TimeUnit] = [.seconds, .minutes, .hours, .days]
        let multipliers = ordered.map(\.multiplier)
        for i in 1..<multipliers.count {
            XCTAssertGreaterThan(multipliers[i], multipliers[i - 1])
        }
    }
}

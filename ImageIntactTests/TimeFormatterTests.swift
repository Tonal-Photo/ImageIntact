import XCTest
@testable import ImageIntact

final class TimeFormatterTests: XCTestCase {
    func testFormatDuration() {
        XCTAssertEqual(TimeFormatter.formatDuration(45.5), "45s")
        XCTAssertEqual(TimeFormatter.formatDuration(65), "1m 5s")
        XCTAssertEqual(TimeFormatter.formatDuration(125.5), "2m 5s")
        // Intentionally drops seconds for hour-scale durations
        XCTAssertEqual(TimeFormatter.formatDuration(3665), "1h 1m")
    }
}

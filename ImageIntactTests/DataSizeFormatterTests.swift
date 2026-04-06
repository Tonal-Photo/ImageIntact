import XCTest
@testable import ImageIntact

final class DataSizeFormatterTests: XCTestCase {

    /// Normalize non-breaking spaces and locale-specific decimal separators for assertions
    private func normalized(_ s: String) -> String {
        s.replacingOccurrences(of: "[\\u{00A0}\\u{202F}]", with: " ", options: .regularExpression)
         .replacingOccurrences(of: ",", with: ".")
    }

    func testExactBoundaries() {
        XCTAssertEqual(normalized(DataSizeFormatter.format(1024)), "1 KB")
        XCTAssertEqual(normalized(DataSizeFormatter.format(1024 * 1024)), "1 MB")
        XCTAssertEqual(normalized(DataSizeFormatter.format(1024 * 1024 * 1024)), "1 GB")
    }

    func testFractionalSizes() {
        XCTAssertEqual(normalized(DataSizeFormatter.format(1024 * 1024 + 512 * 1024)), "1.5 MB")
    }

    func testZeroBytes() {
        // allowsNonnumericFormatting = false → numeric "0" not "Zero"
        let result = normalized(DataSizeFormatter.format(0))
        XCTAssertTrue(result.contains("0"), "Expected numeric zero in: \(result)")
    }
}

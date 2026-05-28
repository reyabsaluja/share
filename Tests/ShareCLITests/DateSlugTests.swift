import XCTest
@testable import share

final class DateSlugTests: XCTestCase {
    func testSlugFormat() {
        let slug = DateSlug.current()
        // Format: YYYY-MM-DD-HHMMSS
        let pattern = #"^\d{4}-\d{2}-\d{2}-\d{6}$"#
        XCTAssertNotNil(slug.range(of: pattern, options: .regularExpression), "Slug '\(slug)' doesn't match expected format")
    }
}

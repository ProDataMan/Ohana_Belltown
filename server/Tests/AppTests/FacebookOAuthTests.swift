import XCTest
@testable import App

final class FacebookOAuthTests: XCTestCase {
    func testParsesFullDateDroppingTheYear() throws {
        XCTAssertEqual(FacebookOAuth.parseBirthday("07/26/1990"), "07-26")
    }

    func testParsesMonthAndDayWithNoYearShared() throws {
        XCTAssertEqual(FacebookOAuth.parseBirthday("3/5"), "03-05")
    }

    func testReturnsNilForYearOnlySharing() throws {
        // Some users only share the year, not the month/day — nothing usable here.
        XCTAssertNil(FacebookOAuth.parseBirthday("1990"))
    }

    func testReturnsNilForGarbage() throws {
        XCTAssertNil(FacebookOAuth.parseBirthday(""))
        XCTAssertNil(FacebookOAuth.parseBirthday("not-a-date"))
        XCTAssertNil(FacebookOAuth.parseBirthday("13/40/1990"))
    }
}

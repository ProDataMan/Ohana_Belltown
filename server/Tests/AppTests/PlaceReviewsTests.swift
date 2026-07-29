import XCTest
@testable import App

final class PlaceReviewsTests: XCTestCase {
    private func review(rating: Int?, author: String = "Someone") -> GoogleReview {
        GoogleReview(author_name: author, profile_photo_url: nil, rating: rating, relative_time_description: "a week ago", text: "Review text")
    }

    func testExcludesOneStarReviewsFromTheWidget() throws {
        let details = GooglePlaceDetailsResult(
            photos: nil,
            reviews: [review(rating: 5), review(rating: 1), review(rating: 3)],
            rating: nil, user_ratings_total: nil
        )
        let summary = PlaceReviewsSummary.build(from: details)
        XCTAssertEqual(summary.reviews.map { $0.rating }, [5, 3])
    }

    func testKeepsTwoThroughFiveStarReviews() throws {
        let details = GooglePlaceDetailsResult(
            photos: nil,
            reviews: [review(rating: 2), review(rating: 3), review(rating: 4), review(rating: 5)],
            rating: nil, user_ratings_total: nil
        )
        let summary = PlaceReviewsSummary.build(from: details)
        XCTAssertEqual(summary.reviews.map { $0.rating }, [2, 3, 4, 5])
    }

    func testTreatsAMissingRatingAsExcluded() throws {
        // Google's API marks rating as optional; a review with no rating at
        // all shouldn't be assumed safe to show any more than a 1-star one.
        let details = GooglePlaceDetailsResult(
            photos: nil, reviews: [review(rating: nil)], rating: nil, user_ratings_total: nil
        )
        let summary = PlaceReviewsSummary.build(from: details)
        XCTAssertTrue(summary.reviews.isEmpty)
    }

    func testOverallRatingAndTotalRatingsStayUnfilteredAndReal() throws {
        // The aggregate stats must reflect Google's real numbers regardless
        // of which individual review snippets are shown, so the site never
        // misrepresents its actual rating.
        let details = GooglePlaceDetailsResult(
            photos: nil, reviews: [review(rating: 1)], rating: 4.6, user_ratings_total: 812
        )
        let summary = PlaceReviewsSummary.build(from: details)
        XCTAssertTrue(summary.reviews.isEmpty)
        XCTAssertEqual(summary.overallRating, 4.6)
        XCTAssertEqual(summary.totalRatings, 812)
    }

    func testHandlesNoReviewsAtAll() throws {
        let details = GooglePlaceDetailsResult(photos: nil, reviews: nil, rating: nil, user_ratings_total: nil)
        let summary = PlaceReviewsSummary.build(from: details)
        XCTAssertTrue(summary.reviews.isEmpty)
    }
}

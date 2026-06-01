import XCTest
@testable import GrindScale

final class GrindScaleIOSTests: XCTestCase {
    func testProfilesExist() {
        XCTAssertFalse(Profiles.all.isEmpty)
    }

    func testRecommendationForLowCount() {
        let stats = AnalysisStats(
            particleCount: 10,
            mean: 0,
            std: 0,
            cv: 0,
            d10: 0,
            d50: 0,
            d90: 0,
            fineRatio: 0,
            targetRatio: 0,
            coarseRatio: 0,
            bimodal: false,
            uniformityScore: 0,
            mode: .relative,
            unitLabel: "px"
        )
        let text = RecommendationService.text(for: stats, profileName: "手沖咖啡")
        XCTAssertTrue(text.contains("樣本量"))
    }
}

import XCTest
@testable import CommandNest

final class UpdateServiceTests: XCTestCase {
    func testVersionComparisonHandlesTagsAndBuildSuffixes() {
        XCTAssertEqual(GitHubUpdateService.compareVersions("v1.0.1", "1.0.0"), .orderedDescending)
        XCTAssertEqual(GitHubUpdateService.compareVersions("v1.0.1", "1.0.1"), .orderedSame)
        XCTAssertEqual(GitHubUpdateService.compareVersions("v1.0.1-2", "1.0.1"), .orderedDescending)
        XCTAssertEqual(GitHubUpdateService.compareVersions("v1.0", "1.0.1"), .orderedAscending)
    }

    func testIsReleaseNewerThanCurrentVersion() {
        XCTAssertTrue(GitHubUpdateService.isRelease("v2.0.0", newerThan: "1.9.9"))
        XCTAssertFalse(GitHubUpdateService.isRelease("v1.0.1", newerThan: "1.0.1"))
    }
}

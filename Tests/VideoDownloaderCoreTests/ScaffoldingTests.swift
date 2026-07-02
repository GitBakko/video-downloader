import XCTest
@testable import VideoDownloaderCore

final class ScaffoldingTests: XCTestCase {
    // Proves the test target can build and @testable import the library module.
    // This whole file is expected to be removed once real feature tests exist.
    func testScaffoldModuleIsImportable() {
        XCTAssertTrue(VideoDownloaderScaffold.isReady)
    }
}

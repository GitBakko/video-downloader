import XCTest
@testable import VideoDownloaderCore

final class HostArchitectureTests: XCTestCase {
    func test_rawValuesMatchArchTokens() {
        XCTAssertEqual(HostArchitecture.arm64.rawValue, "arm64")
        XCTAssertEqual(HostArchitecture.x86_64.rawValue, "x86_64")
    }

    // Spec §3.1/§10: the kernel SIGKILLs unsigned arm64 binaries → only arm64
    // needs the ad-hoc `codesign -s -` fallback.
    func test_onlyArm64RequiresAdHocSignature() {
        XCTAssertTrue(HostArchitecture.arm64.requiresAdHocSignature)
        XCTAssertFalse(HostArchitecture.x86_64.requiresAdHocSignature)
    }
}

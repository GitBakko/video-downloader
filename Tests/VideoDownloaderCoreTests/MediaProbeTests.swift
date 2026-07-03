import XCTest
@testable import VideoDownloaderCore

final class MediaProbeTests: XCTestCase {

    private final class StubBinaries: BinaryProviding, @unchecked Sendable {
        let ytDlpURL: URL
        let ffmpegDirectory: URL
        let ytDlpVersion: String?
        init(ytDlpURL: URL, ffmpegDirectory: URL, ytDlpVersion: String?) {
            self.ytDlpURL = ytDlpURL
            self.ffmpegDirectory = ffmpegDirectory
            self.ytDlpVersion = ytDlpVersion
        }
        func ensureInstalled(onProgress: @escaping @Sendable (Double) -> Void) async throws { onProgress(1) }
        func updateYtDlp() async throws {}
    }

    private final class SpyRunner: ProbeRunning, @unchecked Sendable {
        var receivedExecutable: URL?
        var receivedArguments: [String]?
        let result: ProbeResult
        init(result: ProbeResult) { self.result = result }
        func run(executable: URL, arguments: [String]) async throws -> ProbeResult {
            receivedExecutable = executable
            receivedArguments = arguments
            return result
        }
    }

    func test_probe_invokes_ytDlp_with_dumpJson_arguments() async {
        let exe = URL(fileURLWithPath: "/tmp/bin/yt-dlp")
        let bins = StubBinaries(ytDlpURL: exe,
                                ffmpegDirectory: URL(fileURLWithPath: "/tmp/bin"),
                                ytDlpVersion: "2026.01.01")
        let spy = SpyRunner(result: ProbeResult(stdout: Data("{}".utf8), stderr: Data(), exitCode: 0))
        let probe = MediaProbe(binaries: bins, runner: spy)

        _ = try? await probe.probe(url: "https://example.com/watch?v=x")

        XCTAssertEqual(spy.receivedExecutable, exe)
        // Core args are fixed at the ends; optional `--js-runtimes <name>:<path>`
        // may appear in between when a JS runtime is installed (env-dependent).
        let args = spy.receivedArguments ?? []
        XCTAssertEqual(Array(args.prefix(2)), ["-J", "--no-warnings"])
        XCTAssertEqual(args.last, "https://example.com/watch?v=x")
    }

    func test_probe_throws_lastSignificantStderrLine_on_nonzero_exit() async {
        let bins = StubBinaries(ytDlpURL: URL(fileURLWithPath: "/tmp/yt-dlp"),
                                ffmpegDirectory: URL(fileURLWithPath: "/tmp"),
                                ytDlpVersion: nil)
        let stderr = Data("WARNING: ignore me\nERROR: Video unavailable\n".utf8)
        let spy = SpyRunner(result: ProbeResult(stdout: Data(), stderr: stderr, exitCode: 1))
        let probe = MediaProbe(binaries: bins, runner: spy)

        do {
            _ = try await probe.probe(url: "https://example.com/private")
            XCTFail("expected probe to throw on non-zero exit")
        } catch {
            XCTAssertEqual((error as? MediaProbeError)?.errorDescription, "ERROR: Video unavailable")
        }
    }
}

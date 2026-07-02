import XCTest
@testable import VideoDownloaderCore

final class BinaryURLResolverTests: XCTestCase {
    let resolver = BinaryURLResolver()

    func test_ytDlpURL_isArchIndependentMacOSBuild() {
        XCTAssertEqual(
            resolver.ytDlpDownloadURL().absoluteString,
            "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
        )
    }

    func test_ffmpegURL_arm64() {
        XCTAssertEqual(
            resolver.ffmpegDownloadURL(arch: .arm64).absoluteString,
            "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-arm64"
        )
    }

    // Host token x86_64 maps to asset token "x64".
    func test_ffmpegURL_x86_64_usesX64Token() {
        XCTAssertEqual(
            resolver.ffmpegDownloadURL(arch: .x86_64).absoluteString,
            "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-x64"
        )
    }

    func test_ffprobeURL_arm64() {
        XCTAssertEqual(
            resolver.ffprobeDownloadURL(arch: .arm64).absoluteString,
            "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffprobe-darwin-arm64"
        )
    }

    func test_ffprobeURL_x86_64() {
        XCTAssertEqual(
            resolver.ffprobeDownloadURL(arch: .x86_64).absoluteString,
            "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffprobe-darwin-x64"
        )
    }
}

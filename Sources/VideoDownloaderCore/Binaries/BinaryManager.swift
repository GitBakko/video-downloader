import Foundation

// MARK: - HostArchitecture (pure)

public enum HostArchitecture: String, Sendable, CaseIterable {
    case arm64
    case x86_64

    /// The architecture this build was compiled for. For a natively built app
    /// this equals the CPU it runs on (Apple Silicon -> arm64, Intel -> x86_64).
    public static func current() -> HostArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }

    /// arm64 binaries must carry at least an ad-hoc signature or the kernel
    /// SIGKILLs them (spec §3.1 / §10). x86_64 binaries do not require this.
    public var requiresAdHocSignature: Bool { self == .arm64 }
}

// MARK: - BinaryURLResolver (pure)

public struct BinaryURLResolver: Sendable {
    public init() {}

    /// yt-dlp standalone macOS build. A single self-contained binary that runs
    /// on both Apple Silicon and Intel, so it is NOT architecture-specific.
    public func ytDlpDownloadURL() -> URL {
        URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    }

    /// Static ffmpeg build, architecture-matched.
    /// Source: eugeneware/ffmpeg-static GitHub Releases — the best-documented
    /// source shipping BOTH arm64 and x86_64 macOS builds as raw (uncompressed)
    /// binaries, together with ffprobe (spec §3.1 / §10; no official static
    /// macOS ffmpeg exists).
    public func ffmpegDownloadURL(arch: HostArchitecture) -> URL {
        Self.ffmpegStaticURL(tool: "ffmpeg", arch: arch)
    }

    /// Static ffprobe build, architecture-matched (same source as ffmpeg).
    public func ffprobeDownloadURL(arch: HostArchitecture) -> URL {
        Self.ffmpegStaticURL(tool: "ffprobe", arch: arch)
    }

    /// Token used in the ffmpeg-static asset name for a given architecture.
    static func assetSuffix(for arch: HostArchitecture) -> String {
        switch arch {
        case .arm64:  return "arm64"
        case .x86_64: return "x64"
        }
    }

    private static func ffmpegStaticURL(tool: String, arch: HostArchitecture) -> URL {
        let asset = "\(tool)-darwin-\(assetSuffix(for: arch))"
        return URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/\(asset)")!
    }
}

// MARK: - BinaryLayout (pure path building)

public struct BinaryLayout: Sendable {
    /// Root of the app's managed folder (e.g. .../Application Support/VideoDownloader).
    public let supportDirectory: URL

    public init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    /// Default location under the user's Library (spec §3.1).
    public static func standard(fileManager: FileManager = .default) -> BinaryLayout {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return BinaryLayout(supportDirectory: base.appendingPathComponent("VideoDownloader", isDirectory: true))
    }

    /// `.../VideoDownloader/bin` — passed to yt-dlp as `--ffmpeg-location`.
    public var binDirectory: URL {
        supportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    public var ytDlpURL: URL { binDirectory.appendingPathComponent("yt-dlp", isDirectory: false) }
    public var ffmpegURL: URL { binDirectory.appendingPathComponent("ffmpeg", isDirectory: false) }
    public var ffprobeURL: URL { binDirectory.appendingPathComponent("ffprobe", isDirectory: false) }
}

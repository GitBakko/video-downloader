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

// MARK: - Install planning (pure)

public struct BinaryDownloadTask: Equatable, Sendable {
    public let remote: URL
    public let destination: URL
    public init(remote: URL, destination: URL) {
        self.remote = remote
        self.destination = destination
    }
}

public extension BinaryURLResolver {
    /// The full set of downloads required for a fresh install, arch-matched.
    func installTasks(layout: BinaryLayout, arch: HostArchitecture) -> [BinaryDownloadTask] {
        [
            BinaryDownloadTask(remote: ytDlpDownloadURL(), destination: layout.ytDlpURL),
            BinaryDownloadTask(remote: ffmpegDownloadURL(arch: arch), destination: layout.ffmpegURL),
            BinaryDownloadTask(remote: ffprobeDownloadURL(arch: arch), destination: layout.ffprobeURL),
        ]
    }
}

/// Pure: keeps only the tasks whose destination is not yet installed.
public func pendingBinaryTasks(
    _ tasks: [BinaryDownloadTask],
    isInstalled: (URL) -> Bool
) -> [BinaryDownloadTask] {
    tasks.filter { !isInstalled($0.destination) }
}

// MARK: - BinaryProviding protocol (owned by this file)

public protocol BinaryProviding: AnyObject, Sendable {
    var ytDlpURL: URL { get }
    var ffmpegDirectory: URL { get }
    var ytDlpVersion: String? { get }
    func ensureInstalled() async throws
    func updateYtDlp() async throws
}

public enum BinaryManagerError: Error, Equatable {
    case downloadFailed(url: URL, status: Int)
}

// MARK: - BinaryManager (side effects: network + filesystem + Process)

/// `@unchecked Sendable` is justified: every stored dependency is either an
/// immutable constant (`layout`, `resolver`, `arch`, `fileManager`, `session`)
/// or the mutable `ytDlpVersion`, whose reads/writes are serialized by
/// `versionLock`. So no shared mutable state is ever touched unsynchronized.
public final class BinaryManager: BinaryProviding, @unchecked Sendable {
    private let layout: BinaryLayout
    private let resolver: BinaryURLResolver
    private let arch: HostArchitecture
    private let fileManager: FileManager
    private let session: URLSession

    // `ytDlpVersion` is written off the main actor (ensureInstalled/updateYtDlp)
    // and read on the main actor (SettingsView); the lock prevents a torn read.
    private let versionLock = NSLock()
    private var _ytDlpVersion: String?
    public var ytDlpVersion: String? {
        versionLock.lock(); defer { versionLock.unlock() }
        return _ytDlpVersion
    }
    private func setYtDlpVersion(_ value: String?) {
        versionLock.lock(); _ytDlpVersion = value; versionLock.unlock()
    }

    public init(
        layout: BinaryLayout = .standard(),
        resolver: BinaryURLResolver = BinaryURLResolver(),
        arch: HostArchitecture = .current(),
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) {
        self.layout = layout
        self.resolver = resolver
        self.arch = arch
        self.fileManager = fileManager
        self.session = session
    }

    public var ytDlpURL: URL { layout.ytDlpURL }
    public var ffmpegDirectory: URL { layout.binDirectory }

    /// Spec §3.1 / §5.1: download any missing binary for the host arch, then
    /// make each runnable (unquarantine + execute bit + ad-hoc sign on arm64).
    public func ensureInstalled() async throws {
        try fileManager.createDirectory(at: layout.binDirectory, withIntermediateDirectories: true)
        let all = resolver.installTasks(layout: layout, arch: arch)
        let pending = pendingBinaryTasks(all) { self.fileManager.isExecutableFile(atPath: $0.path) }
        for task in pending {
            try await download(task.remote, to: task.destination)
        }
        setYtDlpVersion(try? await readYtDlpVersion())
    }

    /// Spec §5.3: re-download the latest yt-dlp and refresh the version.
    public func updateYtDlp() async throws {
        try fileManager.createDirectory(at: layout.binDirectory, withIntermediateDirectories: true)
        try await download(resolver.ytDlpDownloadURL(), to: layout.ytDlpURL)
        setYtDlpVersion(try? await readYtDlpVersion())
    }

    // MARK: Side effects

    private func download(_ remote: URL, to destination: URL) async throws {
        let (tempURL, response) = try await session.download(from: remote)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? fileManager.removeItem(at: tempURL)
            throw BinaryManagerError.downloadFailed(url: remote, status: http.statusCode)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        try await prepareExecutable(destination)
    }

    /// Remove the Gatekeeper quarantine attribute, set the execute bit, and
    /// ad-hoc sign unsigned arm64 binaries (spec §3.1 / §10). URLSession
    /// downloads are usually not quarantined, so `xattr -d` is best-effort.
    private func prepareExecutable(_ url: URL) async throws {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        _ = try? await Self.run("/usr/bin/xattr", ["-d", "com.apple.quarantine", url.path])
        if arch.requiresAdHocSignature {
            _ = try? await Self.run("/usr/bin/codesign", ["-s", "-", "--force", url.path])
        }
    }

    private func readYtDlpVersion() async throws -> String {
        let out = try await Self.run(layout.ytDlpURL.path, ["--version"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a short-lived tool and returns its stdout. The blocking pipe read and
    /// `waitUntilExit()` run on a global queue so no cooperative thread is blocked.
    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

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

    /// yt-dlp standalone macOS build — the PyInstaller **onedir** archive
    /// (`yt-dlp_macos.zip`), NOT the onefile binary. The onefile re-extracts its
    /// bundled Python runtime on *every* invocation (~24s each on Intel); the
    /// onedir build extracts once at install time so subsequent probes are fast
    /// (~0.66s). It runs on both Apple Silicon and Intel, so it is NOT
    /// architecture-specific. Unpacking it yields an inner `yt-dlp_macos`
    /// executable alongside its `_internal/` runtime directory.
    public func ytDlpDownloadURL() -> URL {
        URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!
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

    /// Directory holding the extracted yt-dlp onedir bundle: the inner
    /// `yt-dlp_macos` executable plus its `_internal/` Python runtime. Running
    /// the executable from here (with `_internal/` beside it) is what makes
    /// yt-dlp fast — unlike the onefile build, nothing is re-extracted per run.
    public var ytDlpDirectory: URL { binDirectory.appendingPathComponent("yt-dlp", isDirectory: true) }

    /// The runnable yt-dlp executable *inside* the extracted onedir bundle.
    public var ytDlpURL: URL { ytDlpDirectory.appendingPathComponent("yt-dlp_macos", isDirectory: false) }
    public var ffmpegURL: URL { binDirectory.appendingPathComponent("ffmpeg", isDirectory: false) }
    public var ffprobeURL: URL { binDirectory.appendingPathComponent("ffprobe", isDirectory: false) }
}

// MARK: - Install planning (pure)

public struct BinaryDownloadTask: Equatable, Sendable {
    public let remote: URL
    public let destination: URL
    /// When non-nil, `remote` is a `.zip` archive that must be **extracted** into
    /// this directory (replacing any prior contents); `destination` is then the
    /// runnable file produced by extraction (yt-dlp's inner executable). When
    /// nil, `remote` is a single file downloaded directly to `destination`
    /// (ffmpeg / ffprobe).
    public let extractDirectory: URL?
    public init(remote: URL, destination: URL, extractDirectory: URL? = nil) {
        self.remote = remote
        self.destination = destination
        self.extractDirectory = extractDirectory
    }
}

public extension BinaryURLResolver {
    /// The full set of downloads required for a fresh install, arch-matched.
    /// yt-dlp is a zip that is extracted into `layout.ytDlpDirectory`; its
    /// destination (the "installed?" marker) is the inner executable. ffmpeg and
    /// ffprobe are plain single-file downloads.
    func installTasks(layout: BinaryLayout, arch: HostArchitecture) -> [BinaryDownloadTask] {
        [
            BinaryDownloadTask(
                remote: ytDlpDownloadURL(),
                destination: layout.ytDlpURL,
                extractDirectory: layout.ytDlpDirectory
            ),
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
    /// Download any missing binaries, reporting the overall progress across all
    /// pending files as a fraction in `0...1`.
    func ensureInstalled(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func updateYtDlp() async throws
}

public extension BinaryProviding {
    /// Convenience for callers that don't care about progress.
    func ensureInstalled() async throws {
        try await ensureInstalled(onProgress: { _ in })
    }
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
    /// `onProgress` receives the combined fraction (`0...1`) across all pending
    /// files as bytes arrive.
    public func ensureInstalled(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try fileManager.createDirectory(at: layout.binDirectory, withIntermediateDirectories: true)
        let all = resolver.installTasks(layout: layout, arch: arch)
        let pending = pendingBinaryTasks(all) { self.fileManager.isExecutableFile(atPath: $0.path) }
        if pending.isEmpty {
            onProgress(1)
        } else {
            let reporter = OverallProgressReporter(fileCount: pending.count, report: onProgress)
            for (index, task) in pending.enumerated() {
                try await install(task) { written, expected in
                    reporter.update(file: index, written: written, expected: expected)
                }
                reporter.markComplete(file: index)
            }
        }
        // Warm-up: the first run of the freshly extracted yt-dlp pays a one-time
        // ~30s Gatekeeper scan. Doing it here — behind the progress bar — means
        // the user's first real probe is already fast.
        setYtDlpVersion(try? await readYtDlpVersion())
    }

    /// Spec §5.3: re-download the latest yt-dlp (the onedir zip), re-extract it,
    /// and refresh the version.
    public func updateYtDlp() async throws {
        try fileManager.createDirectory(at: layout.binDirectory, withIntermediateDirectories: true)
        try await downloadAndExtract(
            resolver.ytDlpDownloadURL(),
            into: layout.ytDlpDirectory,
            executable: layout.ytDlpURL
        )
        setYtDlpVersion(try? await readYtDlpVersion())
    }

    // MARK: Side effects

    /// Installs one pending task: either a plain single-file download
    /// (ffmpeg / ffprobe) or a download-then-extract of the yt-dlp onedir zip.
    private func install(
        _ task: BinaryDownloadTask,
        onFileProgress: @escaping @Sendable (_ written: Int64, _ expected: Int64) -> Void
    ) async throws {
        if let extractDirectory = task.extractDirectory {
            try await downloadAndExtract(
                task.remote,
                into: extractDirectory,
                executable: task.destination,
                onFileProgress: onFileProgress
            )
        } else {
            try await download(task.remote, to: task.destination, onFileProgress: onFileProgress)
        }
    }

    /// Delegate-driven download so we can surface byte-level progress. The
    /// `DownloadCoordinator` reports `totalBytesWritten / totalBytesExpectedToWrite`
    /// as data arrives, stages the finished file out of the (soon-to-be-deleted)
    /// temp location, and bridges completion back to async. A non-2xx status is
    /// mapped to `downloadFailed`. Returns the staged temp file's URL.
    private func stageDownload(
        _ remote: URL,
        onFileProgress: @escaping @Sendable (_ written: Int64, _ expected: Int64) -> Void
    ) async throws -> URL {
        let coordinator = DownloadCoordinator(fileManager: fileManager, onProgress: onFileProgress)
        let task = session.downloadTask(with: remote)
        task.delegate = coordinator
        return try await coordinator.run(task: task)
    }

    /// Download a single file into place and make it executable (ffmpeg/ffprobe).
    private func download(
        _ remote: URL,
        to destination: URL,
        onFileProgress: @escaping @Sendable (_ written: Int64, _ expected: Int64) -> Void = { _, _ in }
    ) async throws {
        let staged = try await stageDownload(remote, onFileProgress: onFileProgress)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
        try await prepareExecutable(destination)
    }

    /// Download the yt-dlp onedir `.zip` and unpack it into `extractDirectory`,
    /// replacing any previous extraction, then make the inner `executable`
    /// runnable. `ditto -x -k` unpacks a macOS zip cleanly (preserving the
    /// onedir layout of executable + `_internal/`); the download itself has no
    /// `.zip` suffix but ditto reads the archive by content, not extension.
    private func downloadAndExtract(
        _ remote: URL,
        into extractDirectory: URL,
        executable: URL,
        onFileProgress: @escaping @Sendable (_ written: Int64, _ expected: Int64) -> Void = { _, _ in }
    ) async throws {
        let staged = try await stageDownload(remote, onFileProgress: onFileProgress)
        defer { try? fileManager.removeItem(at: staged) }
        if fileManager.fileExists(atPath: extractDirectory.path) {
            try fileManager.removeItem(at: extractDirectory)
        }
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        _ = try await Self.run("/usr/bin/ditto", ["-x", "-k", staged.path, extractDirectory.path])
        try await prepareYtDlpExecutable(directory: extractDirectory, executable: executable)
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

    /// Make the extracted yt-dlp bundle runnable: set the execute bit on the
    /// inner executable, strip quarantine **recursively** across the whole
    /// bundle (executable + `_internal/`, best-effort), and on arm64 ad-hoc sign
    /// the inner executable.
    private func prepareYtDlpExecutable(directory: URL, executable: URL) async throws {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        _ = try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", directory.path])
        if arch.requiresAdHocSignature {
            _ = try? await Self.run("/usr/bin/codesign", ["-s", "-", "--force", executable.path])
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

// MARK: - Progress plumbing (side effects, thread-safe)

/// Combines per-file byte counts into a single `0...1` install fraction.
///
/// When every pending file's length is known it uses byte weighting
/// (`Σwritten / Σexpected`); if any file's length is still unknown (e.g. it
/// hasn't started, or the server omitted `Content-Length` → -1) it falls back
/// to the mean of the per-file fractions (equal per-file weighting). Reports are
/// throttled so slow byte deltas don't spam the UI.
final class OverallProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let fileCount: Int
    private var expected: [Int64]   // per file; <= 0 means "unknown"
    private var written: [Int64]
    private var completed: [Bool]
    private let report: @Sendable (Double) -> Void
    private var lastReported = -1.0

    init(fileCount: Int, report: @escaping @Sendable (Double) -> Void) {
        self.fileCount = max(fileCount, 1)
        self.expected = Array(repeating: -1, count: self.fileCount)
        self.written = Array(repeating: 0, count: self.fileCount)
        self.completed = Array(repeating: false, count: self.fileCount)
        self.report = report
    }

    func update(file index: Int, written w: Int64, expected e: Int64) {
        guard expected.indices.contains(index) else { return }
        lock.lock()
        written[index] = w
        if e > 0 { expected[index] = e }
        let overall = computeLocked()
        let shouldReport = overall >= 1.0 || overall - lastReported >= 0.01
        if shouldReport { lastReported = overall }
        lock.unlock()
        if shouldReport { report(overall) }
    }

    func markComplete(file index: Int) {
        guard expected.indices.contains(index) else { return }
        lock.lock()
        completed[index] = true
        if expected[index] > 0 { written[index] = expected[index] }
        let overall = computeLocked()
        lastReported = overall
        lock.unlock()
        report(overall)
    }

    private func computeLocked() -> Double {
        if expected.allSatisfy({ $0 > 0 }) {
            let total = expected.reduce(0, +)
            if total > 0 {
                let done = zip(written, expected).reduce(Int64(0)) { $0 + min($1.0, $1.1) }
                return min(Double(done) / Double(total), 1.0)
            }
        }
        var sum = 0.0
        for i in 0..<fileCount {
            if completed[i] {
                sum += 1
            } else if expected[i] > 0 {
                sum += min(Double(written[i]) / Double(expected[i]), 1.0)
            }
        }
        return min(sum / Double(fileCount), 1.0)
    }
}

/// Bridges a single `URLSessionDownloadTask` to async: yields byte progress via
/// `onProgress`, resumes with the staged file on `didFinishDownloadingTo`, and
/// throws on transport error or non-2xx status. The finished temp file is moved
/// out of URLSession's scratch location before this delegate method returns,
/// because that file is deleted as soon as it does.
final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let fileManager: FileManager
    private let onProgress: @Sendable (_ written: Int64, _ expected: Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var settled = false

    init(fileManager: FileManager, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.fileManager = fileManager
        self.onProgress = onProgress
    }

    /// Starts `task` and suspends until it finishes (or fails).
    func run(task: URLSessionDownloadTask) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if settled { lock.unlock(); cont.resume(throwing: CancellationError()); return }
            continuation = cont
            lock.unlock()
            task.resume()
        }
    }

    private func settle(_ result: Result<URL, Error>) {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let url = downloadTask.originalRequest?.url ?? location
            settle(.failure(BinaryManagerError.downloadFailed(url: url, status: http.statusCode)))
            return
        }
        let staged = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        do {
            try fileManager.moveItem(at: location, to: staged)
            settle(.success(staged))
        } catch {
            settle(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // Success is already settled in didFinishDownloadingTo; this only fires
        // the failure path for transport-level errors.
        if let error { settle(.failure(error)) }
    }
}

import Foundation

/// Errors surfaced by `DownloadEngine` when the yt-dlp process fails.
public enum DownloadError: Error, Equatable {
    /// The process exited non-zero. `message` is the most meaningful stderr
    /// line; `exitCode` is the raw termination status.
    case failed(message: String, exitCode: Int32)

    /// A human-readable message suitable for `DownloadItem.errorMessage`.
    public var userMessage: String {
        switch self {
        case let .failed(message, _):
            return message.isEmpty ? "Download non riuscito." : message
        }
    }
}

public final class DownloadEngine: Downloading, @unchecked Sendable {

    private let binaries: BinaryProviding

    // Guards the id→Process registry used by cancel(_:).
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]

    public init(binaries: BinaryProviding) {
        self.binaries = binaries
    }

    // MARK: - Downloading

    public func events(for item: DownloadItem, arguments: [String]) -> AsyncThrowingStream<DownloadEvent, Error> {
        let id = item.id
        let executableURL = binaries.ytDlpURL

        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments + [item.url]   // yt-dlp needs the URL as the final positional arg

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            self.store(process, for: id)

            let state = LiveState()

            let worker = Task {
                // Wire up termination BEFORE run() so the callback is never missed;
                // awaiting it (instead of waitUntilExit()) frees the cooperative pool.
                let terminated = ProcessTerminationSignal()
                process.terminationHandler = { _ in terminated.signal() }
                do {
                    try process.run()

                    // Read stdout and stderr CONCURRENTLY so a full pipe buffer
                    // never blocks the child process (classic deadlock). The lines
                    // come from a GCD readability source (see `lines(of:)`), NOT
                    // `FileHandle.bytes`, whose blocking read would wedge a
                    // cooperative-pool thread per pipe and starve the pool once a
                    // few downloads run at once.
                    let outLines = DownloadEngine.lines(of: stdoutPipe.fileHandleForReading)
                    let errLines = DownloadEngine.lines(of: stderrPipe.fileHandleForReading)
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await line in outLines {
                                if let dest = DownloadEngine.destination(from: line) {
                                    await state.setDestination(dest)
                                }
                                guard let event = ProgressParser.parse(line: line) else { continue }
                                switch event {
                                case .processing:
                                    if await state.beginProcessing() {
                                        continuation.yield(.processing)
                                    }
                                case .progress:
                                    continuation.yield(event)
                                case .finished:
                                    break // the engine owns the .finished event
                                }
                            }
                        }
                        group.addTask {
                            for await line in errLines {
                                await state.appendStderr(line)
                            }
                        }
                        await group.waitForAll()
                    }

                    await terminated.wait()
                    self.remove(id)

                    if process.terminationReason == .uncaughtSignal {
                        // Killed by cancel(_:)/terminateAll() → surface as cancellation.
                        continuation.finish(throwing: CancellationError())
                    } else if process.terminationStatus == 0 {
                        // P17: a clean exit whose Destination line we never parsed
                        // still succeeded — fall back to the configured output
                        // directory (from `-o`) so the app can at least reveal the
                        // folder, rather than reporting a completed item with no path.
                        let output = await state.destination
                            ?? DownloadEngine.outputDirectory(from: arguments)
                        continuation.yield(.finished(outputPath: output))
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: DownloadError.failed(
                            message: DownloadEngine.lastMeaningfulLine(await state.stderr),
                            exitCode: process.terminationStatus))
                    }
                } catch {
                    self.remove(id)
                    if process.isRunning { process.terminate() }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
        }
    }

    public func cancel(_ id: UUID) {
        lock.lock()
        let process = processes[id]
        lock.unlock()
        process?.terminate() // SIGTERM → terminationReason == .uncaughtSignal
    }

    /// Terminate every in-flight yt-dlp process this engine started (S16). Each
    /// killed process ends its stream with a `CancellationError`, freeing its slot.
    public func terminateAll() {
        lock.lock()
        let running = Array(processes.values)
        lock.unlock()
        for process in running { process.terminate() }
    }

    // MARK: - Process registry

    private func store(_ process: Process, for id: UUID) {
        lock.lock(); processes[id] = process; lock.unlock()
    }

    private func remove(_ id: UUID) {
        lock.lock(); processes[id] = nil; lock.unlock()
    }

    // MARK: - Non-blocking line reader

    /// Streams `handle`'s bytes as lines WITHOUT blocking a Swift-concurrency
    /// thread. `FileHandle.bytes.lines` runs a synchronous `read()` on the calling
    /// cooperative-pool thread; with several concurrent downloads (two pipes each)
    /// those blocked reads exhaust the pool and every download wedges in
    /// "Preparazione" until one is cancelled (freeing a thread). A GCD readability
    /// source keeps the blocking read off the cooperative pool.
    ///
    /// Splits on `\n` and `\r` — yt-dlp rewrites its progress line with a bare `\r`
    /// (matching the old `.lines` behaviour so `ProgressParser` still sees each
    /// progress update). Empty lines (e.g. the `\n` of a `\r\n`) are dropped.
    static func lines(of handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            var buffer = Data()
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else {   // EOF: the process closed the pipe
                    if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8), !tail.isEmpty {
                        continuation.yield(tail)
                    }
                    fh.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        continuation.yield(line)
                    }
                    buffer.removeSubrange(buffer.startIndex...nl)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    /// Picks the last non-empty stderr line, preferring an `ERROR:` line if any.
    static func lastMeaningfulLine(_ stderr: String) -> String {
        let lines = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let err = lines.last(where: { $0.hasPrefix("ERROR:") }) {
            return err
        }
        return lines.last ?? ""
    }

    /// Extracts the destination file URL from a yt-dlp stdout line, if present.
    /// Handles the common shapes:
    ///   `[download] Destination: /path/File.mp4`
    ///   `[ExtractAudio] Destination: /path/File.mp3`
    ///   `[Merger] Merging formats into "/path/File.mkv"`
    ///   `[download] /path/File.mp4 has already been downloaded`
    static func destination(from line: String) -> URL? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let range = trimmed.range(of: "Destination: ") {
            let path = String(trimmed[range.upperBound...])
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        if let range = trimmed.range(of: "Merging formats into \"") {
            let rest = trimmed[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                return URL(fileURLWithPath: String(rest[..<end]))
            }
        }
        if trimmed.hasPrefix("[download] "),
           let end = trimmed.range(of: " has already been downloaded")?.lowerBound {
            let start = trimmed.index(trimmed.startIndex, offsetBy: "[download] ".count)
            let path = String(trimmed[start..<end])
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        return nil
    }

    /// The destination directory encoded in the `-o` output template (P17). Used
    /// as a fallback output path when a clean download never printed a parseable
    /// `Destination:` line, so the app can still reveal the target folder.
    static func outputDirectory(from arguments: [String]) -> URL? {
        guard let flag = arguments.firstIndex(of: "-o"), flag + 1 < arguments.count else { return nil }
        let directory = (arguments[flag + 1] as NSString).deletingLastPathComponent
        return directory.isEmpty ? nil : URL(fileURLWithPath: directory, isDirectory: true)
    }
}

/// Guards mutable state shared by the concurrently-reading stdout/stderr tasks.
private actor LiveState {
    private(set) var destination: URL?
    private(set) var stderr: String = ""
    private var processingStarted = false

    func setDestination(_ url: URL) { destination = url }
    func appendStderr(_ line: String) { stderr += line + "\n" }

    /// Returns `true` exactly once — the first time post-processing is seen.
    func beginProcessing() -> Bool {
        if processingStarted { return false }
        processingStarted = true
        return true
    }
}

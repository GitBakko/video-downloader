import Foundation

/// Seam over launching a process and collecting stdout/stderr — lets MediaProbe be unit-tested.
public protocol ProbeRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> ProbeResult
}

public struct ProbeResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Default runner backed by Foundation.Process. Reads both pipes concurrently to avoid buffer deadlocks.
public struct SystemProbeRunner: ProbeRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) async throws -> ProbeResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Wire up termination BEFORE run() so the callback is never missed;
        // awaiting it (instead of waitUntilExit()) frees the cooperative pool.
        let terminated = ProcessTerminationSignal()
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        async let out = Self.readAll(outPipe.fileHandleForReading)
        async let err = Self.readAll(errPipe.fileHandleForReading)
        let (outData, errData) = await (out, err)
        // Cancelling the probe Task (M1: cancelling a `.probing` item) kills the
        // yt-dlp process so the wait returns promptly instead of hanging.
        await withTaskCancellationHandler {
            await terminated.wait()
        } onCancel: {
            process.terminate()
        }
        return ProbeResult(stdout: outData, stderr: errData, exitCode: process.terminationStatus)
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let data = (try? handle.readToEnd()) ?? Data()
                cont.resume(returning: data)
            }
        }
    }
}

public enum MediaProbeError: LocalizedError {
    case ytDlpFailed(exitCode: Int32, message: String)
    public var errorDescription: String? {
        switch self {
        case .ytDlpFailed(_, let message): return message
        }
    }
}

/// Real prober: single `yt-dlp -J --no-warnings <url>` (spec §6), parsed by MediaProbeParser.
public struct MediaProbe: MediaProbing {
    private let binaries: BinaryProviding
    private let runner: ProbeRunning

    public init(binaries: BinaryProviding, runner: ProbeRunning = SystemProbeRunner()) {
        self.binaries = binaries
        self.runner = runner
    }

    public func probe(url: String) async throws -> [DownloadItem] {
        let result = try await runner.run(
            executable: binaries.ytDlpURL,
            arguments: ["-J", "--no-warnings", url]
        )
        guard result.exitCode == 0 else {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            throw MediaProbeError.ytDlpFailed(
                exitCode: result.exitCode,
                message: MediaProbe.lastSignificantLine(stderr)
            )
        }
        return try MediaProbeParser.items(fromDumpJSON: result.stdout)   // Phase 2's sole public entry point (result.stdout is Data)
    }

    static func lastSignificantLine(_ text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? "yt-dlp non ha prodotto output."
    }
}

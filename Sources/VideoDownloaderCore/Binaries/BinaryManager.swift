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

import Foundation

/// Recent yt-dlp needs a JavaScript runtime (deno/node/bun) for YouTube's default
/// web client; without one it warns and falls back to a deprecated client that is
/// slower and misses some formats. yt-dlp only auto-enables `deno`, and a GUI app
/// spawns yt-dlp with a minimal `PATH`, so we resolve an available runtime by
/// ABSOLUTE path and pass `--js-runtimes <name>:<path>`.
///
/// Returns `[]` when no runtime is found (yt-dlp then behaves as before).
public enum JSRuntimeResolver {
    /// Resolved once per process (a filesystem probe), reused for every yt-dlp call.
    public static let arguments: [String] = resolve()

    private static func resolve() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Preference order: deno (yt-dlp's best-supported), then node, then bun.
        let candidates: [(name: String, paths: [String])] = [
            ("deno", ["\(home)/.deno/bin/deno", "/opt/homebrew/bin/deno", "/usr/local/bin/deno", "/usr/bin/deno"]),
            ("node", nodePaths(home: home)),
            ("bun",  ["\(home)/.bun/bin/bun", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"]),
        ]

        for candidate in candidates {
            if let path = candidate.paths.first(where: { fm.isExecutableFile(atPath: $0) }) {
                return ["--js-runtimes", "\(candidate.name):\(path)"]
            }
        }
        return []
    }

    private static func nodePaths(home: String) -> [String] {
        var paths = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        // nvm installs node at ~/.nvm/versions/node/<version>/bin/node — prefer the newest.
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            for version in versions.sorted(by: >) { paths.append("\(nvm)/\(version)/bin/node") }
        }
        return paths
    }
}

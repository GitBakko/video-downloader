import XCTest
@testable import VideoDownloaderCore

@MainActor
final class ExistingFileRenamerTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func touch(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    private let xTitle = "PornPlex Rated R - #PetaJensen Oiled Up Big Tits fucked hard."

    func test_candidates_onlyFinishedTemplateFiles() {
        _ = touch("\(xTitle) [2102829100872466432].mp4")
        _ = touch("Clip [abc].mp4.part")
        _ = touch("Clip [abc].f137.mp4")
        _ = touch("Clip [abc].temp.mp4")
        _ = touch("Peta Jensen_already renamed.mp4")
        let found = ExistingFileRenamer.candidates(in: dir)
        XCTAssertEqual(found.map(\.mediaID), ["2102829100872466432"])
        XCTAssertEqual(found.first?.fileTitle, xTitle)
    }

    func test_variousRetry_renamesOnlyWhenAPerformerIsFoundNow() async {
        let found = touch("vario_Satan's All Star Ava Addams is celebrated.mp4")
        _ = touch("vario_Chudai_2.mp4")
        let candidates = ExistingFileRenamer.candidates(in: dir)
        XCTAssertEqual(candidates.map(\.fileTitle), ["Chudai", "Satan's All Star Ava Addams is celebrated"])
        let renames = await ExistingFileRenamer.renameAll(
            candidates, library: ["Ava Addams"], prober: FakeProber(), cookiesBrowser: nil, urlFor: { _ in nil })
        XCTAssertEqual(renames, [.init(from: found, to: dir.appendingPathComponent(
            "Ava Addams_Satan's All Star is celebrated.mp4"))])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("vario_Chudai_2.mp4").path))
    }

    func test_filenameFallback_whenNoHistoryURL() async {
        let file = touch("\(xTitle) [2102829100872466432].mp4")
        let renames = await ExistingFileRenamer.renameAll(
            ExistingFileRenamer.candidates(in: dir), library: ["Peta Jensen"],
            prober: FakeProber(), cookiesBrowser: nil, urlFor: { _ in nil })
        XCTAssertEqual(renames, [.init(from: file, to: dir.appendingPathComponent(
            "Peta Jensen_Oiled Up Big Tits fucked hard.mp4"))])
    }

    func test_probedMetadata_picksEntryMatchingMediaID() async {
        let file = touch("Some post [222].mp4")
        let prober = FakeProber()
        prober.itemsToReturn = [
            DownloadItem(url: "u", title: "Acct - first", mediaID: "111", description: "Lisa Ann first", uploader: "Acct"),
            DownloadItem(url: "u", title: "Acct - second", mediaID: "222", description: "Romi Rain second", uploader: "Acct"),
        ]
        let renames = await ExistingFileRenamer.renameAll(
            ExistingFileRenamer.candidates(in: dir), library: ["Lisa Ann", "Romi Rain"],
            prober: prober, cookiesBrowser: "safari", urlFor: { $0 == file ? "https://x.com/a/status/1" : nil })
        XCTAssertEqual(renames.map(\.to.lastPathComponent), ["Romi Rain_second.mp4"])
        XCTAssertEqual(prober.probedURLs, ["https://x.com/a/status/1"])
        XCTAssertEqual(prober.probedCookieBrowsers, ["safari"])
    }

    func test_probeFailure_fallsBackToFilename() async {
        _ = touch("Lisa Ann by the pool [333].mp4")
        let prober = FakeProber()
        prober.errorToThrow = URLError(.notConnectedToInternet)
        let renames = await ExistingFileRenamer.renameAll(
            ExistingFileRenamer.candidates(in: dir), library: ["Lisa Ann"],
            prober: prober, cookiesBrowser: nil, urlFor: { _ in "https://x.com/deleted" })
        XCTAssertEqual(renames.map(\.to.lastPathComponent), ["Lisa Ann_by the pool.mp4"])
    }

    @MainActor
    func test_moveToPerformerFolders_movesOnlyLibraryPerformers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dest = root.appendingPathComponent("dest"), library = root.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Lisa Ann"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Lisa Ann_a.mp4", "Lisa Ann_b.mp4.part", "vario_c.mp4", "Other_d.mp4"] {
            FileManager.default.createFile(atPath: dest.appendingPathComponent(name).path, contents: Data())
        }
        // Same name already in the folder: gets a suffix, nothing overwritten.
        FileManager.default.createFile(atPath: library.appendingPathComponent("Lisa Ann/Lisa Ann_a.mp4").path, contents: Data())

        let moves = await ExistingFileRenamer.moveToPerformerFolders(in: dest, library: ["Lisa Ann"], libraryRoot: library)

        XCTAssertEqual(moves, [.init(from: dest.appendingPathComponent("Lisa Ann_a.mp4"),
                                     to: library.appendingPathComponent("Lisa Ann/Lisa Ann_a_2.mp4"))])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted(),
                       ["Lisa Ann_b.mp4.part", "Other_d.mp4", "vario_c.mp4"])
    }
}

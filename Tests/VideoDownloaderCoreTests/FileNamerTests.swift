import XCTest
@testable import VideoDownloaderCore

final class FileNamerTests: XCTestCase {
    private let library = ["Angela White", "Lisa Ann", "Romi Rain", "La Sirena 69"]

    // MARK: performer

    func test_libraryNameInTweetText_winsOverAccount() {
        let who = FileNamer.performer(cast: [], text: "Omg LISA ANN is back 🔥🔥 #milf", library: library)
        XCTAssertEqual(who, "Lisa Ann")
    }

    func test_earliestLibraryMatchInText_wins() {
        let who = FileNamer.performer(cast: [], text: "romi rain and angela white", library: library)
        XCTAssertEqual(who, "Romi Rain")
    }

    func test_matchIsWholeWordOnly() {
        // "Lisa Annie" must not match the "Lisa Ann" folder.
        let who = FileNamer.performer(cast: [], text: "lisa annie tonight", library: library)
        XCTAssertNotEqual(who, "Lisa Ann")
    }

    func test_castInLibrary_preferredOverFirstCast() {
        let who = FileNamer.performer(cast: ["Jane Doe", "Angela White"], text: "", library: library)
        XCTAssertEqual(who, "Angela White")
    }

    func test_castNotInLibrary_takesFirstCast() {
        let who = FileNamer.performer(cast: ["Chloé Dupont", "Jane Doe"], text: "", library: library)
        XCTAssertEqual(who, "Chloe Dupont")
    }

    func test_personNameFromText_whenNoLibraryOrCast() {
        let who = FileNamer.performer(cast: [], text: "Yesterday Jessica Smith went to Paris", library: [])
        XCTAssertEqual(who, "Jessica Smith")
    }

    func test_nothingFound_fallsBackToVario() {
        let who = FileNamer.performer(cast: [], text: "🔥🔥🔥 new clip", library: library)
        XCTAssertEqual(who, "vario")
    }

    // MARK: title

    func test_cleanTitle_stripsNoise() {
        let clean = FileNamer.cleanTitle(
            "Aggregator - Hot clip 😍 #tag @someone https://t.co/AbC123 a8F3k2Lq 1834567890123 [1834567890123] 1080p 4K",
            uploader: "Aggregator")
        XCTAssertEqual(clean, "Hot clip 1080p 4K")
    }

    func test_cleanTitle_foldsAccentsKeepsSpaces() {
        XCTAssertEqual(FileNamer.cleanTitle("Chloé à la plage", uploader: nil), "Chloe a la plage")
    }

    func test_cleanTitle_capsLengthOnWordBoundary() {
        let long = String(repeating: "word ", count: 60)
        let clean = FileNamer.cleanTitle(long, uploader: nil)
        XCTAssertLessThanOrEqual(clean.count, FileNamer.maxTitleLength)
        XCTAssertTrue(clean.hasSuffix("word"))
    }

    // MARK: file name

    func test_fileName_prefixesPerformer_andDropsRepeatedName() {
        let item = DownloadItem(url: "u", title: "Poster - Angela White in the kitchen 🔥",
                                uploader: "Poster")
        XCTAssertEqual(FileNamer.fileName(for: item, ext: "mp4", library: library),
                       "Angela White_in the kitchen.mp4")
    }

    func test_fileName_emptyTitle_usesVideo() {
        let item = DownloadItem(url: "u", title: "🔥🔥", uploader: nil)
        XCTAssertEqual(FileNamer.fileName(for: item, ext: "mp4", library: []), "vario_video.mp4")
    }

    func test_uniqueURL_neverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("a.mp4").path, contents: nil)
        XCTAssertEqual(FileNamer.uniqueURL(in: dir, name: "a.mp4").lastPathComponent, "a_2.mp4")
    }

    func test_camelCaseHashtag_matchesLibraryFolder() {
        let item = DownloadItem(url: "u",
                                title: "PornPlex Rated R - #PetaJensen Oiled Up Big Tits fucked hard.",
                                uploader: "PornPlex Rated R")
        XCTAssertEqual(FileNamer.fileName(for: item, ext: "mp4", library: library + ["Peta Jensen"]),
                       "Peta Jensen_Oiled Up Big Tits fucked hard.mp4")
    }

    func test_lowercaseHashtag_matchesSpacelessFolderName() {
        XCTAssertEqual(FileNamer.performer(cast: [], text: "wow #petajensen", library: ["Peta Jensen"]),
                       "Peta Jensen")
    }

    func test_realTitles_fromDownloadsFolder() {
        let lib = ["Adriana Chechik", "Peta Jensen", "Angela White"]
        func name(_ title: String, _ uploader: String, description: String? = nil) -> String {
            FileNamer.fileName(for: DownloadItem(url: "u", title: title, description: description,
                                                 uploader: uploader), ext: "mp4", library: lib)
        }
        XCTAssertEqual(name("Hot Ass - Adriana Chechik's Extreme Gangbang – #AdrianaChechik", "Hot Ass"),
                       "Adriana Chechik_Extreme Gangbang.mp4")
        XCTAssertEqual(name("Vivian - Peta Jensen - Brazzers", "Vivian"), "Peta Jensen_Brazzers.mp4")
        XCTAssertEqual(name("D - Satan's All Star Ava Addams is celebrated today with a compilation, f...", "D"),
                       "vario_Satan's All Star Ava Addams is celebrated today with a compilation.mp4")
        XCTAssertEqual(name("Hot Ass - Group orgy ends with double penetration – #AdrianaChe...", "Hot Ass"),
                       "vario_Group orgy ends with double penetration.mp4")
        XCTAssertEqual(name("Hot Ass - Group orgy ends with double penetration – #AdrianaChe...", "Hot Ass",
                            description: "Group orgy ends with double penetration – #AdrianaChechik #DP"),
                       "Adriana Chechik_Group orgy ends with double penetration.mp4")
    }

    func test_personNames_rejectsLinkSlugs_andCompletesFirstNames() {
        XCTAssertEqual(FileNamer.performer(cast: [], text: "Pizza Party Blowbang  #Brazzers https://t.co/TriZk5Mr6Y",
                                           library: []), "vario")
        let ava = "Satan's All Star Ava Addams is celebrated today with a compilation, from a majority of her "
            + "sinful career, of her being baptized in cum!  Cum celebrate sinners and spend your Sinday "
            + "afternoon lusting for Ava in this goddamn 4+ hour cumshot baptism!"
        XCTAssertEqual(FileNamer.performer(cast: [], text: ava, library: []), "Ava Addams")
    }

    func test_splitHashtags_leavesOtherWordsAlone() {
        XCTAssertEqual(FileNamer.splitHashtags("McKenzie #PetaJensen"), "McKenzie Peta Jensen")
    }

    func test_libraryNames_skipsExclusionsCaseInsensitively() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["Lisa Ann", "Telegram", "Compilations"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(FileNamer.libraryNames(at: dir.path, excluding: ["telegram", " Compilations "]), ["Lisa Ann"])
    }

    func test_performerFolder_onlyLibraryNames_neverVario() {
        let library = ["Ava", "Ava Addams", "vario"]
        XCTAssertEqual(FileNamer.performerFolder(forFileName: "Ava Addams_clip.mp4", library: library), "Ava Addams")
        XCTAssertEqual(FileNamer.performerFolder(forFileName: "Ava_clip.mp4", library: library), "Ava")
        XCTAssertNil(FileNamer.performerFolder(forFileName: "vario_clip.mp4", library: library))
        XCTAssertNil(FileNamer.performerFolder(forFileName: "Mia Malkova_clip.mp4", library: library))
    }

    func test_libraryNames_listsOnlyFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Lisa Ann"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("notes.txt").path, contents: nil)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(FileNamer.libraryNames(at: dir.path), ["Lisa Ann"])
        XCTAssertEqual(FileNamer.libraryNames(at: "/nonexistent/path"), [])
    }
}

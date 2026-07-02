import XCTest
@testable import VideoDownloaderCore

final class SettingsStoreTests: XCTestCase {

    /// A throwaway, isolated UserDefaults suite so tests never touch real prefs.
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_defaults_destinationDefaultFormatAndEmbed() {
        let store = SettingsStore(defaults: ephemeralDefaults())
        XCTAssertTrue(store.destination.path.hasSuffix("Movies/VideoDownloader"))
        XCTAssertEqual(store.defaultFormat, .video(.best))
        XCTAssertFalse(store.embedThumbnailAndMetadata)
    }

    func test_downloadSettings_reflectsStoredProps() {
        let store = SettingsStore(defaults: ephemeralDefaults())
        store.destination = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        store.embedThumbnailAndMetadata = true
        XCTAssertEqual(store.downloadSettings.destination,
                       URL(fileURLWithPath: "/tmp/out", isDirectory: true))
        XCTAssertTrue(store.downloadSettings.embedThumbnailAndMetadata)
    }

    func test_persistsAcrossInstances() {
        let defaults = ephemeralDefaults()
        let first = SettingsStore(defaults: defaults)
        first.defaultFormat = .audio(.best)
        first.embedThumbnailAndMetadata = true

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.defaultFormat, .audio(.best))
        XCTAssertTrue(second.embedThumbnailAndMetadata)
    }
}

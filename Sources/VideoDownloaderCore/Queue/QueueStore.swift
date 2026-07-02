import Foundation
import Observation

@MainActor
@Observable
public final class QueueStore {

    public private(set) var items: [DownloadItem] = []

    private let prober: MediaProbing
    private let engine: Downloading
    private let binaries: BinaryProviding
    private let settings: SettingsStore

    public init(prober: MediaProbing, engine: Downloading,
                binaries: BinaryProviding, settings: SettingsStore) {
        self.prober = prober
        self.engine = engine
        self.binaries = binaries
        self.settings = settings
    }

    // MARK: - Adding

    public func add(url: String) async {
        do {
            var probed = try await prober.probe(url: url)
            // Newly-added items inherit the user's default format (spec §5.2).
            for i in probed.indices { probed[i].selectedFormat = settings.defaultFormat }
            items.append(contentsOf: probed)
        } catch {
            // A probe failure never throws out of add; it surfaces as one
            // failed placeholder so the user sees why nothing was added.
            var failed = DownloadItem(url: url, state: .failed)
            failed.errorMessage = (error as? DownloadError)?.userMessage ?? error.localizedDescription
            items.append(failed)
        }
    }

    // MARK: - Helpers

    private func updateItem(_ id: UUID, _ mutate: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }
}

import SwiftUI
import VideoDownloaderCore

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.setupPhase == .ready {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle).foregroundStyle(.green)
                    Text("Componenti pronti").font(.headline)
                    Text("La finestra principale è collegata nel Task 7.6.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SetupView()
            }
        }
        .task {
            if app.setupPhase != .ready { await app.bootstrap() }
        }
    }
}

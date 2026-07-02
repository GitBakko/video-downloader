import SwiftUI
import VideoDownloaderCore

struct SetupView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Video Downloader").font(.title2).bold()

            switch app.setupPhase {
            case .installing(let message):
                if let progress = app.setupProgress {
                    VStack(spacing: 6) {
                        ProgressView(value: progress) { Text(message) }
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 300)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView(message)
                        .progressViewStyle(.circular)
                }
            case .failed(let message):
                VStack(spacing: 10) {
                    Text("Installazione dei componenti non riuscita")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Riprova") { app.retrySetup() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .ready:
                EmptyView()
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

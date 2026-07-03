import SwiftUI
import AppKit
import VideoDownloaderCore

struct SetupView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Video Downloader").font(.title2).bold()

            switch app.setupPhase {
            case .installing(let message):
                if let progress = app.setupProgress {
                    VStack(spacing: 6) {
                        // P6: fill the (now compact) setup window instead of a
                        // fixed 300pt strip lost in a huge frame.
                        ProgressView(value: progress) { Text(message) }
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)
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

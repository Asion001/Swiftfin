//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import SwiftUI

enum MPVScreenshotStrings {
    static let title = String(enhancedLocalized: "mpv.screenshot.title", defaultValue: "Screenshot")
    static let saved = String(enhancedLocalized: "mpv.screenshot.saved", defaultValue: "Screenshot saved to Files")
    static let failed = String(enhancedLocalized: "mpv.screenshot.failed", defaultValue: "Could not save screenshot")
    static let share = String(enhancedLocalized: "mpv.screenshot.share", defaultValue: "Share screenshot")
}

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    /// Captures the current frame through MPV.
    ///
    /// MPV writes the file itself, so the capture includes everything it is
    /// rendering, subtitles included, at full source resolution rather than
    /// whatever the screen happens to be showing.
    struct Screenshot: View {

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @Toaster
        private var toaster

        @State
        private var capture: ScreenshotCapture?

        private var proxy: (any MediaPlayerScreenshotCapturing)? {
            manager.proxy as? any MediaPlayerScreenshotCapturing
        }

        var body: some View {
            Button {
                takeScreenshot()
            } label: {
                Label(
                    MPVScreenshotStrings.title,
                    systemImage: VideoPlayerActionButton.screenshot.systemImage
                )
            }
            .disabled(proxy == nil)
            .sheet(item: $capture) { capture in
                ScreenshotShareSheet(url: capture.url)
            }
        }

        private func takeScreenshot() {
            guard let proxy else { return }

            Task {
                do {
                    // libmpv's command reply is delivered only after the
                    // screenshot command has finished, so success and sharing
                    // cannot race the file write.
                    let url = try await proxy.takeScreenshot(includeSubtitles: true)
                    toaster.present(MPVScreenshotStrings.saved, systemName: "camera.fill")
                    capture = ScreenshotCapture(url: url)
                } catch {
                    toaster.present(MPVScreenshotStrings.failed, systemName: "exclamationmark.triangle.fill")
                }
            }
        }
    }
}

/// `sheet(item:)` needs identity, and conforming `URL` itself would leak a
/// retroactive stdlib conformance across the app.
private struct ScreenshotCapture: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

private struct ScreenshotShareSheet: View {

    @Environment(\.dismiss)
    private var dismiss

    let url: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                ShareLink(item: url) {
                    Label(MPVScreenshotStrings.share, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle(MPVScreenshotStrings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}
#endif

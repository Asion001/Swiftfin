//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {
    struct Enhancement: View {
        @EnvironmentObject
        private var manager: MediaPlayerManager

        var body: some View {
            if let controller = (manager.proxy as? AVMediaPlayerProxy)?.enhancementController {
                Content(controller: controller)
            }
        }

        private struct Content: View {
            @ObservedObject
            var controller: VideoEnhancementController

            var body: some View {
                Menu {
                    Picker(
                        VideoEnhancementStrings.title,
                        selection: $controller.requestedMode
                    ) {
                        ForEach(VideoEnhancementMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayTitle)
                                .tag(mode)
                        }
                    }

                    Divider()

                    Toggle(
                        VideoEnhancementStrings.comparison,
                        isOn: $controller.isComparisonEnabled
                    )
                    .disabled(controller.bypassReason != nil)

                    Toggle(
                        VideoEnhancementStrings.matchSourceFrameRate,
                        isOn: $controller.matchesSourceFrameRate
                    )

                    Toggle(
                        VideoEnhancementStrings.performance,
                        isOn: $controller.showsPerformanceHUD
                    )

                    if let bypassReason = controller.bypassReason {
                        Divider()
                        Label(bypassReason.displayTitle, systemImage: "info.circle")
                    }
                } label: {
                    Label(
                        VideoEnhancementStrings.title,
                        systemImage: VideoPlayerActionButton.enhancement.systemImage
                    )
                }
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary, .secondary)
            }
        }
    }
}
#endif

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
        private var containerState: VideoPlayerContainerState

        var body: some View {
            Button {
                containerState.presentedModal = .enhancement
            } label: {
                Label(
                    VideoEnhancementStrings.title,
                    systemImage: VideoPlayerActionButton.enhancement.systemImage
                )
            }
        }
    }
}

struct EnhancedEnhancementSettingsView: View {
    @Environment(\.dismiss)
    private var dismiss

    @ObservedObject
    var controller: VideoEnhancementController

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        VideoEnhancementStrings.upscaler,
                        selection: $controller.requestedProvider
                    ) {
                        ForEach(VideoEnhancementProvider.supportedCases, id: \.rawValue) { provider in
                            Text(provider.displayTitle)
                                .tag(provider)
                        }
                    }

                    Picker(
                        VideoEnhancementStrings.title,
                        selection: $controller.requestedMode
                    ) {
                        ForEach(VideoEnhancementMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayTitle)
                                .tag(mode)
                        }
                    }
                } footer: {
                    if controller.requestedProvider == .anime4K {
                        Text(VideoEnhancementStrings.anime4KWarning)
                    }
                }

                Section {
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
                }

                if let bypassReason = controller.bypassReason {
                    Section {
                        Label(bypassReason.displayTitle, systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(VideoEnhancementStrings.title)
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

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

struct MPVUpscalerSettingsView: View {
    @Environment(\.dismiss)
    private var dismiss

    @ObservedObject
    var controller: MPVUpscalerController

    private var isMetalFXUnavailable: Bool {
        controller.requestedProvider == .metalFX && !controller.isMetalFXSupported
    }

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
                    if isMetalFXUnavailable {
                        Text(VideoEnhancementStrings.metalFXUnavailable)
                    } else if controller.requestedProvider == .shader {
                        Text(VideoEnhancementStrings.shaderWarning)
                    }
                }

                Section {
                    Button {} label: {
                        HStack {
                            Text(VideoEnhancementStrings.compare)
                            Spacer()
                            if controller.isComparingBaseline {
                                Text(VideoEnhancementStrings.comparing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    /// A press gesture rather than a toggle: comparing is only
                    /// useful while both pictures are fresh in mind, and holding
                    /// puts the selection back the moment it is released.
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                controller.setComparingBaseline(true)
                            }
                            .onEnded { _ in
                                controller.setComparingBaseline(false)
                            }
                    )
                } footer: {
                    Text(VideoEnhancementStrings.compareFooter)
                }

                Section {
                    LabeledContent(
                        VideoEnhancementStrings.active,
                        value: controller.activeDescription
                    )
                } footer: {
                    if controller.missingShaders.isNotEmpty {
                        Text(
                            VideoEnhancementStrings.missingShaders(
                                controller.missingShaders.joined(separator: ", ")
                            )
                        )
                    }
                }
            }
            .onDisappear {
                /// A hold interrupted by the sheet going away would otherwise
                /// leave the baseline showing with no way back to the selection.
                controller.setComparingBaseline(false)
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

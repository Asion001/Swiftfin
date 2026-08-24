//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct Subtitles: View {

        @ViewContextContains(.isInMenu)
        private var isInMenu

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState

        @State
        private var selectedSubtitleStreamIndex: Int?

        #if os(iOS)
        private var isEnhancedPlayer: Bool {
            (manager.proxy as? AVMediaPlayerProxy)?.presentation == .enhanced
        }
        #endif

        private var systemImage: String {
            if selectedSubtitleStreamIndex == nil || selectedSubtitleStreamIndex == -1 {
                VideoPlayerActionButton.subtitles.secondarySystemImage
            } else {
                VideoPlayerActionButton.subtitles.systemImage
            }
        }

        private var label: some View {
            Label(L10n.subtitles, systemImage: systemImage)
        }

        @ViewBuilder
        private func content(playbackItem: MediaPlayerItem) -> some View {
            Picker(L10n.subtitles, selection: $selectedSubtitleStreamIndex) {
                ForEach(playbackItem.subtitleStreams.prepending(.none), id: \.index) { stream in
                    Text(stream.displayTitle ?? L10n.unknown)
                        .tag(stream.index as Int?)
                }
            }
        }

        private func standardMenu(playbackItem: MediaPlayerItem) -> some View {
            Menu {
                if isInMenu {
                    content(playbackItem: playbackItem)
                } else {
                    Section(L10n.subtitles) {
                        content(playbackItem: playbackItem)
                    }
                }
            } label: {
                label
            }
        }

        #if os(iOS)
        private var enhancedSubtitleButton: some View {
            Button {
                containerState.presentedModal = .subtitles
            } label: {
                label
            }
        }
        #endif

        var body: some View {
            if let playbackItem = manager.playbackItem {
                Group {
                    #if os(iOS)
                    if isEnhancedPlayer {
                        enhancedSubtitleButton
                    } else {
                        standardMenu(playbackItem: playbackItem)
                    }
                    #else
                    standardMenu(playbackItem: playbackItem)
                    #endif
                }
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary, .secondary)
                .videoPlayerActionButtonTransition()
                .assign(playbackItem.$selectedSubtitleStreamIndex, to: $selectedSubtitleStreamIndex)
                .onChange(of: selectedSubtitleStreamIndex) {
                    playbackItem.selectedSubtitleStreamIndex = selectedSubtitleStreamIndex
                }
            }
        }
    }
}

#if os(iOS)
struct EnhancedSubtitleSettingsView: View {
    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject
    private var manager: MediaPlayerManager

    @Default(.VideoPlayer.Subtitle.configuration)
    private var subtitleConfiguration

    @State
    private var selectedSubtitleStreamIndex: Int?

    var body: some View {
        NavigationStack {
            Form {
                if let playbackItem = manager.playbackItem {
                    Section(L10n.subtitles) {
                        Picker(L10n.subtitles, selection: $selectedSubtitleStreamIndex) {
                            ForEach(playbackItem.subtitleStreams.prepending(.none), id: \.index) { stream in
                                Text(stream.displayTitle ?? L10n.unknown)
                                    .tag(stream.index as Int?)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                Section(
                    String(localized: "subtitle.appearance", defaultValue: "Appearance")
                ) {
                    Picker(
                        String(localized: "subtitle.position", defaultValue: "Subtitle position"),
                        selection: $subtitleConfiguration.position
                    ) {
                        ForEach(SubtitlePosition.allCases, id: \.rawValue) { position in
                            Text(position.displayTitle)
                                .tag(position)
                        }
                    }

                    Stepper(
                        value: $subtitleConfiguration.size,
                        in: 1 ... 20,
                        step: 1
                    ) {
                        LabeledContent(L10n.subtitleSize) {
                            Text(subtitleConfiguration.size.description)
                        }
                    }

                    Stepper(
                        value: $subtitleConfiguration.verticalOffset,
                        in: -200 ... 200,
                        step: 5
                    ) {
                        LabeledContent(
                            String(localized: "subtitle.vertical-offset", defaultValue: "Vertical adjustment")
                        ) {
                            Text(verbatim: "\(subtitleConfiguration.verticalOffset) pt")
                        }
                    }

                    Button(
                        String(localized: "subtitle.position.reset", defaultValue: "Reset subtitle position"),
                        systemImage: "arrow.counterclockwise"
                    ) {
                        subtitleConfiguration.position = .automatic
                        subtitleConfiguration.verticalOffset = 0
                    }
                }
            }
            .navigationTitle(L10n.subtitles)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            selectedSubtitleStreamIndex = manager.playbackItem?.selectedSubtitleStreamIndex
        }
        .onChange(of: selectedSubtitleStreamIndex) {
            manager.playbackItem?.selectedSubtitleStreamIndex = selectedSubtitleStreamIndex
        }
    }
}
#endif

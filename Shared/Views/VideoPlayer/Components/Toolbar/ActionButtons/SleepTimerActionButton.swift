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
    struct SleepTimer: View {
        @EnvironmentObject
        private var controller: SleepTimerController

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @ViewContextContains(.isInMenu)
        private var isInMenu

        @State
        private var customDuration: TimeInterval = 30 * 60
        @State
        private var isCustomDurationPresented = false

        /// "End of this episode" reads better than a generic label, and the
        /// distinction matters: only episodes have a next item to suppress.
        private var endOfItemTitle: String {
            switch manager.item.type {
            case .episode:
                SleepTimerStrings.finishEpisode
            case .movie:
                SleepTimerStrings.finishMovie
            default:
                SleepTimerStrings.finishItem
            }
        }

        private var labelTitle: String {
            guard controller.isActive else { return SleepTimerStrings.title }

            return switch controller.mode {
            case .endOfItem:
                SleepTimerStrings.endsIn(controller.formattedRemainingDuration)
            case .duration:
                SleepTimerStrings.remaining(controller.formattedRemainingDuration)
            }
        }

        var body: some View {
            Menu {
                if controller.isActive {
                    Label(labelTitle, systemImage: "timer")

                    if controller.mode == .duration {
                        Button {
                            controller.add(duration: 15 * 60)
                        } label: {
                            Label(SleepTimerStrings.addFifteenMinutes, systemImage: "plus.circle")
                        }
                    }

                    Button(role: .destructive) {
                        controller.cancel()
                    } label: {
                        Label(SleepTimerStrings.cancel, systemImage: "timer.square")
                    }

                    Divider()
                }

                Button {
                    controller.setEndOfItem()
                } label: {
                    Label(
                        endOfItemTitle,
                        systemImage: controller.mode == .endOfItem ? "checkmark" : "play.square"
                    )
                }

                Divider()

                ForEach(SleepTimerController.presetMinutes, id: \.self) { minutes in
                    Button {
                        controller.set(duration: TimeInterval(minutes * 60))
                    } label: {
                        Label(
                            SleepTimerStrings.minutes(minutes),
                            systemImage: controller.mode == .duration
                                && controller.configuredDuration == TimeInterval(minutes * 60)
                                ? "checkmark"
                                : "timer"
                        )
                    }
                }

                Divider()

                Button {
                    isCustomDurationPresented = true
                } label: {
                    Label(SleepTimerStrings.custom, systemImage: "slider.horizontal.3")
                }
            } label: {
                Label(labelTitle, systemImage: VideoPlayerActionButton.sleepTimer.systemImage)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary, .secondary)

                if isInMenu, controller.isActive {
                    Text(controller.formattedRemainingDuration)
                }
            }
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary, .secondary)
            .videoPlayerActionButtonTransition()
            .sheet(isPresented: $isCustomDurationPresented) {
                customDurationSheet
            }
        }

        private var customDurationSheet: some View {
            NavigationStack {
                Form {
                    Section {
                        HourMinutePicker(
                            title: SleepTimerStrings.custom,
                            interval: $customDuration
                        )
                    } footer: {
                        Text(SleepTimerStrings.energyExplanation)
                    }
                }
                .navigationTitle(SleepTimerStrings.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) {
                            isCustomDurationPresented = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(SleepTimerStrings.start) {
                            controller.set(duration: customDuration)
                            isCustomDurationPresented = false
                        }
                        .disabled(customDuration < SleepTimerController.minimumDuration)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
#endif

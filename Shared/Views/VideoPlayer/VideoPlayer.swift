//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI
import Transmission

struct VideoPlayer: View {

    @Environment(\.presentationCoordinator)
    private var presentationCoordinator

    @InjectedObject(\.mediaPlayerManager)
    private var manager: MediaPlayerManager

    @LazyState
    private var proxy: any VideoMediaPlayerProxy

    @Router
    private var router

    // TODO: move audio/subtitle offset to container state?
    @State
    private var audioOffset: Duration = .zero
    @State
    private var isBeingDismissedByTransition = false

    // TODO: move behavior to `PlaybackProgress`?
    @State
    private var scrubbingStartTime: CFTimeInterval? = nil
    @State
    private var subtitleOffset: Duration = .zero

    @StateObject
    private var containerState: VideoPlayerContainerState = .init()
    #if os(iOS)
    @Toaster
    private var toaster

    @StateObject
    private var sleepTimerController: SleepTimerController = .init()
    #endif

    init(proxy: (any VideoMediaPlayerProxy)? = nil) {
        #if targetEnvironment(macCatalyst)
        self._proxy = .init(wrappedValue: proxy ?? AVMediaPlayerProxy())
        #else
        self._proxy = .init(wrappedValue: proxy ?? VLCMediaPlayerProxy())
        #endif
    }

    var body: some View {
        VideoPlayerContainerView(
            containerState: containerState,
            manager: manager
        ) {
            proxy.videoPlayerBody
                .eraseToAnyView()
        } playbackControls: {
            PlaybackControls()
        }
        #if os(iOS)
        .environmentObject(sleepTimerController)
        #endif
        .onAppear {
            manager.proxy = proxy
            #if os(iOS)
            sleepTimerController.attach(to: manager)
            #endif
            manager.start()
        }
        .onDisappear {
            #if os(iOS)
            sleepTimerController.invalidate()
            #endif
        }
        // Keep the fullscreen player's safe area fixed while controls appear.
        // Moving the toolbar with the status bar invalidated menu hit testing,
        // especially during Pencil hover and scrolling.
        .prefersStatusBarHidden(true)
        .onChange(of: audioOffset) {
            if let proxy = proxy as? MediaPlayerOffsetConfigurable {
                proxy.setAudioOffset(audioOffset)
            }
        }
        .onChange(of: containerState.isAspectFilled) {
            /// For a player that can scale continuously, filling is just one
            /// scale, so it is expressed as one rather than applied separately —
            /// otherwise a pinch that lands off a detent would be pulled back by
            /// this the moment it cleared the detent.
            if let zoomProxy = proxy as? any MediaPlayerZoomConfigurable {
                let target = containerState.isAspectFilled ? (zoomProxy.fillZoomScale ?? 1) : 1
                guard abs(containerState.zoomScale - target) > 0.001 else { return }
                containerState.zoomScale = target
            } else {
                UIView.animate(withDuration: 0.2) {
                    proxy.setAspectFill(containerState.isAspectFilled)
                }
            }
        }
        .onChange(of: containerState.zoomScale) {
            guard let zoomProxy = proxy as? any MediaPlayerZoomConfigurable else { return }
            zoomProxy.setZoomScale(containerState.zoomScale)
        }
        .onChange(of: containerState.isScrubbing) {
            if containerState.isScrubbing {
                scrubbingStartTime = CACurrentMediaTime()
            }

            guard let scrubbingStartTime else { return }
            let scrubbingDelta = CACurrentMediaTime() - scrubbingStartTime
            let secondsDelta = abs(manager.seconds - containerState.scrubbedSeconds.value)

            guard secondsDelta >= .seconds(1), scrubbingDelta >= 0.1 else { return }

            let scrubbedSeconds = containerState.scrubbedSeconds.value
            manager.seconds = scrubbedSeconds
            proxy.setSeconds(scrubbedSeconds)
        }
        .onChange(of: subtitleOffset) {
            if let proxy = proxy as? MediaPlayerOffsetConfigurable {
                proxy.setSubtitleOffset(subtitleOffset)
            }
        }
        .preference(
            key: PresentationControllerShouldDismissPreferenceKey.self,
            value: containerState.presentationControllerShouldDismiss
        )
        .onChange(of: presentationCoordinator.isPresented) {
            guard !presentationCoordinator.isPresented else { return }
            isBeingDismissedByTransition = true
            manager.stop()
        }
        .onReceive(manager.$playbackItem) { newItem in
            containerState.isAspectFilled = false
            containerState.zoomScale = 1
            audioOffset = .zero
            subtitleOffset = .zero

            // TODO: move to container view
            containerState.scrubbedSeconds.value = newItem?.baseItem.startSeconds ?? .zero
        }
        .onReceive(manager.secondsBox.$value) { newSeconds in
            // VLC writes this value directly from its playback callback. MPV
            // renders into its own Metal layer with no AVPlayerView in the
            // SwiftUI hierarchy, so keep the shared progress clock synchronized
            // at the player level for every backend.
            guard !containerState.isScrubbing else { return }
            containerState.scrubbedSeconds.value = newSeconds
        }
        .onReceive(manager.$state) { newState in
            if newState == .stopped, !isBeingDismissedByTransition {
                router.dismiss()
            }
        }

        .alert(
            L10n.error,
            isPresented: .constant(manager.error != nil)
        ) {
            Button(L10n.close, role: .cancel) {
                Container.shared.mediaPlayerManager.reset()
                router.dismiss()
            }
        } message: {
            Text(L10n.unableToLoadThisItem)
        }
        #if os(iOS)
        .onChange(of: sleepTimerController.expirationCount) {
            // End-of-item mode lets the item finish rather than pausing
            // mid-playback, so "playback paused" would be wrong there.
            let message = sleepTimerController.lastFinishedMode == .endOfItem
                ? SleepTimerStrings.finished
                : SleepTimerStrings.paused

            toaster.present(message, systemName: "moon.zzz.fill")
        }
        .sheet(item: $containerState.presentedModal) { modal in
            Group {
                switch modal {
                case .subtitles:
                    EnhancedSubtitleSettingsView()
                case .enhancement:
                    if let controller = (manager.proxy as? MPVMediaPlayerProxy)?.upscaler {
                        MPVUpscalerSettingsView(controller: controller)
                    } else {
                        ContentUnavailableView(
                            VideoEnhancementStrings.title,
                            systemImage: "sparkles.tv"
                        )
                    }
                }
            }
            .environmentObject(manager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackground(Color.black.opacity(0.96))
            .preferredColorScheme(.dark)
        }
        #endif
    }
}

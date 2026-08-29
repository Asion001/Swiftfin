//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

extension View {

    func musicPlayerPopup() -> some View {
        modifier(MusicPlayerPopupModifier())
    }
}

private struct MusicPlayerPopupModifier: ViewModifier {

    @Injected(\.mediaPlayerManagerPublisher)
    private var mediaPlayerManagerPublisher

    @State
    private var isPopupOpen = false
    @State
    private var manager: MediaPlayerManager?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let manager, !isPopupOpen {
                    MusicPlayerMiniPlayer(
                        manager: manager,
                        openPlayer: { isPopupOpen = true },
                        stop: {
                            manager.stop()
                            self.manager = nil
                            isPopupOpen = false
                        }
                    )
                    .id(ObjectIdentifier(manager))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $isPopupOpen) {
                if let manager {
                    MusicPlayerPopupView(
                        manager: manager,
                        isPopupOpen: $isPopupOpen
                    )
                    .id(ObjectIdentifier(manager))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: manager != nil)
            .onReceive(mediaPlayerManagerPublisher) { newManager in
                receive(newManager)
            }
    }

    private func receive(_ newManager: MediaPlayerManager?) {
        let previousManager = manager

        if let newManager, newManager.item.type == .audio {
            manager = newManager
        } else {
            manager = nil
            isPopupOpen = false
        }

        if let previousManager, let newManager, previousManager !== newManager {
            previousManager.stop()
        }
    }
}

private struct MusicPlayerMiniPlayer: View {

    @ObservedObject
    private var manager: MediaPlayerManager
    @ObservedObject
    private var seconds: PublishedBox<Duration>

    @State
    private var artwork: UIImage?

    let openPlayer: () -> Void
    let stop: () -> Void

    init(
        manager: MediaPlayerManager,
        openPlayer: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        self.manager = manager
        self.seconds = manager.secondsBox
        self.openPlayer = openPlayer
        self.stop = stop
    }

    private var artist: String? {
        let artists = manager.item.artists?.joined(separator: ", ")
        if let artists, artists.isNotEmpty {
            return artists
        }

        return manager.item.albumArtist
    }

    private var progress: Double {
        guard let runtime = manager.item.runtime?.seconds,
              runtime.isFinite,
              runtime > 0,
              seconds.value.seconds.isFinite
        else {
            return 0
        }

        return clamp(seconds.value.seconds / runtime, min: 0, max: 1)
    }

    private var artworkTaskID: String {
        manager.item.id ?? manager.item.displayTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack(spacing: 12) {
                Button(action: openPlayer) {
                    HStack(spacing: 12) {
                        Group {
                            if let artwork {
                                Image(uiImage: artwork)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "music.note")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.item.displayTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if let artist, artist.isNotEmpty {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    manager.togglePlayPause()
                } label: {
                    Image(systemName: manager.playbackRequestStatus == .playing ? "pause.fill" : "play.fill")
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(manager.playbackRequestStatus == .playing ? L10n.pause : L10n.play)

                if let queue = manager.queue {
                    MusicPlayerPopupNextButton(
                        manager: manager,
                        queue: queue
                    )
                }

                Button(action: stop) {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.close)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .task(id: artworkTaskID) {
            let item = manager.item
            artwork = nil
            let newArtwork = await item.getNowPlayingImage()

            guard !Task.isCancelled, manager.item.id == item.id else { return }
            artwork = newArtwork
        }
    }
}

private struct MusicPlayerPopupView: View {

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @Binding
    private var isPopupOpen: Bool
    @ObservedObject
    private var manager: MediaPlayerManager

    @State
    private var isQueuePresented = false
    @LazyState
    private var proxy: any MediaPlayerProxy

    init(
        manager: MediaPlayerManager,
        isPopupOpen: Binding<Bool>
    ) {
        let proxy: any MediaPlayerProxy = switch Defaults[.MusicPlayer.playerType] {
        case .native:
            AVPlayerMusicMediaPlayerProxy()
        case .mpv:
            MPVMediaPlayerProxy(audioOnly: true)
        }

        self._isPopupOpen = isPopupOpen
        self.manager = manager
        self._proxy = .init(wrappedValue: proxy)
    }

    private var artist: String? {
        let artists = manager.item.artists?.joined(separator: ", ")
        if let artists, artists.isNotEmpty {
            return artists
        }

        guard let albumArtist = manager.item.albumArtist, albumArtist.isNotEmpty else {
            return nil
        }

        return albumArtist
    }

    private var album: String? {
        guard let album = manager.item.album, album.isNotEmpty else { return nil }
        return album
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 0) {
            Button {
                isPopupOpen = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.dismiss)

            Text(album ?? manager.queue?.displayTitle ?? L10n.audio)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button {
                isQueuePresented = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(manager.queue == nil)
            .opacity(manager.queue == nil ? 0 : 1)
            .accessibilityLabel(L10n.nextUp)
        }
        .padding(.horizontal, EdgeInsets.edgePadding / 2)
    }

    private func resolveColor(from image: UIImage, binding: Binding<Color>) {
        Task.detached(priority: .utility) {
            guard let color = image.interestingColor() else { return }

            await MainActor.run {
                binding.wrappedValue = color
            }
        }
    }

    @State
    private var resolvedColor: Color = .clear

    @ViewBuilder
    private var albumArtwork: some View {
        ImageView(
            manager.item.squareImageSources(
                environment: .init()
            )
        )
        .image { (image: UIImage) in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .onAppear {
                    resolveColor(from: image, binding: $resolvedColor)
                }
        }
        .frame(maxWidth: 460)
        .scaleEffect(manager.playbackRequestStatus == .playing ? 1 : 0.92)
        .subtleShadow()
        .animation(
            .bouncy(duration: 0.4, extraBounce: 0.08),
            value: manager.playbackRequestStatus == .playing
        )
    }

    @ViewBuilder
    private var information: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(manager.item.displayTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let artist {
                Text(artist)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let album {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var playbackContent: some View {
        VStack(spacing: EdgeInsets.edgePadding * 1.5) {
            information

            MusicPlayerPlaybackProgress(
                manager: manager,
                proxy: proxy
            )

            MusicPlayerTransportControls(
                manager: manager,
                isBuffering: proxy.isBuffering
            )

            if let queue = manager.queue {
                MusicPlayerQueueButton(
                    queue: queue,
                    action: { isQueuePresented = true }
                )
            }
        }
    }

    @ViewBuilder
    private var playerContent: some View {
        if horizontalSizeClass == .regular {
            ImageContentColumnsLayout(
                idealContentWidth: 520,
                imageAspectRatio: 1,
                imageColumnFraction: 0.5,
                spacing: EdgeInsets.edgePadding * 2
            ) {
                albumArtwork
                playbackContent
            }
            .frame(maxWidth: 960)
        } else {
            VStack(spacing: EdgeInsets.edgePadding) {
                albumArtwork
                    .padding(.horizontal, EdgeInsets.edgePadding)

                playbackContent
            }
        }
    }

    @ViewBuilder
    private var queueSheet: some View {
        if let queue = manager.queue {
            NavigationStack {
                queue.videoPlayerBody
                    .navigationTitle(queue.displayTitle)
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            if #available(iOS 26.0, *) {
                                Button(L10n.close, role: .close) {
                                    isQueuePresented = false
                                }
                            } else {
                                Button(L10n.close) {
                                    isQueuePresented = false
                                }
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    playerContent
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, EdgeInsets.edgePadding)
                        .padding(.top, EdgeInsets.edgePadding / 2)
                        .padding(.bottom, EdgeInsets.edgePadding * 2)
                }
                .trackingFrame(for: .scrollView)
            }
            .background(resolvedColor)
        }
        .onAppear {
            manager.proxy = proxy
            if manager.state == .loadingItem, manager.playbackItem == nil {
                manager.start()
            }
        }
        .sheet(isPresented: $isQueuePresented) {
            queueSheet
        }
    }
}

private struct MusicPlayerPlaybackProgress: View {

    @Default(.VideoPlayer.Overlay.trailingTimestampType)
    private var trailingTimestampType

    @ObservedObject
    var manager: MediaPlayerManager
    @ObservedObject
    private var seconds: PublishedBox<Duration>

    @State
    private var currentTranslation: CGPoint = .zero
    @State
    private var isScrubbing = false
    @State
    private var scrubbedSeconds: Double = 0
    @State
    private var sliderSize: CGSize = .zero

    let proxy: any MediaPlayerProxy

    init(
        manager: MediaPlayerManager,
        proxy: any MediaPlayerProxy
    ) {
        self.manager = manager
        self.seconds = manager.secondsBox
        self.proxy = proxy
    }

    private var canSeek: Bool {
        runtime != nil && manager.state != .loadingItem
    }

    private var displayedSeconds: Duration {
        .seconds(isScrubbing ? scrubbedSeconds : clampedActiveSeconds)
    }

    private var clampedActiveSeconds: Double {
        guard manager.state != .loadingItem else { return 0 }

        let activeSeconds = seconds.value.seconds
        guard activeSeconds.isFinite else { return 0 }
        return clamp(activeSeconds, min: 0, max: sliderTotal)
    }

    private var insetSliderWidth: CGFloat {
        guard sliderSize.width.isFinite else { return 0 }
        return max(0, sliderSize.width - EdgeInsets.edgePadding * 2)
    }

    private var isSlowScrubbing: Bool {
        isScrubbing && currentTranslation.y >= 60
    }

    private var runtime: Duration? {
        guard let runtime = manager.item.runtime,
              runtime > .zero,
              runtime.seconds.isFinite
        else {
            return nil
        }

        return runtime
    }

    private var trailingTimestamp: Duration? {
        guard let runtime else { return nil }

        switch trailingTimestampType {
        case .timeLeft:
            return .zero - (runtime - displayedSeconds)
        case .totalTime:
            return runtime
        }
    }

    private var trailingTimestampAccessibilityValue: Text {
        guard let trailingTimestamp else { return Text(verbatim: .emptyRuntime) }
        return Text(trailingTimestamp, format: .runtime)
    }

    private var sliderTotal: Double {
        runtime?.seconds ?? 1
    }

    private var timeBinding: Binding<Double> {
        Binding(
            get: {
                let value = isScrubbing ? scrubbedSeconds : clampedActiveSeconds
                return clamp(value, min: 0, max: sliderTotal)
            },
            set: { scrubbedSeconds = $0 }
        )
    }

    private var accessibilityProgressBinding: Binding<Double> {
        Binding(
            get: { clampedActiveSeconds / sliderTotal },
            set: { seek(to: $0 * sliderTotal) }
        )
    }

    private var accessibilitySeekLabel: Text {
        guard let runtime else { return Text(L10n.seek) }

        return Text(L10n.seek) +
            Text(verbatim: ", ") +
            Text(displayedSeconds, format: .runtime) +
            Text(verbatim: ", ") +
            Text(L10n.totalTime) +
            Text(verbatim: " ") +
            Text(runtime, format: .runtime)
    }

    private var accessibilityStep: Double {
        let stepSeconds = clamp(sliderTotal * 0.02, min: 1, max: 10)
        return min(1, stepSeconds / sliderTotal)
    }

    @ViewBuilder
    private var capsuleSlider: some View {
        AlternateLayoutView {
            EmptyHitTestView()
                .frame(height: 10)
                .trackingSize($sliderSize)
        } content: {
            // Use scale effect because the slider does not respond well to horizontal frame changes.
            let xScale = insetSliderWidth > 0 ? max(1, sliderSize.width / insetSliderWidth) : 1

            CapsuleSlider(
                value: timeBinding,
                total: sliderTotal,
                translation: $currentTranslation,
                valueDamping: isSlowScrubbing ? 0.1 : 1
            )
            .gesturePadding(30)
            .onEditingChanged(perform: scrubbingDidChange)
            .frame(maxWidth: sliderSize != .zero ? insetSliderWidth : .infinity)
            .scaleEffect(x: isScrubbing ? xScale : 1, y: 1, anchor: .center)
            .frame(height: isScrubbing ? 20 : 10)
            .foregroundStyle(canSeek ? Color.primary : Color.gray)
        }
        .animation(.linear(duration: 0.05), value: displayedSeconds)
        .frame(height: 10)
        .disabled(!canSeek)
        .accessibilityRepresentation {
            Slider(
                value: accessibilityProgressBinding,
                in: 0 ... 1,
                step: accessibilityStep
            ) {
                Text(L10n.seek)
            }
            .accessibilityLabel(accessibilitySeekLabel)
            .disabled(!canSeek)
        }
    }

    @ViewBuilder
    private var timestamps: some View {
        HStack {
            Text(displayedSeconds, format: .runtime)

            Spacer()

            Button(action: toggleTrailingTimestamp) {
                if let trailingTimestamp {
                    Text(trailingTimestamp, format: .runtime)
                } else {
                    Text(verbatim: .emptyRuntime)
                }
            }
            .accessibilityLabel(trailingTimestampType.displayTitle)
            .accessibilityValue(trailingTimestampAccessibilityValue)
        }
        .buttonStyle(.plain)
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(isScrubbing ? .primary : .secondary)
    }

    @ViewBuilder
    private var slowScrubbingIndicator: some View {
        HStack {
            Image(systemName: "backward.fill")
            Text(L10n.slowScrubbing.localizedCapitalized)
            Image(systemName: "forward.fill")
        }
        .font(.caption)
    }

    var body: some View {
        VStack(spacing: 5) {
            capsuleSlider
                .trackingSize($sliderSize)

            timestamps
                .offset(y: isScrubbing ? 5 : 0)
                .frame(maxWidth: isScrubbing ? nil : insetSliderWidth)
        }
        .frame(maxWidth: .infinity)
        .animation(
            .bouncy(duration: 0.4, extraBounce: 0.1),
            value: isScrubbing
        )
        .overlay(alignment: .bottom) {
            if isSlowScrubbing {
                slowScrubbingIndicator
                    .offset(y: EdgeInsets.edgePadding * 2)
                    .transition(.opacity.animation(.linear(duration: 0.1)))
            }
        }
        .onChange(of: isSlowScrubbing) {
            guard isSlowScrubbing else { return }
            UIDevice.impact(.soft)
        }
        .onChange(of: manager.item.id) {
            currentTranslation = .zero
            isScrubbing = false
            scrubbedSeconds = 0
        }
    }

    private func scrubbingDidChange(_ isEditing: Bool) {
        if isEditing {
            guard canSeek else { return }
            scrubbedSeconds = clampedActiveSeconds
            isScrubbing = true
        } else {
            guard isScrubbing else { return }

            isScrubbing = false
            seek(to: scrubbedSeconds)
        }
    }

    private func toggleTrailingTimestamp() {
        switch trailingTimestampType {
        case .timeLeft:
            trailingTimestampType = .totalTime
        case .totalTime:
            trailingTimestampType = .timeLeft
        }
    }

    private func seek(to value: Double) {
        guard canSeek, value.isFinite else { return }

        let newSeconds = Duration.seconds(
            clamp(value, min: 0, max: sliderTotal)
        )
        manager.seconds = newSeconds
        proxy.setSeconds(newSeconds)
    }
}

private struct MusicPlayerQueueButton: View {

    @ObservedObject
    var queue: AnyMediaPlayerQueue

    let action: () -> Void

    private var nextItem: MediaPlayerItemProvider? {
        queue.nextItem
    }

    private var nextArtist: String? {
        guard let artists = nextItem?.item.artists?.joined(separator: ", "), artists.isNotEmpty else {
            return nextItem?.item.albumArtist
        }

        return artists
    }

    @ViewBuilder
    var body: some View {
        if let nextItem {
            Button(action: action) {
                HStack(spacing: 12) {
                    PosterImage(
                        item: nextItem.item,
                        type: .square,
                        size: .extraSmall
                    )
                    .frame(width: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.nextUp)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(nextItem.item.displayTitle)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let nextArtist, nextArtist.isNotEmpty {
                            Text(nextArtist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .background(Color.secondarySystemBackground)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.nextUp)
            .accessibilityValue(nextItem.item.displayTitle)
        }
    }
}

private struct MusicPlayerTransportControls: View {

    @ObservedObject
    var manager: MediaPlayerManager
    @ObservedObject
    var isBuffering: PublishedBox<Bool>

    var body: some View {
        HStack(spacing: 0) {
            if let queue = manager.queue {
                MusicPlayerPreviousButton(
                    manager: manager,
                    queue: queue
                )
                .frame(maxWidth: .infinity)
            } else {
                transportButton(
                    systemName: "backward.end.fill",
                    accessibilityLabel: L10n.previousItem,
                    action: {}
                )
                .disabled(true)
                .frame(maxWidth: .infinity)
            }

            Button {
                manager.togglePlayPause()
            } label: {
                ZStack {
                    if isBuffering.value, manager.playbackRequestStatus == .playing {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: manager.playbackRequestStatus == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 36, weight: .bold))
                            .transition(
                                .opacity
                                    .combined(with: .scale)
                                    .animation(.bouncy(duration: 0.5, extraBounce: 0.1))
                            )
                    }
                }
                .frame(width: 76, height: 72)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(manager.playbackRequestStatus == .playing ? L10n.pause : L10n.play)

            if let queue = manager.queue {
                MusicPlayerNextButton(
                    manager: manager,
                    queue: queue
                )
                .frame(maxWidth: .infinity)
            } else {
                transportButton(
                    systemName: "forward.end.fill",
                    accessibilityLabel: L10n.nextItem,
                    action: {}
                )
                .disabled(true)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
    }

    private func transportButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MusicPlayerPreviousButton: View {

    @ObservedObject
    var manager: MediaPlayerManager
    @ObservedObject
    var queue: AnyMediaPlayerQueue
    @ObservedObject
    private var seconds: PublishedBox<Duration>

    init(manager: MediaPlayerManager, queue: AnyMediaPlayerQueue) {
        self.manager = manager
        self.queue = queue
        self.seconds = manager.secondsBox
    }

    private var canPlayPrevious: Bool {
        manager.state != .loadingItem &&
            (queue.previousItem != nil || seconds.value.seconds > 0)
    }

    var body: some View {
        Button {
            if seconds.value.seconds > 3 || queue.previousItem == nil {
                manager.seconds = .zero
                manager.proxy?.setSeconds(.zero)
            } else if let previousItem = queue.previousItem {
                manager.playNewItem(provider: previousItem)
            }
        } label: {
            Image(systemName: "backward.end.fill")
                .font(.title2)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(!canPlayPrevious)
        .accessibilityLabel(L10n.previousItem)
    }
}

private struct MusicPlayerNextButton: View {

    @ObservedObject
    var manager: MediaPlayerManager
    @ObservedObject
    var queue: AnyMediaPlayerQueue

    var body: some View {
        Button {
            guard let nextItem = queue.nextItem else { return }
            manager.playNewItem(provider: nextItem)
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.title2)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(queue.nextItem == nil || manager.state == .loadingItem)
        .accessibilityLabel(L10n.nextItem)
    }
}

private struct MusicPlayerPopupNextButton: View {

    @ObservedObject
    var manager: MediaPlayerManager
    @ObservedObject
    var queue: AnyMediaPlayerQueue

    var body: some View {
        Button {
            guard let nextItem = queue.nextItem else { return }
            manager.playNewItem(provider: nextItem)
        } label: {
            Image(systemName: "forward.end.fill")
        }
        .disabled(queue.nextItem == nil || manager.state == .loadingItem)
        .accessibilityLabel(L10n.nextItem)
    }
}

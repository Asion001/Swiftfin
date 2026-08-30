//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVKit
import Defaults
import FactoryKit
import JellyfinAPI
import MediaPlayer
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
    @StateObject
    private var sleepTimerController = SleepTimerController()

    /// The proxy is owned here rather than by the popup so that playback starts
    /// with the mini player and survives the popup being collapsed.
    /// `MediaPlayerManager.proxy` is weak, so this is its only strong reference.
    @State
    private var proxy: (any MediaPlayerProxy)?

    func body(content: Content) -> some View {
        content
            .environment(
                \.musicPlayerBottomInset,
                manager == nil || isPopupOpen ? 0 : MusicPlayerMiniPlayer.height
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let manager, !isPopupOpen {
                    MusicPlayerMiniPlayer(
                        manager: manager,
                        openPlayer: { isPopupOpen = true },
                        stop: {
                            manager.stop()
                            self.manager = nil
                            self.proxy = nil
                            isPopupOpen = false
                        }
                    )
                    .id(ObjectIdentifier(manager))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: $isPopupOpen) {
                if let manager, let proxy {
                    MusicPlayerPopupView(
                        manager: manager,
                        proxy: proxy,
                        isPopupOpen: $isPopupOpen
                    )
                    .id(ObjectIdentifier(manager))
                    .environmentObject(manager)
                    .environmentObject(sleepTimerController)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: manager != nil)
            .onReceive(mediaPlayerManagerPublisher) { newManager in
                receive(newManager)
            }
    }

    private func receive(_ newManager: MediaPlayerManager?) {
        let previousManager = manager

        if let newManager, [.audio, .audioBook].contains(newManager.item.type) {
            manager = newManager

            if previousManager !== newManager {
                sleepTimerController.invalidate()
                sleepTimerController.attach(to: newManager)
                attachProxy(to: newManager)
            }
        } else {
            sleepTimerController.invalidate()
            manager = nil
            proxy = nil
            isPopupOpen = false
        }

        if let previousManager, let newManager, previousManager !== newManager {
            previousManager.stop()
        }
    }

    /// Builds the backend for this manager and begins playback, so that a track
    /// selected from a library plays without the popup ever being opened.
    private func attachProxy(to manager: MediaPlayerManager) {
        let newProxy: any MediaPlayerProxy = switch Defaults[.MusicPlayer.playerType] {
        case .native:
            AVPlayerMusicMediaPlayerProxy()
        case .mpv:
            MPVMediaPlayerProxy(audioOnly: true)
        }

        proxy = newProxy
        manager.proxy = newProxy

        if manager.state == .loadingItem, manager.playbackItem == nil {
            manager.start()
        }
    }
}

private struct MusicPlayerMiniPlayer: View {

    static let height: CGFloat = 72

    @ObservedObject
    private var manager: MediaPlayerManager
    @ObservedObject
    private var seconds: PublishedBox<Duration>

    @State
    private var isShowingTechnicalDetails = false

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

    private var technicalSummary: String? {
        guard let playbackItem = manager.playbackItem else { return nil }
        let stream = playbackItem.audioStreams.first { $0.index == playbackItem.selectedAudioStreamIndex }
            ?? playbackItem.audioStreams.first

        let values = [
            stream?.codec?.uppercased() ?? playbackItem.mediaSource.container?.uppercased(),
            stream?.bitRate.map { $0.formatted(.bitRate) }
                ?? playbackItem.mediaSource.bitrate.map { $0.formatted(.bitRate) },
        ]
            .compactMap(\.self)

        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private var subtitle: String? {
        if isShowingTechnicalDetails, let technicalSummary {
            return technicalSummary
        }

        return artist
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack(spacing: 12) {
                Button(action: openPlayer) {
                    HStack(spacing: 12) {
                        MusicPlayerArtwork(
                            item: manager.item,
                            playbackItem: manager.playbackItem
                        )
                        .id(manager.item.id)
                        .frame(width: 46, height: 46)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.item.displayTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if let subtitle, subtitle.isNotEmpty {
                                Text(subtitle)
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
                    isShowingTechnicalDetails.toggle()
                } label: {
                    Image(systemName: isShowingTechnicalDetails ? "info.circle.fill" : "info.circle")
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(technicalSummary == nil)
                .accessibilityLabel(L10n.details)

                if let queue = manager.queue {
                    MusicPlayerPopupPreviousButton(
                        manager: manager,
                        queue: queue
                    )
                }

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
        .frame(height: Self.height)
    }
}

private struct MusicPlayerArtwork: View {

    let item: BaseItemDto
    let playbackItem: MediaPlayerItem?
    var onImage: ((UIImage) -> Void)?

    @State
    private var image: UIImage?

    private var taskID: String {
        playbackItem?.baseItem.id ?? item.id ?? item.displayTitle
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                PosterImage(
                    item: item,
                    type: .square,
                    size: .medium,
                    contentMode: .fill
                )
            }
        }
        .task(id: taskID) {
            image = nil
            let loadedImage: UIImage? = if let thumbnailProvider = playbackItem?.thumbnailProvider {
                await thumbnailProvider()
            } else {
                await item.getNowPlayingImage()
            }
            guard !Task.isCancelled else { return }
            image = loadedImage

            if let loadedImage {
                onImage?(loadedImage)
            }
        }
    }
}

private struct MusicPlayerPopupView: View {

    @EnvironmentObject
    private var sleepTimerController: SleepTimerController

    @Binding
    private var isPopupOpen: Bool
    @ObservedObject
    private var manager: MediaPlayerManager

    @State
    private var isMediaInfoPresented = false
    @State
    private var isQueuePresented = false

    private let proxy: any MediaPlayerProxy

    init(
        manager: MediaPlayerManager,
        proxy: any MediaPlayerProxy,
        isPopupOpen: Binding<Bool>
    ) {
        self._isPopupOpen = isPopupOpen
        self.manager = manager
        self.proxy = proxy
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

    private var selectedAudioStream: MediaStream? {
        guard let playbackItem = manager.playbackItem else { return nil }

        return playbackItem.audioStreams.first { $0.index == playbackItem.selectedAudioStreamIndex }
            ?? playbackItem.audioStreams.first
    }

    private var technicalDetails: [String] {
        guard let playbackItem = manager.playbackItem else { return [] }
        let stream = selectedAudioStream

        return [
            stream?.codec?.uppercased() ?? playbackItem.mediaSource.container?.uppercased(),
            stream?.bitRate.map { $0.formatted(.bitRate) }
                ?? playbackItem.mediaSource.bitrate.map { $0.formatted(.bitRate) },
            stream?.sampleRate.map { "\($0.formatted()) Hz" },
            stream?.bitDepth.map { "\($0.formatted()) bit" },
            stream?.channels.map { "\($0.formatted()) ch" },
        ]
            .compactMap(\.self)
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
                isMediaInfoPresented = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(manager.playbackItem == nil)
            .accessibilityLabel(L10n.details)

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
        MusicPlayerArtwork(
            item: manager.item,
            playbackItem: manager.playbackItem,
            onImage: { resolveColor(from: $0, binding: $resolvedColor) }
        )
        .id(manager.item.id)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
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

            if technicalDetails.isNotEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(technicalDetails, id: \.self) { detail in
                            Text(detail)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
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

            MusicPlayerVolumeControl()

            HStack(spacing: 20) {
                VideoPlayer.PlaybackControls.Toolbar.ActionButtons.SleepTimer()
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(SleepTimerStrings.title)

                Button {
                    isMediaInfoPresented = true
                } label: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(manager.playbackItem == nil)
                .accessibilityLabel(L10n.details)

                if manager.item.canBeDownloaded {
                    MediaDownloadButton(item: manager.item)
                        .id(manager.item.id)
                }

                MusicPlayerRoutePicker()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(L10n.audio)
            }
            .font(.title3)

            if let queue = manager.queue {
                MusicPlayerQueueButton(
                    queue: queue,
                    action: { isQueuePresented = true }
                )
            }
        }
    }

    @ViewBuilder
    private func playerContent(in size: CGSize) -> some View {
        let isWide = size.width >= 760 && size.width > size.height * 1.05

        if isWide {
            HStack(spacing: min(56, EdgeInsets.edgePadding * 2)) {
                albumArtwork
                    .frame(maxWidth: min(480, size.height - 120))

                playbackContent
                    .frame(maxWidth: 520)
            }
            .frame(maxWidth: 1080)
        } else {
            VStack(spacing: EdgeInsets.edgePadding) {
                albumArtwork
                    .frame(
                        maxWidth: min(520, size.width - EdgeInsets.edgePadding * 2),
                        maxHeight: min(520, size.height * 0.48)
                    )

                playbackContent
                    .frame(maxWidth: 560)
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
        ZStack {
            LinearGradient(
                colors: [resolvedColor.opacity(0.78), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                GeometryReader { geometry in
                    ScrollView {
                        playerContent(in: geometry.size)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, EdgeInsets.edgePadding)
                            .padding(.top, EdgeInsets.edgePadding / 2)
                            .padding(.bottom, EdgeInsets.edgePadding * 2)
                            .frame(minHeight: geometry.size.height, alignment: .center)
                    }
                    .trackingFrame(for: .scrollView)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: manager.item.id) {
            resolvedColor = .clear
        }
        .sheet(isPresented: $isQueuePresented) {
            queueSheet
        }
        .sheet(isPresented: $isMediaInfoPresented) {
            if let playbackItem = manager.playbackItem {
                MusicMediaInformationSheet(
                    item: manager.item,
                    source: playbackItem.mediaSource,
                    isPresented: $isMediaInfoPresented
                )
            }
        }
    }
}

private struct MusicPlayerVolumeControl: View {

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            SystemVolumeSlider()
                .frame(height: 32)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.volume)
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct MusicPlayerRoutePicker: UIViewRepresentable {

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.activeTintColor = .white
        view.tintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct MusicMediaInformationSheet: View {

    let item: BaseItemDto
    let source: MediaSourceInfo

    @Binding
    var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.details) {
                    LabeledContent(L10n.title, value: item.displayTitle)

                    if let artists = item.artists?.joined(separator: ", ") ?? item.albumArtist {
                        LabeledContent(L10n.artist, value: artists)
                    }

                    if let album = item.album {
                        LabeledContent(L10n.album, value: album)
                    }

                    ForEach(source.transferProperties, id: \.label) { property in
                        LabeledContent(property.label, value: property.value)
                    }
                }

                if let audioStreams = source.audioStreams, audioStreams.isNotEmpty {
                    Section(L10n.audio) {
                        ForEach(audioStreams, id: \.self) { stream in
                            NavigationLink {
                                MediaStreamInfoView(mediaStream: stream)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stream.displayTitle ?? L10n.audio)

                                    Text(stream.transferProperties.map(\.value).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.media)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26.0, *) {
                        Button(L10n.close, role: .close) {
                            isPresented = false
                        }
                    } else {
                        Button(L10n.close) {
                            isPresented = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

private struct MusicPlayerPopupPreviousButton: View {

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
        }
        .disabled(manager.state == .loadingItem)
        .accessibilityLabel(L10n.previousItem)
    }
}

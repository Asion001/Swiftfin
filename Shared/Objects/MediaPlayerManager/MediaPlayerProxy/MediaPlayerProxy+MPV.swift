//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Combine
import Defaults
import FactoryKit
import Foundation
@preconcurrency import JellyfinAPI
import Metal
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class MPVPlaybackDiagnostics: ObservableObject {
    @Published
    private(set) var logs: [String] = []
    @Published
    private(set) var properties: [String: MPVPropertyValue] = [:]
    @Published
    private(set) var tracks: [MPVTrack] = []
    @Published
    private(set) var latestScreenshotURL: URL?

    func record(property name: String, value: MPVPropertyValue) {
        guard properties[name] != value else { return }
        properties[name] = value
    }

    func record(log: String) {
        logs.append(log.trimmingCharacters(in: .newlines))
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    func record(tracks: [MPVTrack]) {
        self.tracks = tracks
    }

    func record(screenshot url: URL) {
        latestScreenshotURL = url
    }

    func clearLogs() {
        logs.removeAll(keepingCapacity: true)
    }
}

@MainActor
final class MPVMediaPlayerProxy: VideoMediaPlayerProxy,
    MediaPlayerOffsetConfigurable,
    MediaPlayerSubtitleConfigurable,
    MediaPlayerScreenshotCapturing
{
    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let diagnostics = MPVPlaybackDiagnostics()
    let upscaler: MPVUpscalerController

    /// The layer MPV renders into, owned here rather than by the view.
    ///
    /// MPV is handed this layer once, as `wid`, and draws into that one for the
    /// life of the context, so the layer has to outlive any particular view.
    /// SwiftUI rebuilds the surface — opening a supplement is enough — and a
    /// layer created per view meant every rebuild either stranded MPV on a layer
    /// nothing was showing or forced the context to restart, which drops the
    /// picture and tears the audio output down with it. Re-parenting one layer
    /// costs nothing and MPV never notices.
    let renderLayer: MPVMetalLayer = {
        let layer = MPVMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.isOpaque = true
        layer.backgroundColor = UIColor.black.cgColor
        layer.contentsScale = UIScreen.main.nativeScale
        layer.pixelFormat = .bgra8Unorm
        /// Raised once MPV reports an HDR transfer function.
        layer.wantsExtendedDynamicRangeContent = false
        return layer
    }()

    private let client: MPVClientCore
    private let configurationStore: MPVConfigurationStore
    private var decoderDroppedFrames = 0
    private var itemObserver: AnyCancellable?
    private var managerStateObserver: AnyCancellable?
    private var outputDroppedFrames = 0
    private var playbackItem: MediaPlayerItem?
    private var rateObserver: AnyCancellable?
    private var sourceHeight = 0
    private var sourceWidth = 0
    private var transferFunction: String?
    private var signalPeak: Double = 1

    weak var manager: MediaPlayerManager? {
        didSet {
            for var observer in observers {
                observer.manager = manager
            }

            itemObserver = manager?.$playbackItem
                .sink { [weak self] item in
                    guard let item else { return }
                    self?.load(item: item)
                }
            managerStateObserver = manager?.$state
                .sink { [weak self] state in
                    if state == .stopped {
                        self?.client.shutdown()
                    }
                }
            rateObserver = manager?.$rate
                .sink { [weak self] rate in
                    self?.client.setRate(Double(rate))
                }
        }
    }

    var observers: [any MediaPlayerObserver] = [
        NowPlayableObserver(),
    ]

    init(
        audioOnly: Bool = false,
        configurationStore: MPVConfigurationStore = .shared,
        client: MPVClientCore? = nil
    ) {
        self.configurationStore = configurationStore
        self.upscaler = MPVUpscalerController(configurationStore: configurationStore)
        self.client = client ?? MPVClientCore(configurationStore: configurationStore)
        self.client.setEventHandler { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handle(event: event)
            }
        }

        if audioOnly {
            self.client.prepareForAudioPlayback()
        }
    }

    func play() {
        client.play()
    }

    func pause() {
        client.pause()
    }

    func stop() {
        client.stopPlayback()
    }

    func jumpForward(_ seconds: Duration) {
        client.seek(by: seconds.seconds)
    }

    func jumpBackward(_ seconds: Duration) {
        client.seek(by: -seconds.seconds)
    }

    func setRate(_ rate: Float) {
        client.setRate(Double(rate))
    }

    func setSeconds(_ seconds: Duration) {
        client.seek(to: seconds.seconds)
    }

    func setAudioStream(_ stream: MediaStream) {
        client.selectTrack(kind: .audio, ffIndex: stream.index)
    }

    func setSubtitleStream(_ stream: MediaStream) {
        client.selectTrack(kind: .subtitle, ffIndex: stream.index)
    }

    func setAspectFill(_ aspectFill: Bool) {
        client.setAspectFill(aspectFill)
    }

    func setAudioOffset(_ seconds: Duration) {
        client.setAudioDelay(seconds.seconds)
    }

    func setSubtitleOffset(_ seconds: Duration) {
        client.setSubtitleDelay(seconds.seconds)
    }

    func setSubtitleConfiguration(_ configuration: SubtitleConfiguration) {
        let basePosition: Double
        switch configuration.position {
        case .automatic, .lowerBlackBar, .screenBottom:
            basePosition = 100
            client.setOption(name: "sub-use-margins", value: "yes")
            client.setOption(name: "sub-ass-force-margins", value: "yes")
        case .insideVideo:
            basePosition = 94
            client.setOption(name: "sub-use-margins", value: "no")
            client.setOption(name: "sub-ass-force-margins", value: "no")
        }

        let position = min(150, max(0, basePosition + Double(configuration.verticalOffset) / 10))
        client.setOption(name: "sub-font", value: configuration.fontName)
        client.setOption(
            name: "sub-font-size",
            value: String(Int(EnhancedSubtitleGeometry.fontPointSize(for: configuration.size)))
        )
        client.setOption(name: "sub-color", value: Self.mpvColor(for: configuration.color))
        client.setOption(name: "sub-pos", value: String(position))

        /// MPV always applies the `sub-*` options to the formats it converts to
        /// ASS itself — SubRip, WebVTT and the rest — so the font, size and
        /// colour chosen here still reach them. `force` additionally replaces the
        /// fonts, colours, borders and positioning that an ASS or SSA script
        /// authored for itself, which is exactly what those subtitles carry
        /// signs, karaoke and typesetting in. `scale`, MPV's own default, keeps
        /// that intact while still honouring the position set above.
        client.setOption(name: "sub-ass-override", value: "scale")
    }

    /// A colour in the form MPV parses.
    ///
    /// `Color.hexString` returns bare `RRGGBB`, which MPV rejects outright —
    /// `Option sub-color: invalid color: 'FFFFFF'` — so the subtitle colour never
    /// reached the player. MPV wants a leading `#`, and puts alpha first.
    static func mpvColor(for color: Color) -> String {
        let components = color.rgbaComponents
        let channel: (Double) -> Int = { Int((min(1, max(0, $0)) * 255).rounded()) }

        return String(
            format: "#%02X%02X%02X%02X",
            channel(components.alpha),
            channel(components.red),
            channel(components.green),
            channel(components.blue)
        )
    }

    func takeScreenshot(includeSubtitles: Bool = true) async throws -> URL {
        try configurationStore.prepare()
        let url = configurationStore.screenshotURL()
        try await client.takeScreenshot(to: url, includeSubtitles: includeSubtitles)
        diagnostics.record(screenshot: url)
        return url
    }

    /// Whether MPV is presenting an HDR transfer function.
    ///
    /// `sig-peak` is reported relative to SDR reference white, so anything above
    /// 1 is brighter than SDR. The transfer function is the more reliable
    /// signal; the peak covers sources that do not report one.
    var isHighDynamicRange: Bool {
        if let transferFunction, ["pq", "hlg"].contains(transferFunction) {
            return true
        }

        return signalPeak > 1
    }

    func attach() {
        client.attach(to: renderLayer)
        upscaler.attach(to: client)
        updateDynamicRange()
    }

    /// Ends the MPV context once the surface is gone for good.
    ///
    /// Deferred, because a rebuild releases the old view after the replacement
    /// has already adopted the layer: if something has taken it by the time this
    /// runs, the player is still on screen and the context is still wanted.
    /// Playback used to be stopped only by the manager reaching `.stopped`, and
    /// when that did not reach the client the context stayed alive behind a
    /// dismissed player — audible, invisible, and still holding a GPU context
    /// that the next one had to start alongside.
    nonisolated func playerSurfaceDidDeinit() {
        Task { @MainActor [weak self] in
            guard let self, renderLayer.superlayer == nil else { return }
            client.shutdown()
        }
    }

    /// See `MPVClientCore.synchronizeWithLayerSize()`: MPV cannot notice that the
    /// layer it draws into was resized, so the view hosting it has to say so.
    func layerDidLayOut() {
        client.synchronizeWithLayerSize()
    }

    @ViewBuilder
    var videoPlayerBody: some View {
        MPVPlayerSurface(proxy: self)
    }
}

private extension MPVMediaPlayerProxy {

    func load(item: MediaPlayerItem, from seconds: Duration? = nil) {
        playbackItem = item
        isBuffering.value = true
        diagnostics.record(log: "Loading \(item.url.lastPathComponent)")

        // A stopped MPV context is intentionally destroyed. Re-attaching here
        // makes a proxy that receives another item usable instead of leaving a
        // queued URL with no context and presenting a black surface. This goes
        // through `attach()` so the new context is configured exactly like a
        // first attach, upscaler options included.
        attach()

        let audioIndex = item.indexMap.playerIndex(for: item.selectedAudioStreamIndex)
        let subtitleIndex = item.indexMap.playerIndex(for: item.selectedSubtitleStreamIndex)
        client.selectTrack(kind: .audio, ffIndex: audioIndex)
        client.selectTrack(kind: .subtitle, ffIndex: subtitleIndex)
        client.load(
            url: item.url,
            startSeconds: (seconds ?? startSeconds(for: item)).seconds
        )
    }

    /// A live stream has no meaningful resume position, and asking for one only
    /// delays the first frame.
    func startSeconds(for item: MediaPlayerItem) -> Duration {
        guard !item.baseItem.isLiveStream else { return .zero }

        return max(
            .zero,
            (item.baseItem.startSeconds ?? .zero)
                - Duration.seconds(Defaults[.VideoPlayer.resumeOffset])
        )
    }

    func handle(event: MPVClientCore.Event) {
        switch event {
        case let .endFile(error):
            isBuffering.value = false
            if let error {
                manager?.error(ErrorMessage("MPV error: \(error)"))
            } else if playbackItem?.baseItem.isLiveStream == false {
                manager?.ended()
            }
        case .fileLoaded:
            handleFileLoaded()
        case let .log(message):
            diagnostics.record(log: message)
            manager?.logger.trace("MPV: \(message)")
        case let .property(name, value):
            // `time-pos` changes continuously and is already published by the
            // media manager. Keeping a second copy in an @Published dictionary
            // rebuilt the statistics view for every playback tick.
            if name != "time-pos" {
                diagnostics.record(property: name, value: value)
            }
            handleProperty(name: name, value: value)
        case let .tracks(tracks):
            diagnostics.record(tracks: tracks)
            resolveSubtitleTracksIfPossible(tracks)
        }
    }

    func handleFileLoaded() {
        guard let playbackItem else { return }
        isBuffering.value = false

        for subtitle in playbackItem.subtitleStreams.sidecarSubtitles {
            guard let url = externalSubtitleURL(for: subtitle) else { continue }
            client.addSubtitle(url: url, title: subtitle.displayTitle)
        }

        client.setRate(Double(manager?.rate ?? 1))
        setSubtitleConfiguration(Defaults[.VideoPlayer.Subtitle.configuration])
        client.play()
    }

    func handleProperty(name: String, value: MPVPropertyValue) {
        switch (name, value) {
        case let ("time-pos", .double(seconds)):
            manager?.seconds = .seconds(seconds)
        case let ("pause", .bool(isPaused)):
            manager?.setPlaybackRequestStatus(status: isPaused ? .paused : .playing)
        case let ("paused-for-cache", .bool(isPausedForCache)):
            isBuffering.value = isPausedForCache
        case let ("width", .integer(width)):
            sourceWidth = Int(width)
            updateVideoSize()
        case let ("height", .integer(height)):
            sourceHeight = Int(height)
            updateVideoSize()
        case let ("video-params/gamma", .string(gamma)):
            transferFunction = gamma
            updateDynamicRange()
        case ("video-params/gamma", .unavailable):
            transferFunction = nil
            updateDynamicRange()
        case let ("video-params/sig-peak", .double(peak)):
            signalPeak = peak
            updateDynamicRange()
        case let ("decoder-frame-drop-count", .integer(count)):
            decoderDroppedFrames = Int(count)
            updateDroppedFrames()
        case let ("frame-drop-count", .integer(count)):
            outputDroppedFrames = Int(count)
            updateDroppedFrames()
        default:
            break
        }
    }

    func updateVideoSize() {
        videoSize.value = CGSize(width: sourceWidth, height: sourceHeight)
    }

    /// Requesting EDR headroom unconditionally makes SDR content wash out on
    /// some displays, so it follows the actual video parameters.
    func updateDynamicRange() {
        renderLayer.wantsExtendedDynamicRangeContent = isHighDynamicRange
    }

    func updateDroppedFrames() {
        droppedFrames.value = decoderDroppedFrames + outputDroppedFrames
    }

    func resolveSubtitleTracksIfPossible(_ tracks: [MPVTrack]) {
        guard let playbackItem else { return }
        let sidecarCount = playbackItem.subtitleStreams.sidecarSubtitles.count
        let subtitleTracks = tracks.filter { $0.kind == .subtitle }
        guard sidecarCount == 0 || subtitleTracks.count(where: { $0.isExternal }) >= sidecarCount else {
            return
        }

        playbackItem.getSubtitleIndexes(
            subtitleTracks: subtitleTracks.map { track in
                (index: track.ffIndex ?? Int(track.id), title: track.title)
            }
        )
    }

    func externalSubtitleURL(for stream: MediaStream) -> URL? {
        guard let deliveryURL = stream.deliveryURL,
              let client = Container.shared.currentUserSession()?.client
        else { return nil }

        let path = deliveryURL.removingFirst(
            if: client.configuration.url.absoluteString.last == "/"
        )
        return client.url(path: path)
    }
}

private struct MPVPlayerSurface: UIViewRepresentable {
    @ObservedObject
    var proxy: MPVMediaPlayerProxy

    func makeUIView(context: Context) -> MPVPlayerUIView {
        MPVPlayerUIView(proxy: proxy)
    }

    func updateUIView(_ uiView: MPVPlayerUIView, context: Context) {
        uiView.updateDrawableSize()
    }
}

private final class MPVPlayerUIView: UIView {

    private let proxy: MPVMediaPlayerProxy

    init(proxy: MPVMediaPlayerProxy) {
        self.proxy = proxy
        super.init(frame: .zero)

        backgroundColor = .black
        isOpaque = true

        /// Adding it to this layer removes it from whichever view held it
        /// before, so a rebuilt surface adopts the running one.
        layer.addSublayer(proxy.renderLayer)
        proxy.attach()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        proxy.playerSurfaceDidDeinit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    func updateDrawableSize() {
        let metalLayer = proxy.renderLayer
        guard metalLayer.superlayer === layer else { return }

        /// Laying the layer out is not something to animate: an implicit
        /// animation on its frame stretches the picture for the length of
        /// whatever animation happens to be running.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        metalLayer.frame = bounds
        metalLayer.contentsScale = window?.screen.nativeScale ?? UIScreen.main.nativeScale

        let drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )

        /// `layoutSubviews` runs on every frame of the animation that opens a
        /// supplement, and each accepted size costs MPV a swapchain.
        if drawableSize.width > 1,
           drawableSize.height > 1,
           drawableSize != metalLayer.drawableSize
        {
            metalLayer.drawableSize = drawableSize
        }

        /// Told on every pass rather than only when the size changed here: MPV
        /// can fall out of step with a layer this view never resized, and the
        /// check on the other side is two property reads.
        proxy.layerDidLayOut()
    }
}

final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            // MoltenVK may transiently request 1×1 while completing an old
            // presentation. Accepting it causes a visible flash and can leave
            // the layer stuck at that size after rotation or zoom-to-fill.
            guard newValue.width > 1, newValue.height > 1 else { return }
            super.drawableSize = newValue
        }
    }

    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}
#endif

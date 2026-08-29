//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Foundation
@preconcurrency import Libmpv
import QuartzCore

enum MPVClientError: LocalizedError {
    case api(operation: String, code: Int32)
    case initialization
    case terminated

    var errorDescription: String? {
        switch self {
        case let .api(operation, code):
            let message = String(cString: mpv_error_string(code))
            return "MPV \(operation) failed: \(message)"
        case .initialization:
            return "MPV could not create a playback context"
        case .terminated:
            return "MPV playback ended before the command completed"
        }
    }
}

enum MPVPropertyValue: @unchecked Sendable, Equatable {
    case bool(Bool)
    case double(Double)
    case integer(Int64)
    case string(String)
    case unavailable
}

struct MPVTrack: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable {
        case audio
        case subtitle = "sub"
        case video
        case unknown
    }

    let id: Int64
    let ffIndex: Int?
    let kind: Kind
    let title: String
    let language: String?
    let codec: String?
    let isExternal: Bool
    let isSelected: Bool
}

/// The part of the MPV client that configuration code needs.
///
/// Exists so the upscaler can be driven without a live libmpv context: tests
/// substitute a spy and assert on the exact options sent, which is what the
/// concrete class makes impossible.
protocol MPVOptionConfigurable: AnyObject, Sendable {

    func applyUpscaler(_ application: MPVUpscaler.Application)
    func probeOption(named name: String, completion: @escaping @Sendable (Bool) -> Void)
}

/// A serialized libmpv owner. Normal client calls and event draining share one
/// queue; rendering is performed internally by MPV's MoltenVK video output.
/// This avoids the callback/client-thread deadlocks documented by libmpv.
final class MPVClientCore: MPVOptionConfigurable, @unchecked Sendable {

    enum Event: @unchecked Sendable {
        case endFile(error: String?)
        case fileLoaded
        case log(String)
        case property(name: String, value: MPVPropertyValue)
        case tracks([MPVTrack])
    }

    typealias EventHandler = @Sendable (Event) -> Void

    private struct DesiredTrack {
        let kind: MPVTrack.Kind
        let ffIndex: Int?
    }

    private let configurationStore: MPVConfigurationStore
    private let queue = DispatchQueue(
        label: "org.jellyfin.swiftfin.mpv-client",
        qos: .userInitiated
    )

    private var desiredTracks: [MPVTrack.Kind: DesiredTrack] = [:]
    private var eventHandler: EventHandler?
    private var isLayerSizeCheckScheduled = false
    private var lastLayerSizeCheck: UInt64 = 0
    private var lastReportedLayerSizeDrift: String?
    private var hasReportedLayerSizeCheck = false
    private var handle: OpaquePointer?
    private var isInitialized = false
    private var layer: CAMetalLayer?
    private var nextCommandID: UInt64 = 1
    private var pendingStartSeconds: Double = 0
    private var pendingURL: URL?
    private var pendingCommands: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var tracks: [MPVTrack] = []
    private var upscalerApplication: MPVUpscaler.Application?
    private var isUpscalerApplicationScheduled = false
    private var lastUpscalerApplication: UInt64 = 0

    init(configurationStore: MPVConfigurationStore = .shared) {
        self.configurationStore = configurationStore
    }

    deinit {
        // Nothing can await these once `self` is gone, so they are failed here
        // rather than left suspended forever.
        for continuation in pendingCommands.values {
            continuation.resume(throwing: MPVClientError.terminated)
        }
        pendingCommands.removeAll()

        guard let handle else { return }

        // Normal playback teardown calls `shutdown()` and reaches deinit only
        // after the handle is gone. Keep this fallback non-blocking while
        // clearing the unretained callback before `self` can disappear.
        mpv_set_wakeup_callback(handle, nil, nil)
        let detachedHandle = MPVDetachedHandle(handle)
        queue.async {
            detachedHandle.destroy()
        }
    }

    func setEventHandler(_ handler: EventHandler?) {
        queue.async { [weak self] in
            self?.eventHandler = handler
        }
    }

    func attach(to layer: CAMetalLayer) {
        queue.async { [weak self] in
            self?.initializeIfNeeded(layer: layer)
        }
    }

    /// Initializes MPV without a drawable surface for music playback.
    func prepareForAudioPlayback() {
        queue.async { [weak self] in
            self?.initializeIfNeeded(layer: nil)
        }
    }

    /// Opens a file, optionally beginning at `startSeconds`.
    ///
    /// The position is handed to MPV as the `start` option rather than seeked to
    /// once the file is loaded: `loadfile` begins playing immediately, so a seek
    /// issued from the `fileLoaded` event always shows a second or so of the
    /// opening frames before the picture jumps to where the user left off.
    func load(url: URL, startSeconds: Double = 0) {
        queue.async { [weak self] in
            guard let self else { return }
            pendingURL = url
            pendingStartSeconds = startSeconds
            loadPendingURLIfPossible()
        }
    }

    func play() {
        setFlag(name: "pause", value: false)
    }

    func pause() {
        setFlag(name: "pause", value: true)
    }

    func stopPlayback() {
        command(["stop"])
    }

    func seek(to seconds: Double) {
        command(["seek", String(max(0, seconds)), "absolute+exact"])
    }

    func seek(by seconds: Double) {
        command(["seek", String(seconds), "relative+exact"])
    }

    func setRate(_ rate: Double) {
        setDouble(name: "speed", value: rate)
    }

    /// `video-zoom` is a power of two relative to the fitted size.
    func setZoom(_ zoom: Double) {
        setDouble(name: "video-zoom", value: zoom)
    }

    func setAudioDelay(_ seconds: Double) {
        setDouble(name: "audio-delay", value: seconds)
    }

    func setSubtitleDelay(_ seconds: Double) {
        setDouble(name: "sub-delay", value: seconds)
    }

    func setOption(name: String, value: String) {
        queue.async { [weak self] in
            guard let self, let handle else { return }
            reportIfFailed(
                mpv_set_property_string(handle, name, value),
                operation: "set \(name)"
            )
        }
    }

    /// Applies a complete upscaler selection in one turn of the client queue.
    ///
    /// MetalFX is disabled first so no frame can enter the old MetalFX pass
    /// while its shader/scaler inputs are being replaced. This also prevents a
    /// burst of picker changes from interleaving partial configurations.
    /// Installs an upscaler pipeline, rate limiting changes that arrive together.
    ///
    /// Each application leaves the current pipeline and builds another, which
    /// for MetalFX means tearing down and reallocating GPU textures. Dragging
    /// through a picker emits one of these per step, and rebuilding in full for
    /// every value passed through is both wasteful and, apparently, unstable.
    ///
    /// The first change is applied at once and only the ones crowding behind it
    /// are collapsed. Delaying the first instead — which is what this did — meant
    /// a state held for less than the interval was overwritten before it was
    /// ever applied, so flipping quickly between two settings showed neither of
    /// them. That is precisely what comparing two settings does.
    func applyUpscaler(_ application: MPVUpscaler.Application) {
        queue.async { [weak self] in
            guard let self else { return }
            upscalerApplication = application

            guard !isUpscalerApplicationScheduled else { return }

            let elapsed = DispatchTime.now().uptimeNanoseconds &- lastUpscalerApplication

            guard elapsed < Self.upscalerApplicationInterval else {
                applyPendingUpscaler()
                return
            }

            isUpscalerApplicationScheduled = true
            queue.asyncAfter(
                deadline: .now() + .nanoseconds(Int(Self.upscalerApplicationInterval - elapsed))
            ) { [weak self] in
                guard let self else { return }
                isUpscalerApplicationScheduled = false
                applyPendingUpscaler()
            }
        }
    }

    /// Asks MPV whether it knows an option by name.
    ///
    /// Swiftfin's patched libmpv adds options that stock builds do not have, so
    /// features are probed rather than assumed from a version number.
    func probeOption(named name: String, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self, let handle else {
                completion(false)
                return
            }

            completion(getString(handle: handle, name: "option-info/\(name)/name") != nil)
        }
    }

    func selectTrack(kind: MPVTrack.Kind, ffIndex: Int?) {
        queue.async { [weak self] in
            guard let self else { return }
            desiredTracks[kind] = DesiredTrack(kind: kind, ffIndex: ffIndex)
            applyDesiredTrack(kind: kind)
        }
    }

    func addSubtitle(url: URL, title: String?) {
        var arguments = ["sub-add", url.absoluteString, "auto"]
        if let title, title.isNotEmpty {
            arguments.append(title)
        }
        command(arguments)
    }

    func takeScreenshot(to url: URL, includeSubtitles: Bool = true) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: MPVClientError.terminated)
                    return
                }

                performCommand(
                    [
                        "screenshot-to",
                        url.path,
                        includeSubtitles ? "subtitles" : "video",
                    ],
                    continuation: continuation
                )
            }
        }
    }

    /// Repairs MPV's idea of the surface it draws into when it has drifted from
    /// the layer's actual size.
    ///
    /// The `moltenvk` GPU context reads `CAMetalLayer.drawableSize` only from its
    /// `reconfig`, and its `control` answers `VO_NOTIMPL` to everything, so in
    /// this build nothing turns a layer resize into a `VO_EVENT_RESIZE` — the
    /// `android-surface-size` property that drives `VOCTRL_EXTERNAL_RESIZE`
    /// elsewhere is compiled out on Apple platforms. Left alone, `vo->dwidth` and
    /// `vo->dheight` keep the size the file was opened at while libplacebo
    /// rebuilds the swapchain at the new one, and MPV goes on drawing the picture
    /// into a rectangle that no longer lands on the layer — mostly, or entirely,
    /// off it.
    ///
    /// Safe to call on every layout pass. The size is compared first and nothing
    /// happens while the two agree, and comparing is rate limited because reading
    /// a property blocks on MPV's core thread.
    func synchronizeWithLayerSize() {
        queue.async { [weak self] in
            self?.scheduleLayerSizeCheck()
        }
    }

    func shutdown() {
        // Retain the client until queued teardown completes. This makes the
        // non-blocking deinit path a fallback rather than the normal path.
        queue.async {
            self.destroyHandle()
        }
    }
}

private extension MPVClientCore {

    static let observedProperties: [(name: String, format: mpv_format)] = [
        ("time-pos", MPV_FORMAT_DOUBLE),
        ("duration", MPV_FORMAT_DOUBLE),
        ("pause", MPV_FORMAT_FLAG),
        ("paused-for-cache", MPV_FORMAT_FLAG),
        ("width", MPV_FORMAT_INT64),
        ("height", MPV_FORMAT_INT64),
        /// The aspect-corrected size, which is what the picture actually
        /// occupies and so what a fill scale has to be computed against.
        ("dwidth", MPV_FORMAT_INT64),
        ("dheight", MPV_FORMAT_INT64),
        ("container-fps", MPV_FORMAT_DOUBLE),
        ("estimated-vf-fps", MPV_FORMAT_DOUBLE),
        ("display-fps", MPV_FORMAT_DOUBLE),
        ("decoder-frame-drop-count", MPV_FORMAT_INT64),
        ("frame-drop-count", MPV_FORMAT_INT64),
        ("demuxer-cache-duration", MPV_FORMAT_DOUBLE),
        ("cache-buffering-state", MPV_FORMAT_INT64),
        ("video-codec", MPV_FORMAT_STRING),
        ("video-format", MPV_FORMAT_STRING),
        ("audio-codec-name", MPV_FORMAT_STRING),
        ("hwdec-current", MPV_FORMAT_STRING),
        ("video-params/primaries", MPV_FORMAT_STRING),
        ("video-params/gamma", MPV_FORMAT_STRING),
        ("video-params/sig-peak", MPV_FORMAT_DOUBLE),
        ("track-list/count", MPV_FORMAT_INT64),
    ]

    func initializeIfNeeded(layer: CAMetalLayer?) {
        /// MPV is handed the layer once, as `wid`, and renders into that one for
        /// the life of the context. A context that outlives the view it was
        /// built for therefore keeps drawing into a layer nobody is showing —
        /// the picture is black while the audio plays on. Rebuild against the
        /// layer that is actually on screen instead of quietly keeping the old
        /// one.
        if let layer {
            if isInitialized, self.layer !== layer {
                emit(.log("MPV was given a new layer; restarting the context"))
                destroyHandle()
            }

            self.layer = layer
        }
        guard !isInitialized else { return }

        do {
            try configurationStore.prepare()
        } catch {
            emit(.log("Unable to prepare MPV configuration: \(error.localizedDescription)"))
        }

        guard let newHandle = mpv_create() else {
            emit(.endFile(error: MPVClientError.initialization.localizedDescription))
            return
        }
        handle = newHandle

        do {
            try setPreInitializationOptions(handle: newHandle, layer: layer)
            try check(mpv_initialize(newHandle), operation: "initialize")
        } catch {
            /// Drained before the handle goes away so that whatever MPV logged
            /// on its way to failing is reported alongside the failure itself.
            drainEvents()
            emit(.endFile(error: error.localizedDescription))
            destroyHandle()
            return
        }

        isInitialized = true
        mpv_set_wakeup_callback(
            newHandle,
            mpvSwiftfinWakeup,
            Unmanaged.passUnretained(self).toOpaque()
        )

        for (index, property) in Self.observedProperties.enumerated() {
            mpv_observe_property(
                newHandle,
                UInt64(index + 1),
                property.name,
                property.format
            )
        }

        if let upscalerApplication {
            applyUpscalerIfPossible(upscalerApplication)
        }

        loadPendingURLIfPossible()
    }

    /// The shortest gap between two pipeline rebuilds.
    static let upscalerApplicationInterval: UInt64 = 150_000_000

    func applyPendingUpscaler() {
        lastUpscalerApplication = DispatchTime.now().uptimeNanoseconds

        guard let upscalerApplication else { return }
        applyUpscalerIfPossible(upscalerApplication)
    }

    func applyUpscalerIfPossible(_ application: MPVUpscaler.Application) {
        guard let handle else { return }

        if application.isMetalFXEnabled != nil {
            reportIfFailed(
                mpv_set_property_string(handle, MPVUpscaler.metalFXOptionName, "no"),
                operation: "leave current MetalFX pipeline"
            )
        }

        // `change-list` avoids escaping paths against MPV's list separator.
        performCommand(["change-list", "glsl-shaders", "clr", ""])

        for path in application.shaders {
            performCommand(["change-list", "glsl-shaders", "append", path])
        }

        for (name, value) in application.options.sorted(by: { $0.key < $1.key }) {
            reportIfFailed(
                mpv_set_property_string(handle, name, value),
                operation: "set \(name)"
            )
        }

        if application.isMetalFXEnabled == true {
            reportIfFailed(
                mpv_set_property_string(handle, MPVUpscaler.metalFXOptionName, "yes"),
                operation: "enter MetalFX pipeline"
            )
        }
    }

    func setPreInitializationOptions(
        handle: OpaquePointer,
        layer: CAMetalLayer?
    ) throws {
        /// Requested first so that everything below reports through MPV's own
        /// log, including whatever it says while refusing to start.
        #if DEBUG
        try check(mpv_request_log_messages(handle, "info"), operation: "enable logging")
        #else
        try check(mpv_request_log_messages(handle, "warn"), operation: "enable logging")
        #endif

        let requiredOptions: [(name: String, value: String)]

        if let layer {
            var windowID = Int64(bitPattern: UInt64(UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque())))
            try check(
                mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &windowID),
                operation: "attach Metal layer"
            )
            requiredOptions = MPVInitialOptions.required(
                configurationDirectory: configurationStore.directoryURL.path
            )
        } else {
            requiredOptions = MPVInitialOptions.requiredForAudio(
                configurationDirectory: configurationStore.directoryURL.path
            )
        }

        for (name, value) in requiredOptions {
            try setOption(handle: handle, name: name, value: value)
        }

        /// Swiftfin's own playback settings. These are applied before
        /// `mpv_initialize`, and `mpv.conf` is read during it, so anything a
        /// user writes there still overrides all of this.
        for (name, value) in MPVInitialOptions.optional + MPVPlaybackOptions.current() {
            setOptionIfSupported(handle: handle, name: name, value: value)
        }
    }

    func setOption(handle: OpaquePointer, name: String, value: String) throws {
        try check(
            mpv_set_option_string(handle, name, value),
            operation: "configure \(name)"
        )
    }

    /// Applies an option Swiftfin can run without, keeping a build that does
    /// not have it playable.
    ///
    /// libmpv rejects an option it was not built with instead of ignoring it,
    /// and this runs before `mpv_initialize` — so treating every rejection as
    /// fatal meant one absent option aborted the whole context and no video
    /// could open at all.
    func setOptionIfSupported(handle: OpaquePointer, name: String, value: String) {
        let status = mpv_set_option_string(handle, name, value)
        guard status < 0 else { return }

        emit(.log("MPV does not support option \(name): \(String(cString: mpv_error_string(status)))"))
    }

    /// A sub-pixel nudge: `video-align-y` is a fraction of the letterbox slack,
    /// so a ten-thousandth of it never survives rounding to a whole pixel.
    static let layerSizeProbeAlignment = "0.0001"

    /// Reading a property blocks until MPV's core thread answers, and layout can
    /// run once per displayed frame, so checks are spaced out. The delayed branch
    /// means the last layout of a burst is still checked once things settle.
    static let layerSizeCheckInterval: UInt64 = 100_000_000

    func setVideoAlignY(_ value: String) {
        guard let handle else { return }
        reportIfFailed(
            mpv_set_property_string(handle, "video-align-y", value),
            operation: "resynchronize video output"
        )
    }

    func scheduleLayerSizeCheck() {
        guard !isLayerSizeCheckScheduled else { return }

        let elapsed = DispatchTime.now().uptimeNanoseconds &- lastLayerSizeCheck

        guard elapsed < Self.layerSizeCheckInterval else {
            checkLayerSize()
            return
        }

        isLayerSizeCheckScheduled = true
        queue.asyncAfter(
            deadline: .now() + .nanoseconds(Int(Self.layerSizeCheckInterval - elapsed))
        ) { [weak self] in
            guard let self else { return }
            isLayerSizeCheckScheduled = false
            checkLayerSize()
        }
    }

    func checkLayerSize() {
        lastLayerSizeCheck = DispatchTime.now().uptimeNanoseconds

        guard let handle, let layer else { return }

        let drawableSize = layer.drawableSize
        let width = Int64(drawableSize.width.rounded())
        let height = Int64(drawableSize.height.rounded())
        guard width > 0, height > 0 else { return }

        /// `osd-dimensions` is MPV's own view of the surface it draws into —
        /// `vo->dwidth` and `vo->dheight` as the last `resize` left them.
        let outputWidth = getInt64(handle: handle, name: "osd-dimensions/w")
        let outputHeight = getInt64(handle: handle, name: "osd-dimensions/h")

        /// Zero until the first file is configured, which is not drift.
        guard let outputWidth, let outputHeight, outputWidth > 0, outputHeight > 0 else { return }

        /// Said once, so that a log without any of the lines below means the
        /// sizes agreed rather than that this check never read anything.
        if !hasReportedLayerSizeCheck {
            hasReportedLayerSizeCheck = true
            emit(.log("MPV surface is \(outputWidth)x\(outputHeight) for a \(width)x\(height) layer"))
        }
        guard outputWidth != width || outputHeight != height else {
            lastReportedLayerSizeDrift = nil
            return
        }

        /// Reported once per distinct mismatch. A repair that does not take would
        /// otherwise restate the same line ten times a second for the rest of
        /// playback and bury everything else in the log.
        let drift = "\(outputWidth)x\(outputHeight) for \(width)x\(height)"
        if drift != lastReportedLayerSizeDrift {
            lastReportedLayerSizeDrift = drift
            emit(
                .log(
                    "MPV is drawing for a \(outputWidth)x\(outputHeight) surface but its layer "
                        + "is \(width)x\(height); resynchronizing"
                )
            )
        }

        /// Changing an option in MPV's video-position group runs the VO's
        /// `resize`, and `resize` asks libplacebo for the swapchain's real
        /// extent, which is the layer's. It takes two changes: the first
        /// corrects `dwidth`/`dheight` after that pass has already computed its
        /// source and destination rectangles, the second recomputes them from
        /// the corrected size. They cannot be issued back to back, because MPV
        /// coalesces option changes that land before its VO thread next runs.
        setVideoAlignY(Self.layerSizeProbeAlignment)
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.setVideoAlignY("0")
        }
    }

    func loadPendingURLIfPossible() {
        guard isInitialized, let pendingURL else { return }
        self.pendingURL = nil

        /// Always written, so that the position asked for by one item cannot
        /// carry over into the next one loaded into the same context.
        if let handle {
            reportIfFailed(
                mpv_set_property_string(
                    handle,
                    "start",
                    pendingStartSeconds > 0 ? String(pendingStartSeconds) : "none"
                ),
                operation: "set start position"
            )
        }
        pendingStartSeconds = 0

        performCommand(["loadfile", pendingURL.absoluteString, "replace"])
    }

    func command(_ arguments: [String]) {
        queue.async { [weak self] in
            self?.performCommand(arguments)
        }
    }

    func performCommand(_ arguments: [String]) {
        guard let handle, arguments.isNotEmpty else { return }

        var cArguments: [UnsafePointer<CChar>?] = arguments.map { argument in
            UnsafePointer(strdup(argument))
        }
        cArguments.append(nil)
        defer {
            for argument in cArguments.compactMap(\.self) {
                free(UnsafeMutablePointer(mutating: argument))
            }
        }

        reportIfFailed(
            mpv_command(handle, &cArguments),
            operation: arguments[0]
        )
    }

    func performCommand(
        _ arguments: [String],
        continuation: CheckedContinuation<Void, any Error>
    ) {
        guard let handle, arguments.isNotEmpty else {
            continuation.resume(throwing: MPVClientError.terminated)
            return
        }

        let commandID = nextCommandID
        nextCommandID &+= 1
        pendingCommands[commandID] = continuation

        var cArguments: [UnsafePointer<CChar>?] = arguments.map { argument in
            UnsafePointer(strdup(argument))
        }
        cArguments.append(nil)
        defer {
            for argument in cArguments.compactMap(\.self) {
                free(UnsafeMutablePointer(mutating: argument))
            }
        }

        let status = mpv_command_async(handle, commandID, &cArguments)
        guard status < 0 else { return }

        pendingCommands.removeValue(forKey: commandID)?.resume(
            throwing: MPVClientError.api(operation: arguments[0], code: status)
        )
    }

    func setFlag(name: String, value: Bool) {
        queue.async { [weak self] in
            guard let self, let handle else { return }
            var flag: Int32 = value ? 1 : 0
            reportIfFailed(
                mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag),
                operation: "set \(name)"
            )
        }
    }

    func setDouble(name: String, value: Double) {
        queue.async { [weak self] in
            guard let self, let handle else { return }
            var value = value
            reportIfFailed(
                mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &value),
                operation: "set \(name)"
            )
        }
    }

    func applyDesiredTrack(kind: MPVTrack.Kind) {
        guard let desired = desiredTracks[kind], let handle else { return }
        let property = kind == .audio ? "aid" : "sid"

        guard let ffIndex = desired.ffIndex, ffIndex >= 0 else {
            reportIfFailed(
                mpv_set_property_string(handle, property, "no"),
                operation: "disable \(kind.rawValue) track"
            )
            return
        }

        guard let track = tracks.first(where: {
            $0.kind == desired.kind && $0.ffIndex == ffIndex
        }) ?? tracks.first(where: {
            $0.kind == desired.kind && $0.id == Int64(ffIndex)
        }) else { return }

        reportIfFailed(
            mpv_set_property_string(handle, property, String(track.id)),
            operation: "select \(kind.rawValue) track"
        )
    }

    func wakeup() {
        queue.async { [weak self] in
            self?.drainEvents()
        }
    }

    func drainEvents() {
        guard let handle else { return }

        while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
            switch event.pointee.event_id {
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event.pointee.data)
            case MPV_EVENT_FILE_LOADED:
                rebuildTracks()
                emit(.fileLoaded)
            case MPV_EVENT_END_FILE:
                handleEndFile(event.pointee.data)
            case MPV_EVENT_LOG_MESSAGE:
                handleLogMessage(event.pointee.data)
            case MPV_EVENT_COMMAND_REPLY:
                handleCommandReply(
                    id: event.pointee.reply_userdata,
                    error: event.pointee.error
                )
            default:
                break
            }
        }
    }

    func handleCommandReply(id: UInt64, error: Int32) {
        guard let continuation = pendingCommands.removeValue(forKey: id) else { return }

        if error < 0 {
            continuation.resume(throwing: MPVClientError.api(operation: "command", code: error))
        } else {
            continuation.resume()
        }
    }

    func handlePropertyChange(_ data: UnsafeMutableRawPointer?) {
        guard let data else { return }
        let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
        guard let namePointer = property.name else { return }
        let name = String(cString: namePointer)
        let value: MPVPropertyValue

        guard let propertyData = property.data else {
            emit(.property(name: name, value: .unavailable))
            return
        }

        switch property.format {
        case MPV_FORMAT_FLAG:
            value = .bool(propertyData.assumingMemoryBound(to: Int32.self).pointee != 0)
        case MPV_FORMAT_DOUBLE:
            value = .double(propertyData.assumingMemoryBound(to: Double.self).pointee)
        case MPV_FORMAT_INT64:
            value = .integer(propertyData.assumingMemoryBound(to: Int64.self).pointee)
        case MPV_FORMAT_STRING:
            let stringPointer = propertyData
                .assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                .pointee
            value = stringPointer.map { .string(String(cString: $0)) } ?? .unavailable
        default:
            value = .unavailable
        }

        emit(.property(name: name, value: value))

        if name == "track-list/count" {
            rebuildTracks()
        }
    }

    func rebuildTracks() {
        guard let handle else { return }
        let count = Int(getInt64(handle: handle, name: "track-list/count") ?? 0)
        tracks = (0 ..< count).compactMap { index in
            guard let type = getString(handle: handle, name: "track-list/\(index)/type"),
                  let id = getInt64(handle: handle, name: "track-list/\(index)/id")
            else { return nil }

            return MPVTrack(
                id: id,
                ffIndex: getInt64(handle: handle, name: "track-list/\(index)/ff-index").map(Int.init),
                kind: MPVTrack.Kind(rawValue: type) ?? .unknown,
                title: getString(handle: handle, name: "track-list/\(index)/title")
                    ?? getString(handle: handle, name: "track-list/\(index)/lang")
                    ?? "Track \(id)",
                language: getString(handle: handle, name: "track-list/\(index)/lang"),
                codec: getString(handle: handle, name: "track-list/\(index)/codec"),
                isExternal: getFlag(handle: handle, name: "track-list/\(index)/external") ?? false,
                isSelected: getFlag(handle: handle, name: "track-list/\(index)/selected") ?? false
            )
        }

        applyDesiredTrack(kind: .audio)
        applyDesiredTrack(kind: .subtitle)
        emit(.tracks(tracks))
    }

    func handleEndFile(_ data: UnsafeMutableRawPointer?) {
        guard let data else {
            emit(.endFile(error: nil))
            return
        }
        let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
        if endFile.error < 0 {
            emit(.endFile(error: String(cString: mpv_error_string(endFile.error))))
        } else if endFile.reason == MPV_END_FILE_REASON_EOF {
            emit(.endFile(error: nil))
        }
    }

    func handleLogMessage(_ data: UnsafeMutableRawPointer?) {
        guard let data else { return }
        let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
        guard let prefix = message.prefix, let level = message.level, let text = message.text else { return }
        emit(.log("[\(String(cString: prefix))] \(String(cString: level)): \(String(cString: text))"))
    }

    func getString(handle: OpaquePointer, name: String) -> String? {
        guard let value = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    func getInt64(handle: OpaquePointer, name: String) -> Int64? {
        var value = Int64()
        guard mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return value
    }

    func getFlag(handle: OpaquePointer, name: String) -> Bool? {
        var value = Int32()
        guard mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 else { return nil }
        return value != 0
    }

    func check(_ code: Int32, operation: String) throws {
        guard code >= 0 else { throw MPVClientError.api(operation: operation, code: code) }
    }

    func reportIfFailed(_ code: Int32, operation: String) {
        guard code < 0 else { return }
        emit(.log(MPVClientError.api(operation: operation, code: code).localizedDescription))
    }

    func emit(_ event: Event) {
        eventHandler?(event)
    }

    func destroyHandle() {
        guard let handle else { return }
        mpv_set_wakeup_callback(handle, nil, nil)

        let continuations = Array(pendingCommands.values)
        pendingCommands.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: MPVClientError.terminated)
        }

        mpv_terminate_destroy(handle)
        self.handle = nil
        isInitialized = false
        hasReportedLayerSizeCheck = false
        lastReportedLayerSizeDrift = nil
        tracks = []
        layer = nil
    }
}

private final class MPVDetachedHandle: @unchecked Sendable {
    private let handle: OpaquePointer

    init(_ handle: OpaquePointer) {
        self.handle = handle
    }

    func destroy() {
        mpv_terminate_destroy(handle)
    }
}

private func mpvSwiftfinWakeup(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<MPVClientCore>
        .fromOpaque(context)
        .takeUnretainedValue()
        .wakeup()
}
#endif

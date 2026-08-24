//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import AVFoundation
import Combine
import CoreVideo
import Defaults
import Foundation
import Metal
import QuartzCore
import UIKit

struct EnhancedSubtitleTimeline {
    struct Event {
        let presentationTime: CMTime
        let text: String?
    }

    private(set) var events: [Event] = []

    mutating func record(text: String?, at presentationTime: CMTime) {
        guard presentationTime.isValid, !presentationTime.isIndefinite else { return }

        // Legible output is monotonic during normal playback. A backwards
        // timestamp means AVPlayer crossed a seek/discontinuity, so captions
        // from the old playback position must not leak into the new one.
        if let last = events.last,
           CMTimeCompare(presentationTime, last.presentationTime) < 0
        {
            events.removeAll(keepingCapacity: true)
        }

        if let index = events.lastIndex(where: {
            CMTimeCompare($0.presentationTime, presentationTime) == 0
        }) {
            events[index] = Event(presentationTime: presentationTime, text: text)
        } else {
            events.append(Event(presentationTime: presentationTime, text: text))
        }

        // This is only a synchronization window, not a subtitle archive.
        if events.count > 256 {
            events.removeFirst(events.count - 256)
        }
    }

    func text(at presentationTime: CMTime) -> String? {
        guard presentationTime.isValid, !presentationTime.isIndefinite else { return nil }
        return events.last(where: {
            CMTimeCompare($0.presentationTime, presentationTime) <= 0
        })?.text
    }

    mutating func removeAll() {
        events.removeAll(keepingCapacity: true)
    }
}

@MainActor
final class VideoEnhancementController: NSObject, ObservableObject {
    @Published
    private(set) var activeLevel: VideoEnhancementLevel = .balanced
    @Published
    private(set) var averageProcessingTime: TimeInterval = 0
    @Published
    private(set) var avPlayerDroppedFrames = 0
    @Published
    private(set) var bypassReason: VideoEnhancementBypassReason?
    @Published
    private(set) var displayFrameRate: Double = 0
    @Published
    private(set) var enhancedDroppedFrames = 0
    @Published
    private(set) var recentEnhancedDroppedFrames = 0
    @Published
    private(set) var recentEnhancedDropRate: Double = 0
    private(set) var frameRevision: UInt64 = 0
    @Published
    private(set) var isUsingNativePlaybackLayer = true
    @Published
    private(set) var outputSize: CGSize = .zero
    @Published
    private(set) var percentile95ProcessingTime: TimeInterval = 0
    @Published
    private(set) var sourceFrameRate: Double = 24
    @Published
    private(set) var sourceRotationDegrees = 0
    @Published
    private(set) var sourceSize: CGSize = .zero
    @Published
    private(set) var subtitleText: String?
    @Published
    private(set) var usesCustomSubtitleRendering = true

    @Published
    var isComparisonEnabled = false
    @Published
    var requestedProvider: VideoEnhancementProvider {
        didSet {
            guard requestedProvider != oldValue else { return }
            Defaults[.VideoPlayer.enhancementProvider] = requestedProvider
            replaceProcessor()
        }
    }

    @Published
    var matchesSourceFrameRate: Bool {
        didSet { Defaults[.VideoPlayer.enhancementMatchesSourceFrameRate] = matchesSourceFrameRate }
    }

    @Published
    var isPictureInPictureActive = false {
        didSet {
            guard isPictureInPictureActive != oldValue else { return }
            handlePictureInPictureChange()
        }
    }

    @Published
    var requestedMode: VideoEnhancementMode {
        didSet {
            Defaults[.VideoPlayer.enhancementMode] = requestedMode
            resetPerformanceWindow(
                at: CACurrentMediaTime(),
                startingAt: requestedMode.fixedLevel ?? .balanced
            )
            refreshActiveLevel()
            refreshBypassReason()
        }
    }

    @Published
    var showsPerformanceHUD: Bool {
        didSet { Defaults[.VideoPlayer.enhancementPerformanceHUD] = showsPerformanceHUD }
    }

    var isAspectFilled = false
    private(set) var latestPixelBuffer: CVPixelBuffer?

    private let player: AVPlayer
    private var processor: (any VideoFrameProcessor)?
    private let processingQueue = DispatchQueue(label: "org.jellyfin.swiftfin.video-enhancement", qos: .userInteractive)
    private let subtitleOutput = AVPlayerItemLegibleOutput()
    private let videoOutput: AVPlayerItemVideoOutput

    private var adaptivePolicy = EnhancementAdaptivePolicy()
    private var currentItem: AVPlayerItem?
    private var frameSamples: [EnhancementPerformanceSample] = []
    private var isLowMemory = false
    private var isHDR = false
    private var isLiveStream = false
    private var isPixelFormatSupported = true
    private var isProcessingFrame = false
    private var pendingFrames = LatestFrameQueue<VideoFrameContext>()
    private var memoryRecoveryWorkItem: DispatchWorkItem?
    private var notificationTokens: [NSObjectProtocol] = []
    private var processingFailureGeneration: Int64?
    private var renderTickCount = 0
    private var renderTickWindowStart = CACurrentMediaTime()
    private var sessionGeneration: Int64 = 0
    private var latestPublishedPresentationTime: CMTime?
    private var subtitleSelectionTask: Task<Void, Never>?
    private var subtitleTimeline = EnhancedSubtitleTimeline()
    private var targetSize: CGSize = .zero
    private var thermalRecoveryWorkItem: DispatchWorkItem?
    private var retainsCriticalThermalBypass = false
    private var lastAccessLogUpdate = 0.0

    init(player: AVPlayer) {
        let requestedProvider = Defaults[.VideoPlayer.enhancementProvider]
        self.player = player
        self.requestedProvider = requestedProvider
        self.requestedMode = Defaults[.VideoPlayer.enhancementMode]
        self.matchesSourceFrameRate = Defaults[.VideoPlayer.enhancementMatchesSourceFrameRate]
        self.showsPerformanceHUD = Defaults[.VideoPlayer.enhancementPerformanceHUD]

        let attributes: [String: Any] = [
            // MetalFX consumes BGRA directly. Asking AVFoundation for BGRA avoids
            // the provider's former NV12-to-BGRA conversion and its extra full-
            // resolution intermediate texture on every frame.
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)

        self.processor = Self.makeProcessor(for: requestedProvider)

        super.init()

        adaptivePolicy.reset(
            at: CACurrentMediaTime(),
            startingAt: requestedMode.fixedLevel ?? .balanced
        )
        subtitleOutput.setDelegate(self, queue: .main)
        subtitleOutput.suppressesPlayerRendering = true
        observeSystemState()
        refreshActiveLevel()
        refreshBypassReason()
    }

    deinit {
        subtitleSelectionTask?.cancel()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        thermalRecoveryWorkItem?.cancel()
        memoryRecoveryWorkItem?.cancel()
    }

    func configure(playerItem: AVPlayerItem, mediaPlayerItem: MediaPlayerItem) {
        if let currentItem {
            currentItem.remove(videoOutput)
            currentItem.remove(subtitleOutput)
        }

        sessionGeneration += 1
        currentItem = playerItem
        playerItem.add(videoOutput)
        playerItem.add(subtitleOutput)
        processor?.invalidate(sessionGeneration: sessionGeneration)

        let stream = mediaPlayerItem.videoStreams.first
        sourceSize = CGSize(width: stream?.width ?? 0, height: stream?.height ?? 0)
        sourceRotationDegrees = VideoEnhancementGeometry.normalizedRotation(stream?.rotation ?? 0)
        sourceFrameRate = Double(stream?.realFrameRate ?? stream?.averageFrameRate ?? 24)
        isLiveStream = mediaPlayerItem.baseItem.isLiveStream
        isHDR = stream?.videoRangeType?.isHDR == true
        isPixelFormatSupported = true

        adaptivePolicy.reset(
            at: CACurrentMediaTime(),
            startingAt: requestedMode.fixedLevel ?? .balanced
        )
        frameSamples.removeAll(keepingCapacity: true)
        latestPixelBuffer = nil
        latestPublishedPresentationTime = nil
        subtitleText = nil
        subtitleTimeline.removeAll()
        outputSize = .zero
        enhancedDroppedFrames = 0
        recentEnhancedDroppedFrames = 0
        recentEnhancedDropRate = 0
        averageProcessingTime = 0
        percentile95ProcessingTime = 0
        isProcessingFrame = false
        pendingFrames.removeAll()
        isComparisonEnabled = false
        processingFailureGeneration = nil
        selectSubtitle(for: mediaPlayerItem, in: playerItem, generation: sessionGeneration)
        refreshActiveLevel()
        refreshBypassReason()
    }

    func invalidate() {
        sessionGeneration += 1
        subtitleSelectionTask?.cancel()
        subtitleSelectionTask = nil
        if let currentItem {
            currentItem.remove(videoOutput)
            currentItem.remove(subtitleOutput)
        }
        currentItem = nil
        latestPixelBuffer = nil
        latestPublishedPresentationTime = nil
        subtitleText = nil
        subtitleTimeline.removeAll()
        isProcessingFrame = false
        pendingFrames.removeAll()
        isPixelFormatSupported = true
        processingFailureGeneration = nil
        processor?.invalidate(sessionGeneration: sessionGeneration)
        processor?.drain()
    }

    private func replaceProcessor() {
        sessionGeneration += 1

        let previousProcessor = processor
        previousProcessor?.invalidate(sessionGeneration: sessionGeneration)
        previousProcessor?.drain()

        processor = Self.makeProcessor(for: requestedProvider)
        processor?.invalidate(sessionGeneration: sessionGeneration)
        isProcessingFrame = false
        pendingFrames.removeAll()
        latestPixelBuffer = nil
        outputSize = .zero
        processingFailureGeneration = nil
        resetPerformanceWindow(
            at: CACurrentMediaTime(),
            startingAt: requestedMode.fixedLevel ?? .balanced
        )
        refreshActiveLevel()
        refreshBypassReason()
    }

    private static func makeProcessor(
        for provider: VideoEnhancementProvider
    ) -> (any VideoFrameProcessor)? {
        guard MTLCreateSystemDefaultDevice() != nil else { return nil }

        do {
            switch provider {
            case .metalFX:
                return try MetalFXFrameProcessor()
            case .anime4K:
                #if !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
                return try Anime4KFrameProcessor()
                #else
                return nil
                #endif
            }
        } catch {
            return nil
        }
    }

    func renderTick(hostTime: CFTimeInterval, targetSize: CGSize) {
        self.targetSize = targetSize
        updateDisplayFrameRate(at: hostTime)
        updateAccessLogIfNeeded(at: hostTime)
        refreshBypassReason()

        guard !isUsingNativePlaybackLayer else { return }

        let itemTime = videoOutput.itemTime(forHostTime: hostTime)
        var presentationTime = CMTime.invalid
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(
                  forItemTime: itemTime,
                  itemTimeForDisplay: &presentationTime
              )
        else { return }
        if !presentationTime.isValid || presentationTime.isIndefinite {
            presentationTime = itemTime
        }

        let pixelSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        if sourceSize == .zero {
            sourceSize = pixelSize
        }

        guard Self.supports(pixelBuffer: pixelBuffer) else {
            isPixelFormatSupported = false
            refreshBypassReason()
            return
        }

        guard let processor else {
            refreshBypassReason()
            return
        }

        let generation = sessionGeneration
        let level = activeLevel
        let comparisonEnabled = isComparisonEnabled
        let frameRate = max(1, sourceFrameRate)
        let processingTargetSize = VideoEnhancementGeometry.orientedSize(
            targetSize,
            rotationDegrees: sourceRotationDegrees
        )
        let context = VideoFrameContext(
            pixelBuffer: pixelBuffer,
            presentationTime: presentationTime,
            duration: CMTime(seconds: 1 / frameRate, preferredTimescale: 600),
            sourceFrameRate: frameRate,
            sourceSize: pixelSize,
            visibleSourceSize: VideoEnhancementGeometry.visibleSourcePixelSize(
                sourceSize: pixelSize,
                targetSize: processingTargetSize,
                fill: isAspectFilled
            ),
            targetSize: processingTargetSize,
            sessionGeneration: generation,
            level: level,
            isComparisonEnabled: comparisonEnabled
        )

        if isProcessingFrame {
            if pendingFrames.enqueue(context) {
                enhancedDroppedFrames += 1
                recordSample(duration: 0, wasDropped: true, at: hostTime)
            }
            return
        }

        if latestPixelBuffer == nil {
            publish(pixelBuffer, presentationTime: presentationTime)
        }
        process(context, with: processor)
    }

    func rendererDidPresentFrame() {
        renderTickCount += 1
    }

    private func process(_ context: VideoFrameContext, with processor: any VideoFrameProcessor) {
        isProcessingFrame = true
        let startedAt = CACurrentMediaTime()

        processingQueue.async { [weak self] in
            let result: VideoFrameResult
            do {
                result = try processor.process(context)
            } catch {
                result = .passthrough
            }
            let duration = CACurrentMediaTime() - startedAt

            Task { @MainActor [weak self] in
                guard let self, context.sessionGeneration == self.sessionGeneration else { return }
                self.isProcessingFrame = false

                switch result {
                case .passthrough:
                    self.pendingFrames.removeAll()
                    self.publish(context.pixelBuffer, presentationTime: context.presentationTime)
                    self.temporarilyBypassAfterProcessingFailure()
                case let .replace(output):
                    self.publish(output, presentationTime: context.presentationTime)
                    self.outputSize = CGSize(
                        width: CVPixelBufferGetWidth(output),
                        height: CVPixelBufferGetHeight(output)
                    )
                }

                self.recordSample(duration: duration, wasDropped: false, at: CACurrentMediaTime())

                if let pendingFrame = self.pendingFrames.dequeue(), self.bypassReason == nil {
                    self.process(pendingFrame, with: processor)
                }
            }
        }
    }

    private static func supports(pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
    }

    private func refreshBypassReason() {
        let reason = VideoEnhancementEligibility.bypassReason(for: .init(
            mode: requestedMode,
            hasProcessor: processor != nil,
            isLiveStream: isLiveStream,
            isHDR: isHDR,
            isExternalPlaybackActive: player.isExternalPlaybackActive,
            isPictureInPictureActive: isPictureInPictureActive,
            retainsCriticalThermalBypass: retainsCriticalThermalBypass,
            isLowMemory: isLowMemory,
            hasProcessingFailure: processingFailureGeneration == sessionGeneration,
            isPixelFormatSupported: isPixelFormatSupported,
            sourceSize: VideoEnhancementGeometry.orientedSize(
                sourceSize,
                rotationDegrees: sourceRotationDegrees
            ),
            targetSize: targetSize
        ))

        bypassReason = reason
        isUsingNativePlaybackLayer = reason != nil
        videoOutput.suppressesPlayerRendering = reason == nil
        refreshSubtitlePresentation()
    }

    private func refreshSubtitlePresentation() {
        let usesSystemSubtitleRendering = isPictureInPictureActive || player.isExternalPlaybackActive
        subtitleOutput.suppressesPlayerRendering = !usesSystemSubtitleRendering
        usesCustomSubtitleRendering = !usesSystemSubtitleRendering
        synchronizeSubtitleText()
    }

    private func selectSubtitle(
        for mediaPlayerItem: MediaPlayerItem,
        in playerItem: AVPlayerItem,
        generation: Int64
    ) {
        subtitleSelectionTask?.cancel()

        let selectedIndex = mediaPlayerItem.selectedSubtitleStreamIndex
        let selectedStream = selectedIndex.flatMap { index in
            mediaPlayerItem.subtitleStreams.first { $0.index == index }
        }

        subtitleSelectionTask = Task { @MainActor [weak self, weak playerItem] in
            guard let self, let playerItem else { return }

            do {
                guard let group = try await playerItem.asset.loadMediaSelectionGroup(for: .legible),
                      !Task.isCancelled,
                      generation == self.sessionGeneration,
                      playerItem === self.currentItem
                else { return }

                guard let selectedIndex, selectedIndex != -1 else {
                    playerItem.select(nil, in: group)
                    self.subtitleText = nil
                    return
                }

                let language = selectedStream?.language?.lowercased()
                let title = selectedStream?.displayTitle?.lowercased()
                let option = group.options.first { option in
                    if let language,
                       option.extendedLanguageTag?.lowercased().hasPrefix(language) == true
                    {
                        return true
                    }
                    if let title {
                        let optionTitle = option.displayName.lowercased()
                        if title.contains(optionTitle) || optionTitle.contains(title) {
                            return true
                        }
                    }
                    return false
                } ?? (group.options.count == 1 ? group.options.first : nil)

                // Jellyfin HLS normally exposes only the requested subtitle. If
                // its metadata does not match exactly, choosing the first legible
                // option is safer than suppressing captions and showing nothing.
                playerItem.select(option ?? group.options.first, in: group)
            } catch {
                // Encoded/image subtitles have no legible group because they are
                // already part of the video. Playback continues unchanged.
            }
        }
    }

    private func handlePictureInPictureChange() {
        if isPictureInPictureActive {
            // Invalidate work submitted by the inline Metal renderer. The serial
            // processing queue may finish its current command, but its result can
            // no longer be published and no queued frame will follow it.
            sessionGeneration += 1
            isProcessingFrame = false
            pendingFrames.removeAll()
            latestPixelBuffer = nil
            outputSize = .zero
            processor?.invalidate(sessionGeneration: sessionGeneration)
            processor?.drain()
        }

        refreshBypassReason()
    }

    private func refreshActiveLevel() {
        guard requestedMode != .off else {
            activeLevel = .fast
            return
        }
        activeLevel = min(adaptivePolicy.level, maximumAllowedLevel)
    }

    private func recordSample(duration: TimeInterval, wasDropped: Bool, at timestamp: TimeInterval) {
        let sample = EnhancementPerformanceSample(
            timestamp: timestamp,
            processingDuration: duration,
            wasDropped: wasDropped
        )
        frameSamples.append(sample)
        frameSamples.removeAll { timestamp - $0.timestamp > 3 }

        recentEnhancedDroppedFrames = frameSamples.count(where: \.wasDropped)
        recentEnhancedDropRate = frameSamples.isEmpty
            ? 0
            : Double(recentEnhancedDroppedFrames) / Double(frameSamples.count)

        let completedDurations = frameSamples.filter { !$0.wasDropped }.map(\.processingDuration)
        averageProcessingTime = completedDurations.isEmpty
            ? 0
            : completedDurations.reduce(0, +) / Double(completedDurations.count)
        percentile95ProcessingTime = EnhancementAdaptivePolicy.percentile95(completedDurations)

        if requestedMode != .off {
            let frameDuration = 1 / max(1, sourceFrameRate)
            activeLevel = adaptivePolicy.record(
                sample,
                frameDuration: frameDuration,
                maximumLevel: maximumAllowedLevel
            )
        } else {
            refreshActiveLevel()
        }
    }

    private var maximumAllowedLevel: VideoEnhancementLevel {
        let deviceMaximum = VideoEnhancementDevicePolicy.maximumLevel(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        return min(requestedMode.fixedLevel ?? .quality, deviceMaximum)
    }

    private func publish(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        latestPixelBuffer = pixelBuffer
        latestPublishedPresentationTime = presentationTime
        synchronizeSubtitleText()
        frameRevision &+= 1
    }

    private func recordSubtitle(text: String?, at presentationTime: CMTime) {
        subtitleTimeline.record(text: text, at: presentationTime)
        synchronizeSubtitleText()
    }

    private func synchronizeSubtitleText() {
        guard usesCustomSubtitleRendering else {
            subtitleText = nil
            return
        }

        // The enhanced image becomes visible only after GPU processing. Keying
        // captions to that frame's PTS keeps them with the image instead of the
        // AVPlayer audio clock. Native fallback has no processing delay.
        let presentationTime = isUsingNativePlaybackLayer
            ? player.currentTime()
            : latestPublishedPresentationTime
        guard let presentationTime else { return }
        subtitleText = subtitleTimeline.text(at: presentationTime)
    }

    private func resetPerformanceWindow(
        at timestamp: TimeInterval,
        startingAt level: VideoEnhancementLevel
    ) {
        adaptivePolicy.reset(at: timestamp, startingAt: level)
        frameSamples.removeAll(keepingCapacity: true)
        pendingFrames.removeAll()
        averageProcessingTime = 0
        percentile95ProcessingTime = 0
        recentEnhancedDroppedFrames = 0
        recentEnhancedDropRate = 0
    }

    private func updateDisplayFrameRate(at timestamp: TimeInterval) {
        let elapsed = timestamp - renderTickWindowStart
        guard elapsed >= 1 else { return }
        displayFrameRate = Double(renderTickCount) / elapsed
        renderTickCount = 0
        renderTickWindowStart = timestamp
    }

    private func updateAccessLogIfNeeded(at timestamp: TimeInterval) {
        guard timestamp - lastAccessLogUpdate >= 1 else { return }
        lastAccessLogUpdate = timestamp
        avPlayerDroppedFrames = currentItem?.accessLog()?.events.reduce(0) {
            $0 + $1.numberOfDroppedVideoFrames
        } ?? 0
    }

    private func temporarilyBypassAfterProcessingFailure() {
        processingFailureGeneration = sessionGeneration
        refreshBypassReason()

        let generation = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.sessionGeneration == generation else { return }
            self.processingFailureGeneration = nil
            self.refreshBypassReason()
        }
    }

    func rendererDidFail() {
        temporarilyBypassAfterProcessingFailure()
    }

    private func observeSystemState() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.thermalStateDidChange() }
        })
        notificationTokens.append(center.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshActiveLevel()
                self?.refreshBypassReason()
            }
        })
        notificationTokens.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.receivedMemoryWarning() }
        })
    }

    private func thermalStateDidChange() {
        thermalRecoveryWorkItem?.cancel()

        switch ProcessInfo.processInfo.thermalState {
        case .critical:
            retainsCriticalThermalBypass = true
        case .serious:
            break
        case .fair, .nominal:
            guard retainsCriticalThermalBypass else { break }
            let workItem = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self,
                          VideoEnhancementDevicePolicy.shouldReleaseCriticalBypass(
                              thermalState: ProcessInfo.processInfo.thermalState,
                              secondsBelowSerious: VideoEnhancementDevicePolicy.criticalThermalRecoveryInterval
                          )
                    else { return }
                    self.retainsCriticalThermalBypass = false
                    self.refreshBypassReason()
                }
            }
            thermalRecoveryWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + VideoEnhancementDevicePolicy.criticalThermalRecoveryInterval,
                execute: workItem
            )
        @unknown default:
            retainsCriticalThermalBypass = true
        }

        refreshActiveLevel()
        refreshBypassReason()
    }

    private func receivedMemoryWarning() {
        isLowMemory = true
        latestPixelBuffer = nil
        processor?.drain()
        refreshBypassReason()

        memoryRecoveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.isLowMemory = false
                self?.refreshBypassReason()
            }
        }
        memoryRecoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }
}

extension VideoEnhancementController: AVPlayerItemLegibleOutputPushDelegate {
    nonisolated func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings
            .map(\.string)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor [weak self] in
            guard let self,
                  output === self.subtitleOutput
            else { return }
            self.recordSubtitle(
                text: text.isEmpty ? nil : text,
                at: itemTime
            )
        }
    }
}
#endif

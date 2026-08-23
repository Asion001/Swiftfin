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

@MainActor
final class VideoEnhancementController: ObservableObject {
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
    var isComparisonEnabled = false
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
    private let processor: (any VideoFrameProcessor)?
    private let processingQueue = DispatchQueue(label: "org.jellyfin.swiftfin.video-enhancement", qos: .userInteractive)
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
    private var targetSize: CGSize = .zero
    private var thermalRecoveryWorkItem: DispatchWorkItem?
    private var retainsCriticalThermalBypass = false
    private var lastAccessLogUpdate = 0.0

    init(player: AVPlayer) {
        self.player = player
        self.requestedMode = Defaults[.VideoPlayer.enhancementMode]
        self.matchesSourceFrameRate = Defaults[.VideoPlayer.enhancementMatchesSourceFrameRate]
        self.showsPerformanceHUD = Defaults[.VideoPlayer.enhancementPerformanceHUD]

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)

        if MTLCreateSystemDefaultDevice() == nil {
            self.processor = nil
        } else {
            do {
                self.processor = try Anime4KFrameProcessor()
            } catch {
                self.processor = nil
            }
        }

        observeSystemState()
        refreshActiveLevel()
        refreshBypassReason()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        thermalRecoveryWorkItem?.cancel()
        memoryRecoveryWorkItem?.cancel()
    }

    func configure(playerItem: AVPlayerItem, mediaPlayerItem: MediaPlayerItem) {
        if let currentItem {
            currentItem.remove(videoOutput)
        }

        sessionGeneration += 1
        currentItem = playerItem
        playerItem.add(videoOutput)
        processor?.invalidate(sessionGeneration: sessionGeneration)

        let stream = mediaPlayerItem.videoStreams.first
        sourceSize = CGSize(width: stream?.width ?? 0, height: stream?.height ?? 0)
        sourceRotationDegrees = VideoEnhancementGeometry.normalizedRotation(stream?.rotation ?? 0)
        sourceFrameRate = Double(stream?.realFrameRate ?? stream?.averageFrameRate ?? 24)
        isLiveStream = mediaPlayerItem.baseItem.isLiveStream
        isHDR = stream?.videoRangeType?.isHDR == true
        isPixelFormatSupported = true

        adaptivePolicy.reset(at: CACurrentMediaTime())
        frameSamples.removeAll(keepingCapacity: true)
        latestPixelBuffer = nil
        outputSize = .zero
        enhancedDroppedFrames = 0
        averageProcessingTime = 0
        percentile95ProcessingTime = 0
        isProcessingFrame = false
        pendingFrames.removeAll()
        isComparisonEnabled = false
        processingFailureGeneration = nil
        refreshActiveLevel()
        refreshBypassReason()
    }

    func invalidate() {
        sessionGeneration += 1
        if let currentItem {
            currentItem.remove(videoOutput)
        }
        currentItem = nil
        latestPixelBuffer = nil
        isProcessingFrame = false
        pendingFrames.removeAll()
        isPixelFormatSupported = true
        processingFailureGeneration = nil
        processor?.invalidate(sessionGeneration: sessionGeneration)
        processor?.drain()
    }

    func renderTick(hostTime: CFTimeInterval, targetSize: CGSize) {
        self.targetSize = targetSize
        updateDisplayFrameRate(at: hostTime)
        updateAccessLogIfNeeded(at: hostTime)
        refreshBypassReason()

        guard !isUsingNativePlaybackLayer else { return }

        let itemTime = videoOutput.itemTime(forHostTime: hostTime)
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }

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
        let context = VideoFrameContext(
            pixelBuffer: pixelBuffer,
            presentationTime: itemTime,
            duration: CMTime(seconds: 1 / frameRate, preferredTimescale: 600),
            sourceFrameRate: frameRate,
            sourceSize: pixelSize,
            targetSize: VideoEnhancementGeometry.orientedSize(
                targetSize,
                rotationDegrees: sourceRotationDegrees
            ),
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

        latestPixelBuffer = latestPixelBuffer ?? pixelBuffer
        process(context, with: processor)
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
                    self.latestPixelBuffer = context.pixelBuffer
                    self.temporarilyBypassAfterProcessingFailure()
                case let .replace(output):
                    self.latestPixelBuffer = output
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
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_32BGRA,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            true
        default:
            false
        }
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
        let maximumLevel = VideoEnhancementDevicePolicy.maximumLevel(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )

        if let fixedLevel = requestedMode.fixedLevel {
            activeLevel = min(fixedLevel, maximumLevel)
        } else if requestedMode == .auto {
            activeLevel = min(adaptivePolicy.level, maximumLevel)
        } else {
            activeLevel = .fast
        }
    }

    private func recordSample(duration: TimeInterval, wasDropped: Bool, at timestamp: TimeInterval) {
        let sample = EnhancementPerformanceSample(
            timestamp: timestamp,
            processingDuration: duration,
            wasDropped: wasDropped
        )
        frameSamples.append(sample)
        frameSamples.removeAll { timestamp - $0.timestamp > 3 }

        let completedDurations = frameSamples.filter { !$0.wasDropped }.map(\.processingDuration)
        averageProcessingTime = completedDurations.isEmpty
            ? 0
            : completedDurations.reduce(0, +) / Double(completedDurations.count)
        percentile95ProcessingTime = EnhancementAdaptivePolicy.percentile95(completedDurations)

        if requestedMode == .auto {
            let frameDuration = 1 / max(1, sourceFrameRate)
            let maximumLevel = VideoEnhancementDevicePolicy.maximumLevel(
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                thermalState: ProcessInfo.processInfo.thermalState
            )
            activeLevel = adaptivePolicy.record(sample, frameDuration: frameDuration, maximumLevel: maximumLevel)
        } else {
            refreshActiveLevel()
        }
    }

    private func updateDisplayFrameRate(at timestamp: TimeInterval) {
        renderTickCount += 1
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
#endif

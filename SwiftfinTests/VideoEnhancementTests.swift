//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreMedia
import CoreVideo
import Metal
@testable import Swiftfin_iOS
import XCTest

final class VideoEnhancementTests: XCTestCase {
    @MainActor
    func testSleepTimerCountdownExtensionAndExpiration() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        var expirationCount = 0
        let controller = SleepTimerController(
            now: { currentDate },
            startsTicker: false,
            expirationHandler: { expirationCount += 1 }
        )

        controller.set(duration: 15 * 60)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.remainingDuration, 15 * 60)

        currentDate = currentDate.addingTimeInterval(5 * 60)
        controller.reconcile()
        XCTAssertEqual(controller.remainingDuration, 10 * 60)

        controller.add(duration: 15 * 60)
        XCTAssertEqual(controller.remainingDuration, 25 * 60)

        currentDate = currentDate.addingTimeInterval(25 * 60)
        controller.reconcile()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.remainingDuration, 0)
        XCTAssertEqual(controller.expirationCount, 1)
        XCTAssertEqual(expirationCount, 1)

        controller.reconcile()
        XCTAssertEqual(expirationCount, 1)
    }

    @MainActor
    func testSleepTimerCancelAndBounds() {
        let controller = SleepTimerController(startsTicker: false)

        controller.set(duration: 1)
        XCTAssertEqual(controller.configuredDuration, SleepTimerController.minimumDuration)

        controller.add(duration: SleepTimerController.maximumDuration * 2)
        XCTAssertLessThanOrEqual(controller.remainingDuration, SleepTimerController.maximumDuration)

        controller.cancel()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.configuredDuration)
        XCTAssertNil(controller.deadline)
    }

    @MainActor
    func testSleepTimerFormattingAndPresets() {
        XCTAssertEqual(SleepTimerController.presetMinutes, [15, 30, 45, 60, 90])
        XCTAssertEqual(SleepTimerController.clockString(for: 0), "0:00")
        XCTAssertEqual(SleepTimerController.clockString(for: 65), "1:05")
        XCTAssertEqual(SleepTimerController.clockString(for: 3661), "1:01:01")
    }

    func testPresetMapping() {
        XCTAssertEqual(Anime4KFrameProcessor.presetRawValue(for: .fast), "modeAFast")
        XCTAssertEqual(Anime4KFrameProcessor.presetRawValue(for: .balanced), "modeAAFast")
        XCTAssertEqual(Anime4KFrameProcessor.presetRawValue(for: .quality), "modeAAHQ")
    }

    func testFramePacingUsesSourceCadenceOrDisplayMaximum() {
        XCTAssertEqual(EnhancementFramePacing.preferredFramesPerSecond(
            sourceFrameRate: 23.976,
            maximumFramesPerSecond: 120,
            matchesSourceFrameRate: true
        ), 24)
        XCTAssertEqual(EnhancementFramePacing.preferredFramesPerSecond(
            sourceFrameRate: 59.94,
            maximumFramesPerSecond: 60,
            matchesSourceFrameRate: true
        ), 60)
        XCTAssertEqual(EnhancementFramePacing.preferredFramesPerSecond(
            sourceFrameRate: 24,
            maximumFramesPerSecond: 120,
            matchesSourceFrameRate: false
        ), 120)
    }

    func testFramePacingPreferencePersistence() {
        let key = "videoEnhancementMatchesSourceFrameRate"
        let defaults = UserDefaults.currentUserSuite
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(false, forKey: key)
        XCTAssertFalse(defaults.bool(forKey: key))
        defaults.set(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key))
    }

    func testLatestFrameQueueHoldsPresentedFrameAndOnlyDropsSupersededPendingFrames() {
        var queue = LatestFrameQueue<Int>()

        XCTAssertFalse(queue.enqueue(2))
        XCTAssertTrue(queue.enqueue(3))
        XCTAssertEqual(queue.dequeue(), 3)
        XCTAssertNil(queue.dequeue())
    }

    func testModePersistence() {
        let key = "videoEnhancementMode"
        let defaults = UserDefaults.currentUserSuite
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        for mode in VideoEnhancementMode.allCases {
            defaults.set(mode.rawValue, forKey: key)
            XCTAssertEqual(VideoEnhancementMode(rawValue: defaults.string(forKey: key) ?? ""), mode)
        }
    }

    func testEligibilityReasonsAndPrecedence() {
        var inputs = eligibleInputs()
        XCTAssertNil(VideoEnhancementEligibility.bypassReason(for: inputs))

        inputs.isHDR = true
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .highDynamicRange)
        inputs.isExternalPlaybackActive = true
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .externalPlayback)

        inputs = eligibleInputs()
        inputs.isLiveStream = true
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .liveStream)
        inputs = eligibleInputs()
        inputs.isPictureInPictureActive = true
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .pictureInPicture)
        inputs = eligibleInputs()
        inputs.retainsCriticalThermalBypass = true
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .criticalThermalState)
        inputs = eligibleInputs()
        inputs.isLowMemory = true
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .lowMemory)
        inputs = eligibleInputs()
        inputs.isPixelFormatSupported = false
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .unsupportedPixelFormat)
        inputs = eligibleInputs()
        inputs.sourceSize = CGSize(width: 2560, height: 1440)
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .sourceTooLarge)
        inputs = eligibleInputs()
        inputs.sourceSize = CGSize(width: 1080, height: 1920)
        XCTAssertNil(VideoEnhancementEligibility.bypassReason(for: inputs))
        inputs = eligibleInputs()
        inputs.targetSize = CGSize(width: 1280, height: 720)
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .sourceAtTargetSize)
        inputs = eligibleInputs()
        inputs.hasProcessor = false
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .metalUnavailable)
        inputs.mode = .off
        XCTAssertEqual(VideoEnhancementEligibility.bypassReason(for: inputs), .modeOff)
    }

    func testAdaptiveDowngradeUpgradeCooldownAndCap() {
        let frameDuration = 1.0 / 24
        var policy = EnhancementAdaptivePolicy()
        policy.reset(at: 0)

        XCTAssertEqual(policy.record(
            .init(timestamp: 5, processingDuration: frameDuration * 0.81, wasDropped: false),
            frameDuration: frameDuration,
            maximumLevel: .quality
        ), .fast)

        policy.reset(at: 0)
        for second in 1 ... 20 {
            _ = policy.record(
                .init(timestamp: Double(second), processingDuration: frameDuration * 0.3, wasDropped: false),
                frameDuration: frameDuration,
                maximumLevel: .quality
            )
        }
        XCTAssertEqual(policy.level, .quality)

        XCTAssertEqual(policy.record(
            .init(timestamp: 25, processingDuration: frameDuration, wasDropped: false),
            frameDuration: frameDuration,
            maximumLevel: .quality
        ), .balanced)
        XCTAssertEqual(policy.record(
            .init(timestamp: 26, processingDuration: frameDuration, wasDropped: false),
            frameDuration: frameDuration,
            maximumLevel: .quality
        ), .balanced)

        XCTAssertEqual(policy.record(
            .init(timestamp: 27, processingDuration: 0, wasDropped: true),
            frameDuration: frameDuration,
            maximumLevel: .quality
        ), .balanced)
        XCTAssertEqual(policy.record(
            .init(timestamp: 30, processingDuration: frameDuration, wasDropped: false),
            frameDuration: frameDuration,
            maximumLevel: .fast
        ), .fast)
    }

    func testAspectGeometryAndEvenOutputSize() {
        let fit = VideoEnhancementGeometry.aspectRect(
            sourceSize: CGSize(width: 1920, height: 1080),
            targetSize: CGSize(width: 2048, height: 1536),
            fill: false
        )
        XCTAssertEqual(fit.width, 2048, accuracy: 0.01)
        XCTAssertEqual(fit.height, 1152, accuracy: 0.01)
        XCTAssertEqual(fit.minY, 192, accuracy: 0.01)

        let fill = VideoEnhancementGeometry.aspectRect(
            sourceSize: CGSize(width: 1920, height: 1080),
            targetSize: CGSize(width: 2048, height: 1536),
            fill: true
        )
        XCTAssertEqual(fill.height, 1536, accuracy: 0.01)
        XCTAssertLessThan(fill.minX, 0)
        XCTAssertEqual(
            VideoEnhancementGeometry.outputPixelSize(for: CGSize(width: 2049, height: 1537)),
            CGSize(width: 2048, height: 1536)
        )
        XCTAssertEqual(
            VideoEnhancementGeometry.orientedSize(
                CGSize(width: 1920, height: 1080),
                rotationDegrees: 90
            ),
            CGSize(width: 1080, height: 1920)
        )
        XCTAssertEqual(VideoEnhancementGeometry.exifOrientation(rotationDegrees: 90), 6)
        XCTAssertEqual(VideoEnhancementGeometry.exifOrientation(rotationDegrees: -90), 8)
    }

    func testEnhancedSubtitleGeometryUsesLowerBlackBarAndFallsBackSafely() {
        let container = CGSize(width: 2048, height: 1536)
        let source = CGSize(width: 1920, height: 1080)
        let automatic = EnhancedSubtitleGeometry.layout(
            position: .automatic,
            sourceSize: source,
            containerSize: container,
            fontPointSize: 30
        )

        XCTAssertEqual(automatic.placement, .center)
        XCTAssertEqual(automatic.region.minY, 1344, accuracy: 0.01)
        XCTAssertEqual(automatic.region.height, 192, accuracy: 0.01)

        let insideVideo = EnhancedSubtitleGeometry.layout(
            position: .insideVideo,
            sourceSize: source,
            containerSize: container,
            fontPointSize: 30
        )
        XCTAssertEqual(insideVideo.placement, .bottom)
        XCTAssertEqual(insideVideo.region.minY, 192, accuracy: 0.01)
        XCTAssertEqual(insideVideo.region.height, 1152, accuracy: 0.01)

        let noBar = EnhancedSubtitleGeometry.layout(
            position: .lowerBlackBar,
            sourceSize: CGSize(width: 4, height: 3),
            containerSize: container,
            fontPointSize: 30
        )
        XCTAssertEqual(noBar.placement, .bottom)
        XCTAssertEqual(noBar.region, CGRect(origin: .zero, size: container))

        XCTAssertEqual(EnhancedSubtitleGeometry.fontPointSize(for: 9), 30)
        XCTAssertEqual(EnhancedSubtitleGeometry.fontPointSize(for: -1), 14)
        XCTAssertEqual(EnhancedSubtitleGeometry.fontPointSize(for: 99), 52)
    }

    func testSubtitleConfigurationMigratesStoredValuesWithoutPosition() throws {
        let encoded = try JSONEncoder().encode(SubtitleConfiguration.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "position")
        object.removeValue(forKey: "verticalOffset")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SubtitleConfiguration.self, from: legacyData)

        XCTAssertEqual(decoded.position, .automatic)
        XCTAssertEqual(decoded.verticalOffset, 0)
        XCTAssertEqual(decoded.size, SubtitleConfiguration.default.size)
    }

    func testLowPowerThermalCapAndCriticalRecovery() {
        XCTAssertEqual(
            VideoEnhancementDevicePolicy.maximumLevel(
                isLowPowerModeEnabled: true,
                thermalState: .nominal
            ),
            .fast
        )
        XCTAssertEqual(
            VideoEnhancementDevicePolicy.maximumLevel(
                isLowPowerModeEnabled: false,
                thermalState: .serious
            ),
            .fast
        )
        XCTAssertFalse(VideoEnhancementDevicePolicy.shouldReleaseCriticalBypass(
            thermalState: .serious,
            secondsBelowSerious: 60
        ))
        XCTAssertFalse(VideoEnhancementDevicePolicy.shouldReleaseCriticalBypass(
            thermalState: .nominal,
            secondsBelowSerious: 29.9
        ))
        XCTAssertTrue(VideoEnhancementDevicePolicy.shouldReleaseCriticalBypass(
            thermalState: .fair,
            secondsBelowSerious: 30
        ))
    }

    func testSessionInvalidationReturnsPassthrough() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let processor = try Anime4KFrameProcessor()
        processor.invalidate(sessionGeneration: 7)
        let input = try makePixelBuffer(width: 32, height: 24)
        let result = try processor.process(context(pixelBuffer: input, generation: 6))

        guard case .passthrough = result else {
            return XCTFail("A stale session must not publish an enhanced frame")
        }
    }

    func testFrameOutputSizeOrientationAndComparison() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let processor = try Anime4KFrameProcessor()
        processor.invalidate(sessionGeneration: 9)
        let input = try makePixelBuffer(width: 64, height: 48)
        let orientationKey = "SwiftfinTestOrientation" as CFString
        CVBufferSetAttachment(input, orientationKey, 6 as CFTypeRef, .shouldPropagate)

        let normal = try processor.process(context(pixelBuffer: input, generation: 9))
        let compared = try processor.process(context(pixelBuffer: input, generation: 9, comparison: true))

        for result in [normal, compared] {
            guard case let .replace(output) = result else {
                return XCTFail("A current eligible frame should be replaced")
            }
            XCTAssertEqual(CVPixelBufferGetWidth(output), 128)
            XCTAssertEqual(CVPixelBufferGetHeight(output), 96)
            let attachment = CVBufferCopyAttachment(output, orientationKey, nil) as? NSNumber
            XCTAssertEqual(attachment?.intValue, 6)
        }
    }

    private func eligibleInputs() -> VideoEnhancementEligibility.Inputs {
        .init(
            mode: .auto,
            hasProcessor: true,
            isLiveStream: false,
            isHDR: false,
            isExternalPlaybackActive: false,
            isPictureInPictureActive: false,
            retainsCriticalThermalBypass: false,
            isLowMemory: false,
            hasProcessingFailure: false,
            isPixelFormatSupported: true,
            sourceSize: CGSize(width: 1920, height: 1080),
            targetSize: CGSize(width: 2732, height: 2048)
        )
    }

    private func context(
        pixelBuffer: CVPixelBuffer,
        generation: Int64,
        comparison: Bool = false
    ) -> VideoFrameContext {
        .init(
            pixelBuffer: pixelBuffer,
            presentationTime: .zero,
            duration: CMTime(value: 1, timescale: 24),
            sourceFrameRate: 24,
            sourceSize: CGSize(width: 64, height: 48),
            targetSize: CGSize(width: 128, height: 96),
            sessionGeneration: generation,
            level: .fast,
            isComparisonEnabled: comparison
        )
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return pixelBuffer
    }
}

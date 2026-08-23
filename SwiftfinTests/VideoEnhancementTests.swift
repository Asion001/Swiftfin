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
    func testPresetMapping() {
        XCTAssertEqual(Anime4KFrameProcessor.presetRawValue(for: .fast), "modeAFast")
        XCTAssertEqual(Anime4KFrameProcessor.presetRawValue(for: .balanced), "modeAAFast")
        XCTAssertEqual(Anime4KFrameProcessor.presetRawValue(for: .quality), "modeAAHQ")
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

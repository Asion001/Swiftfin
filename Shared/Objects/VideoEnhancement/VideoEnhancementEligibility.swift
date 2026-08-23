//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import CoreGraphics
import Foundation

enum VideoEnhancementEligibility {
    struct Inputs {
        var mode: VideoEnhancementMode
        var hasProcessor: Bool
        var isLiveStream: Bool
        var isHDR: Bool
        var isExternalPlaybackActive: Bool
        var isPictureInPictureActive: Bool
        var retainsCriticalThermalBypass: Bool
        var isLowMemory: Bool
        var hasProcessingFailure: Bool
        var isPixelFormatSupported: Bool
        var sourceSize: CGSize
        var targetSize: CGSize
    }

    static func bypassReason(for inputs: Inputs) -> VideoEnhancementBypassReason? {
        if inputs.mode == .off {
            return .modeOff
        }
        if !inputs.hasProcessor {
            return .metalUnavailable
        }
        if inputs.isExternalPlaybackActive {
            return .externalPlayback
        }
        if inputs.isPictureInPictureActive {
            return .pictureInPicture
        }
        if inputs.retainsCriticalThermalBypass {
            return .criticalThermalState
        }
        if inputs.isLowMemory {
            return .lowMemory
        }
        if inputs.hasProcessingFailure {
            return .processingFailed
        }
        if inputs.isLiveStream {
            return .liveStream
        }
        if inputs.isHDR {
            return .highDynamicRange
        }
        if !inputs.isPixelFormatSupported {
            return .unsupportedPixelFormat
        }
        let sourceLongEdge = max(inputs.sourceSize.width, inputs.sourceSize.height)
        let sourceShortEdge = min(inputs.sourceSize.width, inputs.sourceSize.height)
        if sourceLongEdge > 1920 || sourceShortEdge > 1080 {
            return .sourceTooLarge
        }
        if inputs.targetSize != .zero,
           inputs.sourceSize != .zero,
           inputs.targetSize.width <= inputs.sourceSize.width,
           inputs.targetSize.height <= inputs.sourceSize.height
        {
            return .sourceAtTargetSize
        }
        return nil
    }
}

enum VideoEnhancementGeometry {
    static func normalizedRotation(_ degrees: Int) -> Int {
        let normalized = degrees % 360
        return normalized >= 0 ? normalized : normalized + 360
    }

    static func orientedSize(_ size: CGSize, rotationDegrees: Int) -> CGSize {
        switch normalizedRotation(rotationDegrees) {
        case 90, 270:
            CGSize(width: size.height, height: size.width)
        default:
            size
        }
    }

    static func exifOrientation(rotationDegrees: Int) -> Int32 {
        switch normalizedRotation(rotationDegrees) {
        case 90: 6
        case 180: 3
        case 270: 8
        default: 1
        }
    }

    static func outputPixelSize(for targetSize: CGSize) -> CGSize {
        CGSize(
            width: max(2, Int(targetSize.width.rounded(.down)) & ~1),
            height: max(2, Int(targetSize.height.rounded(.down)) & ~1)
        )
    }

    static func scaledOutputPixelSize(sourceSize: CGSize, targetSize: CGSize) -> CGSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0
        else { return outputPixelSize(for: sourceSize) }

        let scale = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        guard scale > 1 else { return outputPixelSize(for: sourceSize) }
        return outputPixelSize(for: CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        ))
    }

    static func visibleSourcePixelSize(
        sourceSize: CGSize,
        targetSize: CGSize,
        fill: Bool
    ) -> CGSize? {
        guard fill,
              sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0
        else { return nil }

        let sourceAspect = sourceSize.width / sourceSize.height
        let targetAspect = targetSize.width / targetSize.height
        var visibleSize = sourceSize

        if sourceAspect > targetAspect {
            visibleSize.width = sourceSize.height * targetAspect
        } else if sourceAspect < targetAspect {
            visibleSize.height = sourceSize.width / targetAspect
        }

        visibleSize = outputPixelSize(for: visibleSize)
        guard visibleSize.width < sourceSize.width || visibleSize.height < sourceSize.height else {
            return nil
        }
        return visibleSize
    }

    static func aspectRect(sourceSize: CGSize, targetSize: CGSize, fill: Bool) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0
        else { return .zero }

        let horizontalScale = targetSize.width / sourceSize.width
        let verticalScale = targetSize.height / sourceSize.height
        let scale = fill ? max(horizontalScale, verticalScale) : min(horizontalScale, verticalScale)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        return CGRect(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

enum VideoEnhancementDevicePolicy {
    static let criticalThermalRecoveryInterval: TimeInterval = 30

    static func maximumLevel(
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> VideoEnhancementLevel {
        if isLowPowerModeEnabled || isThermallyConstrained(thermalState) {
            .fast
        } else {
            .quality
        }
    }

    static func shouldReleaseCriticalBypass(
        thermalState: ProcessInfo.ThermalState,
        secondsBelowSerious: TimeInterval
    ) -> Bool {
        !isThermallyConstrained(thermalState) && secondsBelowSerious >= criticalThermalRecoveryInterval
    }

    static func isThermallyConstrained(_ state: ProcessInfo.ThermalState) -> Bool {
        switch state {
        case .serious, .critical:
            true
        case .nominal, .fair:
            false
        @unknown default:
            true
        }
    }
}
#endif

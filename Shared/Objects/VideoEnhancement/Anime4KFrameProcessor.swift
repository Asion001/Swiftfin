//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Anime4KMetal
import CoreVideo
import Foundation
import VideoToolbox

final class Anime4KFrameProcessor: VideoFrameProcessor, @unchecked Sendable {
    private let interpolator: Anime4KInterpolator
    private let lock = NSLock()
    private var cropPool: CVPixelBufferPool?
    private var cropPoolSize: CGSize?
    private var cropTransferSession: VTPixelTransferSession?
    private var needsDrain = false
    private var sessionGeneration: Int64 = 0

    init() throws {
        interpolator = try Anime4KInterpolator(configuration: .init(preset: .modeAFast))
    }

    func process(_ context: VideoFrameContext) throws -> VideoFrameResult {
        lock.lock()
        let isCurrentSession = context.sessionGeneration == sessionGeneration
        let shouldDrain = needsDrain
        if isCurrentSession {
            needsDrain = false
        }
        lock.unlock()

        guard isCurrentSession else { return .passthrough }
        if shouldDrain {
            resetResources()
        }

        let outputSize = VideoEnhancementGeometry.outputPixelSize(for: context.targetSize)
        let processingInput = cropToVisibleRegion(context) ?? context.pixelBuffer

        let packageOutput = try interpolator.enhance(
            pixelBuffer: processingInput,
            preset: Self.preset(for: context.level),
            maxOutputWidth: Int(outputSize.width),
            maxOutputHeight: Int(outputSize.height),
            abCompareEnabled: context.isComparisonEnabled
        )
        // Anime4KMetal already returns a pixel buffer from its own reusable pool.
        // Copying that result into a second Swiftfin-owned pool adds a full-size
        // VideoToolbox transfer to every frame and significantly increases memory
        // bandwidth and sustained thermal load on iPad.
        CVBufferPropagateAttachments(context.pixelBuffer, packageOutput)
        if context.visibleSourceSize != nil {
            // The source aperture describes the uncropped frame and must not be
            // applied to the smaller fill-mode output surface.
            CVBufferRemoveAttachment(packageOutput, kCVImageBufferCleanApertureKey)
            CVBufferRemoveAttachment(packageOutput, kCVImageBufferPreferredCleanApertureKey)
        }

        lock.lock()
        let shouldPublish = context.sessionGeneration == sessionGeneration
        lock.unlock()

        return shouldPublish ? .replace(packageOutput) : .passthrough
    }

    func drain() {
        lock.lock()
        needsDrain = true
        lock.unlock()
    }

    func invalidate(sessionGeneration: Int64) {
        lock.lock()
        self.sessionGeneration = sessionGeneration
        needsDrain = true
        lock.unlock()
    }

    static func preset(for level: VideoEnhancementLevel) -> Anime4KPreset {
        Anime4KPreset(rawValue: presetRawValue(for: level)) ?? .modeAFast
    }

    static func presetRawValue(for level: VideoEnhancementLevel) -> String {
        switch level {
        case .fast:
            "modeCFast"
        case .balanced:
            "modeAFast"
        case .quality:
            "modeAAFast"
        }
    }

    private func resetResources() {
        interpolator.reset()
        if let cropTransferSession {
            VTPixelTransferSessionInvalidate(cropTransferSession)
        }
        cropTransferSession = nil
        cropPool = nil
        cropPoolSize = nil
    }

    private func cropToVisibleRegion(_ context: VideoFrameContext) -> CVPixelBuffer? {
        guard let visibleSourceSize = context.visibleSourceSize else { return nil }
        let cropSize = VideoEnhancementGeometry.outputPixelSize(for: visibleSourceSize)

        if cropPoolSize != cropSize {
            cropPool = Self.makeCropPool(size: cropSize)
            cropPoolSize = cropSize
        }

        guard let cropPool else { return nil }
        var destination: CVPixelBuffer?
        let allocationAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 2] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            cropPool,
            allocationAttributes,
            &destination
        ) == kCVReturnSuccess, let destination else { return nil }

        if cropTransferSession == nil {
            var session: VTPixelTransferSession?
            guard VTPixelTransferSessionCreate(
                allocator: kCFAllocatorDefault,
                pixelTransferSessionOut: &session
            ) == noErr, let session else { return nil }
            guard VTSessionSetProperty(
                session,
                key: kVTPixelTransferPropertyKey_ScalingMode,
                value: kVTScalingMode_Trim
            ) == noErr else {
                VTPixelTransferSessionInvalidate(session)
                return nil
            }
            cropTransferSession = session
        }

        guard let cropTransferSession,
              VTPixelTransferSessionTransferImage(
                  cropTransferSession,
                  from: context.pixelBuffer,
                  to: destination
              ) == noErr
        else { return nil }

        return destination
    }

    private static func makeCropPool(size: CGSize) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var pool: CVPixelBufferPool?
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: 2] as CFDictionary
        guard CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes,
            attributes as CFDictionary,
            &pool
        ) == kCVReturnSuccess else { return nil }
        return pool
    }
}
#endif

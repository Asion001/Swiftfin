//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
import Anime4KMetal
import CoreImage
import CoreVideo
import Foundation
import VideoToolbox

final class Anime4KFrameProcessor: VideoFrameProcessor, @unchecked Sendable {
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let comparisonContext: CIContext
    private let interpolator: Anime4KInterpolator
    private let lock = NSLock()

    private var comparisonPool: CVPixelBufferPool?
    private var comparisonPoolSize: CGSize?
    private var cropPool: CVPixelBufferPool?
    private var cropPoolSize: CGSize?
    private var cropTransferSession: VTPixelTransferSession?
    private var needsDrain = false
    private var sessionGeneration: Int64 = 0

    init() throws {
        interpolator = try Anime4KInterpolator(configuration: .init(preset: .modeAFast))
        comparisonContext = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: colorSpace,
        ])
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

        // Anime4KMetal's built-in A/B path has different texture-coordinate
        // and color handling from its normal path. Always request a normal
        // enhanced frame, then compose both halves from upright CVPixelBuffers.
        let enhanced = try interpolator.enhance(
            pixelBuffer: processingInput,
            preset: Self.preset(for: context.level),
            maxOutputWidth: Int(outputSize.width),
            maxOutputHeight: Int(outputSize.height),
            abCompareEnabled: false
        )
        let output = context.isComparisonEnabled
            ? composeComparison(original: processingInput, enhanced: enhanced) ?? enhanced
            : enhanced

        CVBufferPropagateAttachments(context.pixelBuffer, output)
        if context.visibleSourceSize != nil {
            CVBufferRemoveAttachment(output, kCVImageBufferCleanApertureKey)
            CVBufferRemoveAttachment(output, kCVImageBufferPreferredCleanApertureKey)
        }

        lock.lock()
        let shouldPublish = context.sessionGeneration == sessionGeneration
        lock.unlock()
        return shouldPublish ? .replace(output) : .passthrough
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
        case .fast: "modeCFast"
        case .balanced: "modeAFast"
        case .quality: "modeAAFast"
        }
    }

    private func composeComparison(
        original: CVPixelBuffer,
        enhanced: CVPixelBuffer
    ) -> CVPixelBuffer? {
        let size = CGSize(
            width: CVPixelBufferGetWidth(enhanced),
            height: CVPixelBufferGetHeight(enhanced)
        )
        if comparisonPoolSize != size {
            comparisonPool = Self.makePool(size: size, minimumBufferCount: 2)
            comparisonPoolSize = size
        }
        guard let comparisonPool,
              let destination = Self.makePixelBuffer(from: comparisonPool, threshold: 2)
        else { return nil }

        let bounds = CGRect(origin: .zero, size: size)
        let originalImage = CIImage(
            cvPixelBuffer: original,
            options: [.colorSpace: colorSpace]
        ).transformed(by: CGAffineTransform(
            scaleX: size.width / CGFloat(CVPixelBufferGetWidth(original)),
            y: size.height / CGFloat(CVPixelBufferGetHeight(original))
        )).cropped(to: bounds)
        let enhancedImage = CIImage(
            cvPixelBuffer: enhanced,
            options: [.colorSpace: colorSpace]
        ).cropped(to: bounds)
        let enhancedHalf = CGRect(
            x: bounds.midX,
            y: bounds.minY,
            width: bounds.width / 2,
            height: bounds.height
        )
        let mask = CIImage(color: .white)
            .cropped(to: enhancedHalf)
            .composited(over: CIImage(color: .black).cropped(to: bounds))
        let comparison = enhancedImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: originalImage,
            kCIInputMaskImageKey: mask,
        ])
        comparisonContext.render(comparison, to: destination, bounds: bounds, colorSpace: colorSpace)
        return destination
    }

    private func resetResources() {
        interpolator.reset()
        if let cropTransferSession {
            VTPixelTransferSessionInvalidate(cropTransferSession)
        }
        cropTransferSession = nil
        cropPool = nil
        cropPoolSize = nil
        comparisonPool = nil
        comparisonPoolSize = nil
        comparisonContext.clearCaches()
    }

    private func cropToVisibleRegion(_ context: VideoFrameContext) -> CVPixelBuffer? {
        guard let visibleSourceSize = context.visibleSourceSize else { return nil }
        let cropSize = VideoEnhancementGeometry.outputPixelSize(for: visibleSourceSize)

        if cropPoolSize != cropSize {
            cropPool = Self.makePool(size: cropSize, minimumBufferCount: 2)
            cropPoolSize = cropSize
        }
        guard let cropPool,
              let destination = Self.makePixelBuffer(from: cropPool, threshold: 2)
        else { return nil }

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

    private static func makePixelBuffer(
        from pool: CVPixelBufferPool,
        threshold: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: threshold] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            pool,
            attributes,
            &pixelBuffer
        ) == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    private static func makePool(
        size: CGSize,
        minimumBufferCount: Int
    ) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        let poolAttributes = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: minimumBufferCount,
        ] as CFDictionary
        var pool: CVPixelBufferPool?
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

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
    private var needsDrain = false
    private var outputPool: CVPixelBufferPool?
    private var outputPoolDescriptor: OutputPoolDescriptor?
    private var transferSession: VTPixelTransferSession?
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

        let packageOutput = try interpolator.enhance(
            pixelBuffer: context.pixelBuffer,
            preset: Self.preset(for: context.level),
            maxOutputWidth: Int(outputSize.width),
            maxOutputHeight: Int(outputSize.height),
            abCompareEnabled: context.isComparisonEnabled
        )
        let output = copyIntoReusableOutputBuffer(packageOutput) ?? packageOutput
        CVBufferPropagateAttachments(context.pixelBuffer, output)

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
        case .fast:
            "modeAFast"
        case .balanced:
            "modeAAFast"
        case .quality:
            "modeAAHQ"
        }
    }

    private func copyIntoReusableOutputBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let descriptor = OutputPoolDescriptor(
            width: CVPixelBufferGetWidth(source),
            height: CVPixelBufferGetHeight(source),
            pixelFormat: CVPixelBufferGetPixelFormatType(source)
        )
        if outputPoolDescriptor != descriptor {
            outputPool = Self.makeOutputPool(descriptor: descriptor)
            outputPoolDescriptor = descriptor
        }

        guard let outputPool else { return nil }
        var destination: CVPixelBuffer?
        let allocationAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 3] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            outputPool,
            allocationAttributes,
            &destination
        ) == kCVReturnSuccess, let destination else { return nil }

        if transferSession == nil {
            VTPixelTransferSessionCreate(
                allocator: kCFAllocatorDefault,
                pixelTransferSessionOut: &transferSession
            )
        }
        guard let transferSession,
              VTPixelTransferSessionTransferImage(transferSession, from: source, to: destination) == noErr
        else { return nil }

        return destination
    }

    private func resetResources() {
        interpolator.reset()
        if let transferSession {
            VTPixelTransferSessionInvalidate(transferSession)
        }
        transferSession = nil
        outputPool = nil
        outputPoolDescriptor = nil
    }

    private static func makeOutputPool(descriptor: OutputPoolDescriptor) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: descriptor.width,
            kCVPixelBufferHeightKey as String: descriptor.height,
            kCVPixelBufferPixelFormatTypeKey as String: descriptor.pixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var pool: CVPixelBufferPool?
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary
        guard CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes,
            attributes as CFDictionary,
            &pool
        ) == kCVReturnSuccess else { return nil }
        return pool
    }

    private struct OutputPoolDescriptor: Equatable {
        let width: Int
        let height: Int
        let pixelFormat: OSType
    }
}
#endif

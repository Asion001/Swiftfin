//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import CoreImage
import CoreVideo
import Foundation
import Metal
#if !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
import MetalFX
import MetalPerformanceShaders

final class MetalFXFrameProcessor: VideoFrameProcessor, @unchecked Sendable {
    static let engineDisplayName = "MetalFX"

    enum ProcessorError: Error {
        case blitEncoderCreationFailed
        case commandBufferCreationFailed
        case commandBufferFailed
        case inputTextureCreationFailed
        case outputBufferCreationFailed
        case outputTextureCreationFailed
        case scalerCreationFailed
        case unsupportedDevice
    }

    private struct Configuration: Equatable {
        let inputWidth: Int
        let inputHeight: Int
        let outputWidth: Int
        let outputHeight: Int
    }

    private let ciContext: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let commandQueue: any MTLCommandQueue
    private let comparisonScaler: MPSImageBilinearScale
    private let device: any MTLDevice
    private let lock = NSLock()
    private let textureCache: CVMetalTextureCache

    private var configuration: Configuration?
    private var comparisonTexture: (any MTLTexture)?
    private var croppedInputTexture: (any MTLTexture)?
    private var needsDrain = false
    private var outputPool: CVPixelBufferPool?
    private var outputTexture: (any MTLTexture)?
    private var scaler: (any MTLFXSpatialScaler)?
    private var sessionGeneration: Int64 = 0

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              MTLFXSpatialScalerDescriptor.supportsDevice(device),
              let commandQueue = device.makeCommandQueue()
        else { throw ProcessorError.unsupportedDevice }

        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        ) == kCVReturnSuccess, let textureCache
        else { throw ProcessorError.inputTextureCreationFailed }

        self.device = device
        self.commandQueue = commandQueue
        self.comparisonScaler = MPSImageBilinearScale(device: device)
        self.textureCache = textureCache
        self.ciContext = CIContext(mtlDevice: device, options: [
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

        let sourceSize = context.visibleSourceSize ?? context.sourceSize
        let outputSize = VideoEnhancementGeometry.scaledOutputPixelSize(
            sourceSize: sourceSize,
            targetSize: context.targetSize
        )
        let requestedConfiguration = Configuration(
            inputWidth: Int(sourceSize.width),
            inputHeight: Int(sourceSize.height),
            outputWidth: Int(outputSize.width),
            outputHeight: Int(outputSize.height)
        )
        try configureIfNeeded(requestedConfiguration, needsCroppedInput: context.visibleSourceSize != nil)

        guard let scaler, let outputTexture else { throw ProcessorError.scalerCreationFailed }
        guard let destinationBuffer = makeOutputPixelBuffer(configuration: requestedConfiguration),
              let destinationTexture = makePixelBufferTexture(
                  destinationBuffer,
                  width: requestedConfiguration.outputWidth,
                  height: requestedConfiguration.outputHeight
              )
        else { throw ProcessorError.outputBufferCreationFailed }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ProcessorError.commandBufferCreationFailed
        }

        guard let sourceTexture = makePixelBufferTexture(
            context.pixelBuffer,
            width: CVPixelBufferGetWidth(context.pixelBuffer),
            height: CVPixelBufferGetHeight(context.pixelBuffer)
        ) else { throw ProcessorError.inputTextureCreationFailed }

        let inputTexture: any MTLTexture
        if context.visibleSourceSize != nil {
            guard let croppedInputTexture else { throw ProcessorError.inputTextureCreationFailed }
            try copyCenteredCrop(
                from: sourceTexture,
                to: croppedInputTexture,
                commandBuffer: commandBuffer
            )
            inputTexture = croppedInputTexture
        } else {
            inputTexture = sourceTexture
        }

        scaler.colorTexture = inputTexture
        scaler.inputContentWidth = requestedConfiguration.inputWidth
        scaler.inputContentHeight = requestedConfiguration.inputHeight
        scaler.outputTexture = outputTexture
        scaler.encode(commandBuffer: commandBuffer)

        let comparisonBaselineTexture: (any MTLTexture)?
        if context.isComparisonEnabled {
            let texture = try makeComparisonTextureIfNeeded(configuration: requestedConfiguration)
            comparisonScaler.encode(
                commandBuffer: commandBuffer,
                sourceTexture: inputTexture,
                destinationTexture: texture
            )
            comparisonBaselineTexture = texture
        } else {
            comparisonBaselineTexture = nil
        }

        guard let metalFXImage = CIImage(
            mtlTexture: outputTexture,
            options: [.colorSpace: colorSpace]
        ) else { throw ProcessorError.outputTextureCreationFailed }

        let enhancedImage = metalFXImage.applyingFilter(
            "CISharpenLuminance",
            parameters: [kCIInputSharpnessKey: Self.sharpness(for: context.level)]
        )

        let outputBounds = CGRect(
            x: 0,
            y: 0,
            width: requestedConfiguration.outputWidth,
            height: requestedConfiguration.outputHeight
        )
        let imageToRender: CIImage
        if context.isComparisonEnabled {
            guard let comparisonBaselineTexture,
                  let originalImage = CIImage(
                      mtlTexture: comparisonBaselineTexture,
                      options: [.colorSpace: colorSpace]
                  )
            else { throw ProcessorError.outputTextureCreationFailed }
            let black = CIImage(color: .black).cropped(to: outputBounds)
            let enhancedHalf = CGRect(
                x: outputBounds.midX,
                y: outputBounds.minY,
                width: outputBounds.width / 2,
                height: outputBounds.height
            )
            let mask = CIImage(color: .white)
                .cropped(to: enhancedHalf)
                .composited(over: black)
            imageToRender = enhancedImage.applyingFilter("CIBlendWithMask", parameters: [
                // Both scaling paths read the same raw Metal input texture.
                // The left uses a plain bilinear presentation baseline while
                // the right uses MetalFX plus the selected edge profile.
                kCIInputBackgroundImageKey: originalImage,
                kCIInputMaskImageKey: mask,
            ])
        } else {
            imageToRender = enhancedImage
        }

        ciContext.render(
            imageToRender,
            to: destinationTexture,
            commandBuffer: commandBuffer,
            bounds: outputBounds,
            colorSpace: colorSpace
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw ProcessorError.commandBufferFailed }

        CVBufferPropagateAttachments(context.pixelBuffer, destinationBuffer)
        if context.visibleSourceSize != nil {
            CVBufferRemoveAttachment(destinationBuffer, kCVImageBufferCleanApertureKey)
            CVBufferRemoveAttachment(destinationBuffer, kCVImageBufferPreferredCleanApertureKey)
        }

        lock.lock()
        let shouldPublish = context.sessionGeneration == sessionGeneration
        lock.unlock()
        return shouldPublish ? .replace(destinationBuffer) : .passthrough
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

    static func sharpness(for level: VideoEnhancementLevel) -> Float {
        switch level {
        case .fast: 0.25
        case .balanced: 0.55
        case .quality: 0.85
        }
    }

    private func configureIfNeeded(_ requested: Configuration, needsCroppedInput: Bool) throws {
        guard configuration != requested || (needsCroppedInput && croppedInputTexture == nil) else { return }

        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = requested.inputWidth
        descriptor.inputHeight = requested.inputHeight
        descriptor.outputWidth = requested.outputWidth
        descriptor.outputHeight = requested.outputHeight
        descriptor.colorTextureFormat = .bgra8Unorm_srgb
        descriptor.outputTextureFormat = .bgra8Unorm_srgb
        descriptor.colorProcessingMode = .perceptual

        guard let scaler = descriptor.makeSpatialScaler(device: device) else {
            throw ProcessorError.scalerCreationFailed
        }

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: requested.outputWidth,
            height: requested.outputHeight,
            mipmapped: false
        )
        outputDescriptor.storageMode = .private
        outputDescriptor.usage = scaler.outputTextureUsage.union([.shaderRead, .shaderWrite])
        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor) else {
            throw ProcessorError.outputTextureCreationFailed
        }

        let croppedInputTexture: (any MTLTexture)?
        if needsCroppedInput {
            let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb,
                width: requested.inputWidth,
                height: requested.inputHeight,
                mipmapped: false
            )
            inputDescriptor.storageMode = .private
            inputDescriptor.usage = scaler.colorTextureUsage.union([.shaderRead, .shaderWrite, .renderTarget])
            guard let texture = device.makeTexture(descriptor: inputDescriptor) else {
                throw ProcessorError.inputTextureCreationFailed
            }
            croppedInputTexture = texture
        } else {
            croppedInputTexture = nil
        }

        configuration = requested
        self.scaler = scaler
        self.outputTexture = outputTexture
        self.croppedInputTexture = croppedInputTexture
        comparisonTexture = nil
        outputPool = Self.makeOutputPool(configuration: requested)
    }

    private func makeOutputPixelBuffer(configuration: Configuration) -> CVPixelBuffer? {
        if outputPool == nil {
            outputPool = Self.makeOutputPool(configuration: configuration)
        }
        guard let outputPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let allocationAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 3] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            outputPool,
            allocationAttributes,
            &pixelBuffer
        ) == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    private func makePixelBufferTexture(
        _ pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> (any MTLTexture)? {
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm_srgb,
            width,
            height,
            0,
            &cvTexture
        ) == kCVReturnSuccess,
            let cvTexture,
            let texture = CVMetalTextureGetTexture(cvTexture)
        else { return nil }
        return texture
    }

    private func copyCenteredCrop(
        from sourceTexture: any MTLTexture,
        to destinationTexture: any MTLTexture,
        commandBuffer: any MTLCommandBuffer
    ) throws {
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw ProcessorError.blitEncoderCreationFailed
        }
        let sourceOrigin = MTLOrigin(
            x: max(0, (sourceTexture.width - destinationTexture.width) / 2),
            y: max(0, (sourceTexture.height - destinationTexture.height) / 2),
            z: 0
        )
        blitEncoder.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: sourceOrigin,
            sourceSize: MTLSize(
                width: destinationTexture.width,
                height: destinationTexture.height,
                depth: 1
            ),
            to: destinationTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()
    }

    private func makeComparisonTextureIfNeeded(
        configuration: Configuration
    ) throws -> any MTLTexture {
        if let comparisonTexture,
           comparisonTexture.width == configuration.outputWidth,
           comparisonTexture.height == configuration.outputHeight
        {
            return comparisonTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: configuration.outputWidth,
            height: configuration.outputHeight,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw ProcessorError.outputTextureCreationFailed
        }
        comparisonTexture = texture
        return texture
    }

    private func resetResources() {
        configuration = nil
        comparisonTexture = nil
        croppedInputTexture = nil
        outputPool = nil
        outputTexture = nil
        scaler = nil
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    private static func makeOutputPool(configuration: Configuration) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: configuration.outputWidth,
            kCVPixelBufferHeightKey as String: configuration.outputHeight,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary
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
#elseif targetEnvironment(macCatalyst)
// MetalFX is a native macOS framework and has no Mac Catalyst ABI. Catalyst
// uses Core Image's system Lanczos scaler so the Mac build keeps a fast,
// maintained Apple-GPU provider instead of linking an incompatible framework.
final class MetalFXFrameProcessor: VideoFrameProcessor, @unchecked Sendable {
    static let engineDisplayName = "Core Image"

    enum ProcessorError: Error {
        case outputBufferCreationFailed
        case unsupportedDevice
    }

    private struct OutputConfiguration: Equatable {
        let width: Int
        let height: Int
    }

    private let ciContext: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let lock = NSLock()
    private var needsDrain = false
    private var outputConfiguration: OutputConfiguration?
    private var outputPool: CVPixelBufferPool?
    private var sessionGeneration: Int64 = 0

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ProcessorError.unsupportedDevice
        }
        ciContext = CIContext(mtlDevice: device, options: [
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
            outputConfiguration = nil
            outputPool = nil
            ciContext.clearCaches()
        }

        let sourceSize = context.visibleSourceSize ?? context.sourceSize
        let outputSize = VideoEnhancementGeometry.scaledOutputPixelSize(
            sourceSize: sourceSize,
            targetSize: context.targetSize
        )
        let configuration = OutputConfiguration(
            width: Int(outputSize.width),
            height: Int(outputSize.height)
        )
        guard let destination = makeOutputPixelBuffer(configuration: configuration) else {
            throw ProcessorError.outputBufferCreationFailed
        }

        let outputBounds = CGRect(x: 0, y: 0, width: configuration.width, height: configuration.height)
        let original = scaledOriginalImage(context, outputBounds: outputBounds)
        let enhanced = original.applyingFilter(
            "CISharpenLuminance",
            parameters: [kCIInputSharpnessKey: Self.sharpness(for: context.level)]
        )
        let imageToRender: CIImage
        if context.isComparisonEnabled {
            let black = CIImage(color: .black).cropped(to: outputBounds)
            let enhancedHalf = CGRect(
                x: outputBounds.midX,
                y: outputBounds.minY,
                width: outputBounds.width / 2,
                height: outputBounds.height
            )
            let mask = CIImage(color: .white)
                .cropped(to: enhancedHalf)
                .composited(over: black)
            imageToRender = enhanced.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: original,
                kCIInputMaskImageKey: mask,
            ])
        } else {
            imageToRender = enhanced
        }

        ciContext.render(imageToRender, to: destination, bounds: outputBounds, colorSpace: colorSpace)
        CVBufferPropagateAttachments(context.pixelBuffer, destination)
        if context.visibleSourceSize != nil {
            CVBufferRemoveAttachment(destination, kCVImageBufferCleanApertureKey)
            CVBufferRemoveAttachment(destination, kCVImageBufferPreferredCleanApertureKey)
        }

        lock.lock()
        let shouldPublish = context.sessionGeneration == sessionGeneration
        lock.unlock()
        return shouldPublish ? .replace(destination) : .passthrough
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

    static func sharpness(for level: VideoEnhancementLevel) -> Float {
        switch level {
        case .fast: 0.25
        case .balanced: 0.55
        case .quality: 0.85
        }
    }

    private func makeOutputPixelBuffer(configuration: OutputConfiguration) -> CVPixelBuffer? {
        if outputConfiguration != configuration {
            outputConfiguration = configuration
            outputPool = Self.makeOutputPool(configuration: configuration)
        }
        guard let outputPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let allocationAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 3] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            outputPool,
            allocationAttributes,
            &pixelBuffer
        ) == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    private func scaledOriginalImage(_ context: VideoFrameContext, outputBounds: CGRect) -> CIImage {
        var original = CIImage(cvPixelBuffer: context.pixelBuffer)
        if let visibleSourceSize = context.visibleSourceSize {
            let cropRect = CGRect(
                x: original.extent.midX - visibleSourceSize.width / 2,
                y: original.extent.midY - visibleSourceSize.height / 2,
                width: visibleSourceSize.width,
                height: visibleSourceSize.height
            )
            original = original
                .cropped(to: cropRect)
                .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        }
        let scale = outputBounds.width / original.extent.width
        return original
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1,
            ])
            .cropped(to: outputBounds)
    }

    private static func makeOutputPool(configuration: OutputConfiguration) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: configuration.width,
            kCVPixelBufferHeightKey as String: configuration.height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary
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
#else
// MetalFX is intentionally absent from Apple's iOS Simulator SDK. Keep the
// app and deterministic policy tests buildable there while reporting the
// processor as unavailable; physical iPhone and iPad builds use the real path.
final class MetalFXFrameProcessor: VideoFrameProcessor, @unchecked Sendable {
    static let engineDisplayName = "MetalFX"

    enum ProcessorError: Error {
        case unsupportedDevice
    }

    init() throws {
        throw ProcessorError.unsupportedDevice
    }

    func process(_ context: VideoFrameContext) throws -> VideoFrameResult {
        .passthrough
    }

    func drain() {}

    func invalidate(sessionGeneration: Int64) {}

    static func sharpness(for level: VideoEnhancementLevel) -> Float {
        switch level {
        case .fast: 0.25
        case .balanced: 0.55
        case .quality: 0.85
        }
    }
}
#endif
#endif

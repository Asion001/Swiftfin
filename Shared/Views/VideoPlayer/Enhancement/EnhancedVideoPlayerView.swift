//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import AVFoundation
import AVKit
import CoreImage
import Defaults
import MetalKit
import SwiftUI

struct EnhancedVideoPlayerView: View {
    @ObservedObject
    var controller: VideoEnhancementController

    let avPlayerLayer: AVPlayerLayer

    var body: some View {
        ZStack(alignment: .topLeading) {
            EnhancedVideoSurface(
                controller: controller,
                avPlayerLayer: avPlayerLayer
            )

            EnhancedSubtitleOverlay(controller: controller)
                .allowsHitTesting(false)

            if controller.showsPerformanceHUD {
                VideoEnhancementPerformanceHUD(controller: controller)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct EnhancedSubtitleOverlay: View {
    @ObservedObject
    var controller: VideoEnhancementController

    @Default(.VideoPlayer.Subtitle.configuration)
    private var configuration

    var body: some View {
        GeometryReader { proxy in
            if let subtitleText = controller.subtitleText,
               controller.sourceSize != .zero,
               controller.usesCustomSubtitleRendering
            {
                let fontSize = EnhancedSubtitleGeometry.fontPointSize(for: configuration.size)
                let sourceSize = VideoEnhancementGeometry.orientedSize(
                    controller.sourceSize,
                    rotationDegrees: controller.sourceRotationDegrees
                )
                let layout = EnhancedSubtitleGeometry.layout(
                    position: configuration.position,
                    sourceSize: sourceSize,
                    containerSize: proxy.size,
                    fontPointSize: fontSize,
                    isAspectFilled: controller.isAspectFilled
                )
                let alignment: Alignment = layout.placement == .bottom ? .bottom : .center

                Text(subtitleText)
                    .font(.custom(configuration.fontName, size: fontSize))
                    .fontWeight(.semibold)
                    .foregroundStyle(configuration.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 16)
                    .padding(.bottom, layout.placement == .bottom ? 18 : 0)
                    .frame(
                        width: layout.region.width,
                        height: layout.region.height,
                        alignment: alignment
                    )
                    .position(x: layout.region.midX, y: layout.region.midY)
                    .offset(y: CGFloat(configuration.verticalOffset))
            }
        }
        .ignoresSafeArea()
    }
}

private struct EnhancedVideoSurface: UIViewRepresentable {
    @ObservedObject
    var controller: VideoEnhancementController

    let avPlayerLayer: AVPlayerLayer

    func makeUIView(context: Context) -> EnhancedPlayerUIView {
        EnhancedPlayerUIView(controller: controller, avPlayerLayer: avPlayerLayer)
    }

    func updateUIView(_ uiView: EnhancedPlayerUIView, context: Context) {
        uiView.updatePresentation()
    }
}

private final class PresentedPixelBufferLease: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

@MainActor
private final class EnhancedPlayerUIView: UIView, MTKViewDelegate {
    private let avPlayerLayer: AVPlayerLayer
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext?
    private let controller: VideoEnhancementController
    private let metalView: MTKView
    private var lastRenderedDrawableSize = CGSize.zero
    private var lastRenderedFrameRevision: UInt64?
    private var lastRenderedIsAspectFilled = false
    private var lastRenderedRotationDegrees = 0
    private var pictureInPictureController: AVPictureInPictureController?
    private let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(controller: VideoEnhancementController, avPlayerLayer: AVPlayerLayer) {
        self.controller = controller
        self.avPlayerLayer = avPlayerLayer

        let device = MTLCreateSystemDefaultDevice()
        self.metalView = MTKView(frame: .zero, device: device)
        self.commandQueue = device?.makeCommandQueue()
        self.context = device.map { CIContext(mtlDevice: $0) }

        super.init(frame: .zero)

        backgroundColor = .black
        layer.addSublayer(avPlayerLayer)

        if AVPictureInPictureController.isPictureInPictureSupported(),
           let pictureInPictureController = AVPictureInPictureController(playerLayer: avPlayerLayer)
        {
            pictureInPictureController.delegate = self
            pictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = true
            self.pictureInPictureController = pictureInPictureController
        }

        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.backgroundColor = .black
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.delegate = self
        metalView.enableSetNeedsDisplay = false
        metalView.framebufferOnly = false
        metalView.isPaused = false
        metalView.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        addSubview(metalView)

        updatePresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avPlayerLayer.frame = bounds
        metalView.frame = bounds
    }

    func updatePresentation() {
        let usesNativeLayer = controller.isUsingNativePlaybackLayer
        avPlayerLayer.isHidden = !usesNativeLayer
        metalView.isHidden = usesNativeLayer
        metalView.isPaused = controller.isPictureInPictureActive
        avPlayerLayer.videoGravity = controller.isAspectFilled ? .resizeAspectFill : .resizeAspect
        metalView.preferredFramesPerSecond = EnhancementFramePacing.preferredFramesPerSecond(
            sourceFrameRate: controller.sourceFrameRate,
            maximumFramesPerSecond: UIScreen.main.maximumFramesPerSecond,
            matchesSourceFrameRate: controller.matchesSourceFrameRate
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        controller.renderTick(hostTime: CACurrentMediaTime(), targetSize: view.drawableSize)
        updatePresentation()

        guard !controller.isUsingNativePlaybackLayer,
              let pixelBuffer = controller.latestPixelBuffer
        else { return }

        let presentationChanged = lastRenderedFrameRevision != controller.frameRevision ||
            lastRenderedDrawableSize != view.drawableSize ||
            lastRenderedIsAspectFilled != controller.isAspectFilled ||
            lastRenderedRotationDegrees != controller.sourceRotationDegrees
        guard presentationChanged else { return }

        guard let commandQueue, let context else {
            controller.rendererDidFail()
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            controller.rendererDidFail()
            return
        }

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor
        else { return }

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = view.clearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)?.endEncoding()

        let targetBounds = CGRect(origin: .zero, size: view.drawableSize)
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(
            forExifOrientation: VideoEnhancementGeometry.exifOrientation(
                rotationDegrees: controller.sourceRotationDegrees
            )
        )
        let displayRect = VideoEnhancementGeometry.aspectRect(
            sourceSize: sourceImage.extent.size,
            targetSize: targetBounds.size,
            fill: controller.isAspectFilled
        )
        let scale = displayRect.width / sourceImage.extent.width
        let scaledImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translation = CGAffineTransform(
            translationX: displayRect.midX - scaledImage.extent.midX,
            y: displayRect.midY - scaledImage.extent.midY
        )
        let displayImage = scaledImage.transformed(by: translation)

        context.render(
            displayImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: targetBounds,
            colorSpace: sRGBColorSpace
        )
        // Keep the package-owned pooled buffer alive until Metal has finished
        // sampling it. The Anime4K pool can allocate another surface instead of
        // reusing the one currently being presented.
        let pixelBufferLease = PresentedPixelBufferLease(pixelBuffer)
        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(pixelBufferLease) {}
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        controller.rendererDidPresentFrame()

        lastRenderedFrameRevision = controller.frameRevision
        lastRenderedDrawableSize = view.drawableSize
        lastRenderedIsAspectFilled = controller.isAspectFilled
        lastRenderedRotationDegrees = controller.sourceRotationDegrees
    }
}

@MainActor
extension EnhancedPlayerUIView: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        controller.isPictureInPictureActive = true
        updatePresentation()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        controller.isPictureInPictureActive = false
        updatePresentation()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// swiftlint:disable hard_coded_display_string
private struct VideoEnhancementPerformanceHUD: View {
    @ObservedObject
    var controller: VideoEnhancementController

    private var sourceResolution: String {
        "\(Int(controller.sourceSize.width))×\(Int(controller.sourceSize.height))"
    }

    private var outputResolution: String {
        guard controller.outputSize != .zero else { return "—" }
        return "\(Int(controller.outputSize.width))×\(Int(controller.outputSize.height))"
    }

    private var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Anime4K \(controller.requestedMode.displayTitle) → \(controller.activeLevel.displayTitle)")
            Text("\(sourceResolution) → \(outputResolution)")
            Text(String(
                format: "source %.1f fps · renderer %.1f fps · %@",
                controller.sourceFrameRate,
                controller.displayFrameRate,
                controller.matchesSourceFrameRate ? "source-gated" : "display max"
            ))
            Text(String(
                format: "GPU %.2f ms avg · %.2f ms p95",
                controller.averageProcessingTime * 1000,
                controller.percentile95ProcessingTime * 1000
            ))
            Text(String(
                format: "drops %.1f%% / 3s (%d) · %d total · %d player",
                controller.recentEnhancedDropRate * 100,
                controller.recentEnhancedDroppedFrames,
                controller.enhancedDroppedFrames,
                controller.avPlayerDroppedFrames
            ))
            Text("thermal \(thermalState) · low power \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")

            if let bypassReason = controller.bypassReason {
                Text(bypassReason.displayTitle)
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}
// swiftlint:enable hard_coded_display_string
#endif

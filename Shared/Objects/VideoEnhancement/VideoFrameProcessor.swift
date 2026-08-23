//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import CoreMedia
import CoreVideo

struct VideoFrameContext: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let duration: CMTime
    let sourceFrameRate: Double
    let sourceSize: CGSize
    let targetSize: CGSize
    let sessionGeneration: Int64
    let level: VideoEnhancementLevel
    let isComparisonEnabled: Bool
}

enum VideoFrameResult: @unchecked Sendable {
    case passthrough
    case replace(CVPixelBuffer)
}

protocol VideoFrameProcessor: AnyObject, Sendable {
    func process(_ context: VideoFrameContext) throws -> VideoFrameResult
    func drain()
    func invalidate(sessionGeneration: Int64)
}
#endif

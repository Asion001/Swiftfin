//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

// TODO: feature implementations
//       - PiP
// TODO: Chromecast proxy

/// The proxy for top-down communication to an
/// underlying media player
protocol MediaPlayerProxy: ObservableObject, MediaPlayerObserver {

    var isBuffering: PublishedBox<Bool> { get }

    func play()
    func pause()
    func stop()

    func jumpForward(_ seconds: Duration)
    func jumpBackward(_ seconds: Duration)
    func setRate(_ rate: Float)
    func setSeconds(_ seconds: Duration)
}

@MainActor
protocol VideoMediaPlayerProxy: MediaPlayerProxy, MediaPlayerAudioTrackConfigurable, MediaPlayerSubtitleTrackConfigurable {

    associatedtype VideoPlayerBody: View

    var videoSize: PublishedBox<CGSize> { get }
    var droppedFrames: PublishedBox<Int> { get }
    var corruptedFrames: PublishedBox<Int> { get }

    // TODO: remove when container view handles aspect fill
    func setAspectFill(_ aspectFill: Bool)

    @ViewBuilder
    @MainActor
    var videoPlayerBody: Self.VideoPlayerBody { get }
}

protocol MediaPlayerAudioTrackConfigurable {
    func setAudioStream(_ stream: MediaStream)
}

protocol MediaPlayerSubtitleTrackConfigurable {
    func setSubtitleStream(_ stream: MediaStream)
}

protocol MediaPlayerOffsetConfigurable {
    func setAudioOffset(_ seconds: Duration)
    func setSubtitleOffset(_ seconds: Duration)
}

protocol MediaPlayerSubtitleConfigurable {
    func setSubtitleConfiguration(_ configuration: SubtitleConfiguration)
}

/// A proxy whose picture can be scaled continuously rather than only switched
/// between fitting and filling the surface.
///
/// Filling is all or nothing, which throws away a lot of a 2.39:1 film on a
/// 16:9 screen. A scale lets the picture be taken part of the way there.
@MainActor
protocol MediaPlayerZoomConfigurable {

    /// `1` fits the picture inside the surface.
    func setZoomScale(_ scale: CGFloat)

    /// The scale at which the picture exactly fills the surface, or `nil` while
    /// the video's dimensions are still unknown.
    var fillZoomScale: CGFloat? { get }
}

@MainActor
protocol MediaPlayerScreenshotCapturing {
    func takeScreenshot(includeSubtitles: Bool) async throws -> URL
}

@MainActor
protocol MediaPlayerTrackRebuildPolicy {
    var requiresTrackRebuild: Bool { get }
}

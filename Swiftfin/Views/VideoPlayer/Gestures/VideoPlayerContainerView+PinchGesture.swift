//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension VideoPlayer.UIVideoPlayerContainerViewController {

    /// How close to a detent counts as being on it.
    ///
    /// Wide enough that fit and fill can be landed on deliberately, narrow
    /// enough that a scale chosen between them is not dragged off it.
    private var zoomDetentTolerance: CGFloat {
        0.04
    }

    func handlePinchGesture(
        scale: CGFloat,
        velocity: CGFloat,
        state: UIGestureRecognizer.State
    ) {
        guard checkGestureLock() else { return }
        guard !containerState.isPresentingSupplement else { return }

        let action = Defaults[.VideoPlayer.Gesture.pinchGesture]

        switch action {
        case .none: ()
        case .aspectFill:
            guard let zoomProxy = containerState.manager?.proxy as? any MediaPlayerZoomConfigurable else {
                guard state != .ended else { return }

                if scale > 1, !containerState.isAspectFilled {
                    containerState.isAspectFilled = true
                } else if scale < 1, containerState.isAspectFilled {
                    containerState.isAspectFilled = false
                }
                return
            }

            handleZoom(scale: scale, state: state, proxy: zoomProxy)
        }
    }

    /// Scales the picture continuously between fitting and filling the surface,
    /// and past filling, rather than snapping between the two ends.
    ///
    /// A 2.39:1 film loses roughly a third of its width to a fill, so the useful
    /// setting for it is usually somewhere in between. Both ends still attract,
    /// so the two conventional ones remain easy to land on exactly.
    private func handleZoom(
        scale: CGFloat,
        state: UIGestureRecognizer.State,
        proxy: any MediaPlayerZoomConfigurable
    ) {
        let fill = proxy.fillZoomScale ?? 1

        /// Past filling is allowed, but only so far: beyond this the picture is
        /// mostly off screen and the gesture cannot be undone by feel.
        let maximum = max(fill, 1) * 2

        if state == .began {
            zoomScaleAtGestureStart = containerState.isAspectFilled ? fill : containerState.zoomScale
        }

        let start = zoomScaleAtGestureStart ?? containerState.zoomScale
        let proposed = clamp(start * scale, min: 1, max: maximum)
        let resolved = snapping(proposed, to: [1, fill])

        if state == .ended || state == .cancelled || state == .failed {
            zoomScaleAtGestureStart = nil
        }

        guard resolved != containerState.zoomScale else { return }

        /// The scale is what reaches the player; `isAspectFilled` only records
        /// whether the picture happens to be filling, so the aspect-fill button
        /// and the subtitle placement still agree with what is on screen.
        containerState.zoomScale = resolved
        containerState.isAspectFilled = abs(resolved - fill) < zoomDetentTolerance && fill > 1
    }

    /// Pulls a scale onto a detent when it is already close to one.
    private func snapping(_ scale: CGFloat, to detents: [CGFloat]) -> CGFloat {
        for detent in detents where abs(scale - detent) < zoomDetentTolerance {
            return detent
        }

        return scale
    }
}

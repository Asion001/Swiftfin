//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import SwiftUI

/// The control left over the video after starting a comparison.
///
/// Comparing an upscaler from inside the settings sheet does not work: the
/// sheet covers the picture being judged and darkens what is left of it. This
/// stays out of the way instead — one switch for the two pictures, and a way
/// out — so the only thing changing on screen is the thing being compared.
struct UpscalerCompareBar: View {

    @ObservedObject
    var controller: MPVUpscalerController

    var body: some View {
        VStack(spacing: 6) {
            controls

            /// Said plainly rather than left to be inferred from two identical
            /// pictures, which is indistinguishable from a broken comparison.
            if !controller.isSelectionEffective {
                Text(VideoEnhancementStrings.compareIneffective)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                controller.toggleComparedSide()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: controller.isComparingBaseline ? "sparkles.slash" : "sparkles")
                    Text(controller.activeDescription)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 20)

            Button(VideoEnhancementStrings.stopComparing) {
                controller.stopComparing()
            }
            .font(.subheadline)
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.75), in: .capsule)
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .animation(.linear(duration: 0.15), value: controller.isComparingBaseline)
    }
}
#endif

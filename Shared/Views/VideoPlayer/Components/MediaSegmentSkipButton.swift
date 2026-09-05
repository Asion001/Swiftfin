//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer {

    /// The button offered while playback is inside a segment the user has asked
    /// to be prompted about.
    ///
    /// It is deliberately independent of the overlay: an intro is skipped
    /// without first summoning the rest of the controls.
    ///
    /// Its own padding and alignment are applied here rather than by the caller
    /// so that an idle button is an `EmptyView` and takes no room in the stack
    /// holding it — a modifier applied outside would give it a layout slot, and
    /// with it a stack's spacing, for the whole of every item with no segments.
    struct MediaSegmentSkipButton: View {

        #if os(iOS)
        @Environment(\.safeAreaInsets)
        private var safeAreaInsets
        #endif

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState

        @ObservedObject
        private var observer: MediaSegmentsObserver

        #if os(tvOS)
        @FocusState
        private var isFocused: Bool
        #endif

        init(observer: MediaSegmentsObserver) {
            self.observer = observer
        }

        /// A panel covers the button, and a locked screen is a request to not be
        /// offered anything at all.
        private var isPresentable: Bool {
            !containerState.isPresentingSupplement && !containerState.isGestureLocked
        }

        // MARK: body

        var body: some View {
            if let segment = observer.promptedSegment, isPresentable {
                button(for: segment)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    #if os(iOS)
                    .padding(.leading, safeAreaInsets.leading)
                    .padding(.trailing, safeAreaInsets.trailing + EdgeInsets.edgePadding)
                    .padding(.bottom, EdgeInsets.edgePadding / 2)
                    #endif
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .animation(.bouncy(duration: 0.3), value: segment)
            }
        }

        @ViewBuilder
        private func button(for segment: MediaSegment) -> some View {
            Button {
                containerState.timer.poke()
                observer.act(on: segment)
            } label: {
                Label(
                    observer.promptTitle(for: segment),
                    systemImage: observer.promptSystemImage(for: segment)
                )
                #if os(tvOS)
                .font(.callout.weight(.semibold))
                #else
                    .font(.subheadline.weight(.semibold))
                #endif
                .labelStyle(.titleAndIcon)
            }
            #if os(tvOS)
            .buttonStyle(.borderedProminent)
                .focused($isFocused)
                .onAppear {
                    // The overlay may already be up, in which case the button is
                    // immediately usable. If it is not, the first press raises the
                    // overlay and the second one lands here.
                    guard !containerState.isScrubbing, !containerState.isPresentingSupplement else { return }
                    isFocused = true
                }
            #else
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(.black.opacity(0.6))
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        }
                }
                .contentShape(Capsule())
            #endif
        }
    }
}

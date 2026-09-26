//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

struct NavigationBarFilterDrawerModifier: ViewModifier {

    @FocusState
    private var focusedFilter: FilterTrack.FocusTarget?

    @ObservedObject
    var viewModel: FilterViewModel

    let types: [ItemFilterType]

    @ViewBuilder
    private var drawer: some View {
        ScrollView(.horizontal) {
            HStack {
                FilterTrack(viewModel: viewModel, types: types, focus: $focusedFilter)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.bottom, 5)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        /// The drawer is the content of a `safeAreaBar`, which hands its bar the
        /// container's rect *and* the container's safe area, expecting the bar to
        /// lay itself out within the inset. SwiftUI does place this scroll view
        /// correctly — but UIKit then adjusts the scroll content by that same
        /// inset again, pushing the filters a navigation bar's height below the
        /// bar they belong to.
        .introspect(.scrollView, on: .iOS(.v18...)) { scrollView in
            scrollView.contentInsetAdjustmentBehavior = .never
        }
    }

    func body(content: Content) -> some View {
        if types.isEmpty {
            content
        } else {
            if #available(iOS 26, *) {
                // The bar floats above scroll content and adds its height to
                // the safe area rather than taking a slice out of the layout.
                // Content that draws through its vertical safe area — paging
                // libraries do — has to reserve that height itself, which is
                // what `IsSafeAreaBarApplied` signals.
                content
                    .safeAreaBar(edge: .top, spacing: 0) {
                        drawer
                    }
                    .preference(key: IsSafeAreaBarApplied.self, value: true)
            } else {
                NavigationBarDrawerView {
                    drawer
                        .ignoresSafeArea()
                } content: {
                    content
                }
                .ignoresSafeArea()
            }
        }
    }
}

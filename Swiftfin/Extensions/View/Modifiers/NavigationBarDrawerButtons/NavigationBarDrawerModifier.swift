//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct NavigationBarFilterDrawerModifier: ViewModifier {

    @ObservedObject
    var viewModel: FilterViewModel

    let types: [ItemFilterType]

    @ViewBuilder
    private var drawer: some View {
        NavigationBarFilterDrawer(
            viewModel: viewModel,
            types: types
        )
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

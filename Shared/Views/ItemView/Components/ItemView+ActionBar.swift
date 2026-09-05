//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct ActionBar: View {

        @FocusState
        private var focusedButton: String?

        @ObservedObject
        var provider: ItemContentGroupProvider

        private var buttonConfiguration = ItemActionButtons.Configuration()

        let alignment: HorizontalAlignment
        let usesMusicControlRow: Bool

        init(
            provider: ItemContentGroupProvider,
            alignment: HorizontalAlignment = .center,
            usesMusicControlRow: Bool = false
        ) {
            self.provider = provider
            self.alignment = alignment
            self.usesMusicControlRow = usesMusicControlRow
        }

        @ViewBuilder
        private var playButton: some View {
            if provider.item.presentPlayButton {
                PlayButton(provider: provider)
                    .coordinatedFocus(ItemView.Component.play, selection: $focusedButton)
                    .frame(height: UIDevice.isTV ? 75 : 44)
            }
        }

        var body: some View {
            let (visible, overflow, menu) = buttonConfiguration.resolvedButtons(for: provider)
            let defaultFocusedButton = provider.item.presentPlayButton ?
                ItemView.Component.play : visible.first?.id ?? ItemView.Component.menu

            let actions = ItemActionButtons(
                provider: provider,
                buttons: visible,
                overflowButtons: overflow,
                menuButtons: menu,
                focusedButton: $focusedButton
            )

            Group {
                if usesMusicControlRow {
                    HStack(spacing: 12) {
                        actions
                        Spacer(minLength: 16)
                        playButton
                            .frame(maxWidth: 220)
                    }
                } else {
                    VStack(alignment: alignment, spacing: UIDevice.isTV ? 24 : 8) {
                        playButton
                        actions
                    }
                }
            }
            .focusSection()
            .defaultFocus(
                $focusedButton,
                defaultFocusedButton,
                priority: .userInitiated
            )
            .multilineTextAlignment(.center)
        }
    }
}

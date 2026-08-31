//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    struct RegularSimpleHeaderContentGroup: ContentGroup {

        let id: String = ItemView.Component.header
        let provider: ItemContentGroupProvider

        func body(with viewModel: Empty) -> Body {
            Body(provider: provider)
        }

        struct Body: View {

            @ObservedObject
            var provider: ItemContentGroupProvider

            @StoredValue(.User.itemViewAttributes)
            private var attributes

            private var posterDisplayType: PosterDisplayType {
                switch provider.item.type {
                case .audio, .musicAlbum:
                    .square
                case .musicArtist, .person:
                    .portrait
                default:
                    .landscape
                }
            }

            private var usesMusicControlRow: Bool {
                [
                    .audio,
                    .musicAlbum,
                    .musicArtist,
                    .musicGenre,
                    .playlist,
                ].contains(provider.item.type)
            }

            @ViewBuilder
            private var controls: some View {
                if usesMusicControlRow {
                    HStack(spacing: 12) {
                        ItemView.ActionButtonHStack(provider: provider)

                        Spacer(minLength: 16)

                        if provider.item.presentPlayButton {
                            PlayButton(provider: provider)
                                .frame(maxWidth: 220)
                        }
                    }
                    .frame(maxWidth: 520)
                } else {
                    VStack(alignment: .leading, spacing: UIDevice.isTV ? 25 : 5) {
                        if provider.item.presentPlayButton {
                            PlayButton(provider: provider)
                        }

                        ItemView.ActionButtonHStack(provider: provider)
                    }
                    .frame(maxWidth: UIDevice.isTV ? 450 : 300, alignment: .leading)
                }
            }

            @ViewBuilder
            private var title: some View {
                VStack(alignment: .leading, spacing: 5) {
                    if let parentID = provider.item.parentRootID, let parentTitle = provider.item.parentTitle {
                        ParentButton(title: parentTitle, id: parentID)
                    }

                    Text(provider.item.displayTitle)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    MetadataHStack(item: provider.item)
                }
            }

            var body: some View {
                ImageContentColumnsLayout(
                    idealContentWidth: 600,
                    imageAspectRatio: posterDisplayType == .landscape ? 1.77 : 1,
                    imageColumnFraction: posterDisplayType == .landscape ? 0.5 : 0.33,
                    spacing: EdgeInsets.edgePadding
                ) {
                    PosterImage(
                        item: provider.item,
                        type: posterDisplayType,
                        size: .medium,
                        contentMode: .fit
                    )
                    #if os(tvOS)
                    .posterBorder()
                    .posterCornerRadius(posterDisplayType)
                    .subtleShadow()
                    #endif
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .trailing
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        title

                        ItemView.Description(item: provider.item)

                        controls

                        ItemView.AttributesHStack(
                            attributes: attributes,
                            item: provider.item,
                            selectedMediaSource: provider.mediaPlayerItemProvider?.mediaSource,
                            alignment: .leading
                        )
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusSection()
                .edgePadding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

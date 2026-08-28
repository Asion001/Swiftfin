//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// swiftlint:disable hard_coded_display_string
enum SubtitlePosition: String, CaseIterable, Displayable, Storable {
    case automatic
    case insideVideo
    case lowerBlackBar
    case screenBottom

    var displayTitle: String {
        switch self {
        case .automatic:
            String(enhancedLocalized: "subtitle.position.automatic", defaultValue: "Automatic")
        case .insideVideo:
            String(enhancedLocalized: "subtitle.position.video", defaultValue: "Inside video")
        case .lowerBlackBar:
            String(enhancedLocalized: "subtitle.position.black-bar", defaultValue: "Bottom black bar")
        case .screenBottom:
            String(enhancedLocalized: "subtitle.position.screen", defaultValue: "Bottom of screen")
        }
    }
}

// swiftlint:enable hard_coded_display_string

struct SubtitleConfiguration: Hashable, Storable, WithDefaultValue {

    var color: Color
    var fontName: String
    var position: SubtitlePosition
    var size: Int
    var verticalOffset: Int

    /// Note: "Noto Sans CJK SC" should be our default as it successfully handles English and non-Romantic
    static let `default`: SubtitleConfiguration = .init(
        color: .white,
        fontName: "Noto Sans CJK SC",
        position: .automatic,
        size: 9,
        verticalOffset: 0
    )

    private enum CodingKeys: String, CodingKey {
        case color
        case fontName
        case position
        case size
        case verticalOffset
    }

    init(
        color: Color,
        fontName: String,
        position: SubtitlePosition = .automatic,
        size: Int,
        verticalOffset: Int = 0
    ) {
        self.color = color
        self.fontName = fontName
        self.position = position
        self.size = size
        self.verticalOffset = verticalOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try Color(hex: container.decode(String.self, forKey: .color))
        self.fontName = try container.decode(String.self, forKey: .fontName)
        self.position = try container.decodeIfPresent(SubtitlePosition.self, forKey: .position) ?? .automatic
        self.size = try container.decode(Int.self, forKey: .size)
        self.verticalOffset = try container.decodeIfPresent(Int.self, forKey: .verticalOffset) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color.hexString, forKey: .color)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        try container.encode(verticalOffset, forKey: .verticalOffset)
    }
}

#if os(iOS)
enum EnhancedSubtitleGeometry {
    enum VerticalPlacement: Equatable {
        case center
        case bottom
    }

    struct Layout: Equatable {
        let region: CGRect
        let placement: VerticalPlacement
    }

    static func fontPointSize(for configuredSize: Int) -> CGFloat {
        CGFloat(12 + min(20, max(1, configuredSize)) * 2)
    }

    static func layout(
        position: SubtitlePosition,
        sourceSize: CGSize,
        containerSize: CGSize,
        fontPointSize: CGFloat,
        isAspectFilled: Bool = false
    ) -> Layout {
        let container = CGRect(origin: .zero, size: containerSize)
        let video = isAspectFilled
            ? container
            : VideoEnhancementGeometry.aspectRect(
                sourceSize: sourceSize,
                targetSize: containerSize,
                fill: false
            )
        let lowerBar = CGRect(
            x: max(0, video.minX),
            y: min(container.height, video.maxY),
            width: min(container.width, video.width),
            height: max(0, container.height - video.maxY)
        )
        let barCanFitText = lowerBar.height >= fontPointSize * 1.5

        switch position {
        case .automatic where barCanFitText,
             .lowerBlackBar where barCanFitText:
            return Layout(region: lowerBar, placement: .center)
        case .screenBottom:
            return Layout(region: container, placement: .bottom)
        case .automatic, .insideVideo, .lowerBlackBar:
            return Layout(region: video.intersection(container), placement: .bottom)
        }
    }
}
#endif

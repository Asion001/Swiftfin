//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// TODO: add audio/subtitle offset

enum VideoPlayerActionButton: String, CaseIterable, Displayable, Equatable, Identifiable, Storable, SystemImageable {

    case aspectFill
    case audio
    case autoPlay
    #if os(iOS)
    case enhancement
    case gestureLock
    #endif
    case playbackSpeed
    case playbackSettings
    case playNextItem
    case playPreviousItem
    case subtitles

    var displayTitle: String {
        switch self {
        case .aspectFill:
            L10n.aspectFill
        case .audio:
            L10n.audio
        case .autoPlay:
            L10n.autoPlay
        #if os(iOS)
        case .enhancement:
            VideoEnhancementStrings.title
        case .gestureLock:
            L10n.gestureLock
        #endif
        case .playbackSpeed:
            L10n.playbackSpeed
        case .playbackSettings:
            L10n.playback
        case .playNextItem:
            L10n.playNextItem
        case .playPreviousItem:
            L10n.playPreviousItem
        case .subtitles:
            L10n.subtitles
        }
    }

    var id: String {
        rawValue
    }

    #if os(tvOS)
    var systemImage: String {
        switch self {
        case .aspectFill: "arrow.up.left.and.arrow.down.right"
        case .audio: "speaker.wave.2"
        case .autoPlay: "play.fill"
        case .playbackSpeed: "speedometer"
        case .playbackSettings: "tv"
        case .playNextItem: "forward.end.fill"
        case .playPreviousItem: "backward.end.fill"
        case .subtitles: "captions.bubble.fill"
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .aspectFill: "arrow.down.right.and.arrow.up.left"
        case .audio: "speaker.wave.2"
        case .autoPlay: "stop.fill"
        case .subtitles: "captions.bubble"
        default:
            systemImage
        }
    }
    #else
    var systemImage: String {
        let usesLiquidGlassSymbols = if #available(iOS 26.0, *) {
            true
        } else {
            false
        }

        return switch self {
        case .aspectFill: "arrow.up.left.and.arrow.down.right"
        case .audio: "speaker.wave.2.fill"
        case .autoPlay: usesLiquidGlassSymbols ? "play.fill" : "play.circle.fill"
        case .enhancement: "sparkles"
        case .gestureLock: usesLiquidGlassSymbols ? "lock.fill" : "lock.circle.fill"
        case .playbackSpeed: "speedometer"
        case .playbackSettings: usesLiquidGlassSymbols ? "tv" : "tv.circle.fill"
        case .playNextItem: usesLiquidGlassSymbols ? "forward.end.fill" : "forward.end.circle.fill"
        case .playPreviousItem: usesLiquidGlassSymbols ? "backward.end.fill" : "backward.end.circle.fill"
        case .subtitles: "captions.bubble.fill"
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .aspectFill: "arrow.down.right.and.arrow.up.left"
        case .audio: "speaker.wave.2"
        case .autoPlay:
            if #available(iOS 26.0, *) {
                "stop"
            } else {
                "stop.circle"
            }
        case .gestureLock: "lock.open.fill"
        case .enhancement: systemImage
        case .subtitles: "captions.bubble"
        default:
            systemImage
        }
    }
    #endif

    static let defaultBarActionButtons: [VideoPlayerActionButton] = [
        .aspectFill,
        .autoPlay,
        .playPreviousItem,
        .playNextItem,
    ]

    static var defaultMenuActionButtons: [VideoPlayerActionButton] {
        #if os(iOS)
        [
            .audio,
            .subtitles,
            .enhancement,
            .playbackSpeed,
            .playbackSettings,
        ]
        #else
        [
            .audio,
            .subtitles,
            .playbackSpeed,
            .playbackSettings,
        ]
        #endif
    }
}

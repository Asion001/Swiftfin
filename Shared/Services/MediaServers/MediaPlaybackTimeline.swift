//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public extension MediaServerDomain {

    struct MediaTime: Hashable, Codable, Sendable, Comparable {
        public let seconds: Double

        public init(seconds: Double) throws {
            guard seconds.isFinite, seconds >= 0 else { throw ValidationError.invalidTime }
            self.seconds = seconds
        }

        public init(from decoder: any Decoder) throws {
            try self.init(seconds: decoder.singleValueContainer().decode(Double.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(seconds)
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.seconds < rhs.seconds
        }
    }

    struct PlaybackTimeline: Hashable, Codable, Sendable {
        /// source position = player position + offset, supplied by the provider plan.
        public let sourceOffsetSeconds: Double
        public let sourceDuration: MediaTime?

        public init(sourceOffsetSeconds: Double, sourceDuration: MediaTime?) throws {
            guard sourceOffsetSeconds.isFinite else { throw ValidationError.invalidOffset }
            self.sourceOffsetSeconds = sourceOffsetSeconds
            self.sourceDuration = sourceDuration
        }

        private enum CodingKeys: CodingKey {
            case sourceOffsetSeconds
            case sourceDuration
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                sourceOffsetSeconds: values.decode(Double.self, forKey: .sourceOffsetSeconds),
                sourceDuration: values.decodeIfPresent(MediaTime.self, forKey: .sourceDuration)
            )
        }

        public func sourcePosition(for playerPosition: MediaTime) throws -> MediaTime {
            try MediaTime(seconds: playerPosition.seconds + sourceOffsetSeconds)
        }

        public func playerPosition(for sourcePosition: MediaTime) throws -> MediaTime {
            try MediaTime(seconds: sourcePosition.seconds - sourceOffsetSeconds)
        }
    }

    struct SeekWindow: Hashable, Codable, Sendable {
        public let start: MediaTime
        public let end: MediaTime

        public init(start: MediaTime, end: MediaTime) throws {
            guard start <= end else { throw ValidationError.invalidSeekWindow }
            self.start = start
            self.end = end
        }

        private enum CodingKeys: CodingKey {
            case start
            case end
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(start: values.decode(MediaTime.self, forKey: .start), end: values.decode(MediaTime.self, forKey: .end))
        }
    }

    enum SeekPolicy: Hashable, Codable, Sendable {
        case disabled
        case local
        /// A provider-declared closed source window. Outside it, obtain a new plan.
        case localWindow(SeekWindow)
        /// Includes open-ended remux plans: engine duration is not evidence of seekability.
        case reanchor

        public func destination(for sourcePosition: MediaTime, timeline: PlaybackTimeline) -> SeekDestination {
            if let duration = timeline.sourceDuration, sourcePosition > duration {
                return .unavailable
            }

            switch self {
            case .disabled:
                return .unavailable
            case .reanchor:
                return .reanchor(sourcePosition: sourcePosition)
            case let .localWindow(window) where sourcePosition < window.start || sourcePosition > window.end:
                return .reanchor(sourcePosition: sourcePosition)
            case .local, .localWindow:
                guard let position = try? timeline.playerPosition(for: sourcePosition) else {
                    return .reanchor(sourcePosition: sourcePosition)
                }
                return .local(playerPosition: position)
            }
        }
    }

    enum SeekDestination: Equatable, Sendable {
        case unavailable
        case local(playerPosition: MediaTime)
        case reanchor(sourcePosition: MediaTime)
    }
}

//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public extension MediaServerDomain {

    /// A handle into the owning adapter's authenticated resources, never a serialized signed URL.
    struct ResourceHandle: Hashable, Sendable {
        public let id: UUID
        public let session: SessionScope

        public init(id: UUID = UUID(), session: SessionScope) {
            self.id = id
            self.session = session
        }
    }

    struct PlaybackTrack: Equatable, Sendable {
        public enum Kind: Sendable {
            case audio
            case subtitle
        }

        public enum Delivery: Sendable {
            case embedded
            case external(ResourceHandle)
            case burnInOnly
            case unavailable
        }

        public let id: TrackID
        /// Provider ordinal, not the index in a filtered UI list.
        public let ordinal: Int?
        public let kind: Kind
        public let delivery: Delivery
        public let title: String?
        public let language: String?

        public init(id: TrackID, ordinal: Int?, kind: Kind, delivery: Delivery, title: String?, language: String?) {
            self.id = id
            self.ordinal = ordinal
            self.kind = kind
            self.delivery = delivery
            self.title = title
            self.language = language
        }
    }

    struct EnginePlaybackPlan: Equatable, Sendable {
        public enum Delivery: Sendable {
            case direct
            case remux
            case transcode
        }

        public let resource: ResourceHandle
        public let delivery: Delivery
        public let timeline: PlaybackTimeline
        public let startPosition: MediaTime
        public let seekPolicy: SeekPolicy
        public let tracks: [PlaybackTrack]

        public init(
            resource: ResourceHandle,
            delivery: Delivery,
            timeline: PlaybackTimeline,
            startPosition: MediaTime,
            seekPolicy: SeekPolicy,
            tracks: [PlaybackTrack]
        ) {
            self.resource = resource
            self.delivery = delivery
            self.timeline = timeline
            self.startPosition = startPosition
            self.seekPolicy = seekPolicy
            self.tracks = tracks
        }
    }

    enum PlaybackDecision: Equatable, Sendable {
        case playable(EnginePlaybackPlan)
        case terminal(code: String, message: String?)
        case providerFailure(code: String, retryable: Bool)
    }

    /// Used by a coordinator confined to one actor/queue. It does not perform network delivery.
    struct PlaybackOwnership: Sendable {
        public let session: SessionScope
        public private(set) var generation: UUID
        public private(set) var isStopped = false

        public init(session: SessionScope, generation: UUID = UUID()) {
            self.session = session
            self.generation = generation
        }

        public func accepts(session: SessionScope, generation: UUID) -> Bool {
            !isStopped && self.session == session && self.generation == generation
        }

        /// Capture the returned value before sending a plan request.
        public mutating func beginReplan() -> UUID? {
            guard !isStopped else { return nil }
            generation = UUID()
            return generation
        }

        /// The winner owns the final progress/stop sequence. Repeated close/end signals lose.
        public mutating func claimStop() -> Bool {
            guard !isStopped else { return false }
            isStopped = true
            return true
        }
    }
}

extension MediaServerDomain.PlaybackTrack.Delivery: Equatable {}

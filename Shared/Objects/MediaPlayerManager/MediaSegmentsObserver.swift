//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI

/// Fetches the segments the server has marked on the playing item and acts on
/// them as playback reaches each one: offering a skip button, or performing the
/// skip outright, according to the user's per-type setting.
///
/// One of these belongs to each `MediaPlayerItem`, so its state is discarded
/// along with the item it describes.
@MainActor
final class MediaSegmentsObserver: ViewModel, MediaPlayerObserver {

    /// Every segment the player understands for the current item, ordered by
    /// start. Empty until the request returns, and on servers older than 10.10
    /// or without a segment provider.
    @Published
    private(set) var segments: [MediaSegment] = []

    /// The segment currently being offered to the user, if any.
    @Published
    private(set) var promptedSegment: MediaSegment?

    weak var manager: MediaPlayerManager? {
        didSet {
            guard let manager else { return }
            setup(with: manager)
        }
    }

    /// Segments already skipped automatically.
    ///
    /// Kept for the life of the item so that seeking back into an intro plays it
    /// instead of being thrown forward again.
    private var autoSkippedSegmentIDs: Set<MediaSegment.ID> = []

    /// Segments the user has skipped by hand, cleared once playback is no longer
    /// inside them. Without this the button reappears for the frames between the
    /// seek and the player reporting its new position.
    private var dismissedSegmentIDs: Set<MediaSegment.ID> = []

    private let itemID: String?
    private let isSupported: Bool
    private var segmentsTask: Task<Void, Never>?

    init(baseItem: BaseItemDto) {
        self.itemID = baseItem.id

        // Live streams have no fixed timeline to mark up, and the audio player
        // has nowhere to show a button.
        self.isSupported = baseItem.id != nil
            && baseItem.type != .audio
            && !baseItem.isLiveStream

        super.init()
    }

    // MARK: - Skipping

    /// Seeks past `segment`, resuming playback if it was paused.
    func skip(_ segment: MediaSegment) {
        guard let manager else { return }

        let destination = MediaSegmentResolver.destination(
            for: segment,
            runtime: manager.item.runtime
        )

        dismissedSegmentIDs.insert(segment.id)
        promptedSegment = nil

        logger.debug(
            "Skipping media segment",
            metadata: [
                "type": .stringConvertible(segment.type.rawValue),
                "to": .stringConvertible(destination.seconds),
            ]
        )

        manager.proxy?.setSeconds(destination)
        manager.setPlaybackRequestStatus(status: .playing)
    }

    // MARK: - Observation

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []

        manager.secondsBox
            .$value
            .sink { [weak self] seconds in
                self?.update(for: seconds)
            }
            .store(in: &cancellables)

        fetchSegments()
    }

    private func update(for seconds: Duration) {
        dismissedSegmentIDs = dismissedSegmentIDs.filter { id in
            segments.first { $0.id == id }?.contains(seconds) ?? false
        }

        let segment = MediaSegmentResolver.segment(at: seconds, in: segments) { segment in
            action(for: segment) != .none
        }

        guard let segment, !dismissedSegmentIDs.contains(segment.id) else {
            promptedSegment = nil
            return
        }

        switch action(for: segment) {
        case .none:
            promptedSegment = nil
        case .ask:
            if promptedSegment != segment {
                promptedSegment = segment
            }
        case .skip:
            promptedSegment = nil

            guard !autoSkippedSegmentIDs.contains(segment.id) else { return }
            autoSkippedSegmentIDs.insert(segment.id)

            skip(segment)
        }
    }

    private func action(for segment: MediaSegment) -> MediaSegmentAction {
        Defaults[.VideoPlayer.MediaSegments.action(for: segment.type)]
    }

    // MARK: - Fetching

    private func fetchSegments() {
        guard isSupported, let itemID else { return }

        segmentsTask?.cancel()
        segmentsTask = Task { [weak self] in
            guard let self else { return }

            do {
                let request = Paths.getItemSegments(
                    itemID: itemID,
                    includeSegmentTypes: MediaSegmentType.skippableCases
                )
                let response = try await send(request)

                guard !Task.isCancelled else { return }

                segments = MediaSegmentResolver.segments(from: response.value.items ?? [])

                // Playback may already be inside a segment: the request is made
                // as the item starts, and a resumed item starts anywhere.
                if let manager {
                    update(for: manager.seconds)
                }

                logger.debug(
                    "Retrieved media segments",
                    metadata: [
                        "itemID": .stringConvertible(itemID),
                        "count": .stringConvertible(segments.count),
                    ]
                )
            } catch is CancellationError {
                // Playback moved on before the segments arrived.
            } catch {
                // A server without a segment provider, or older than the
                // endpoint, is expected rather than exceptional.
                logger.debug(
                    "Unable to retrieve media segments",
                    metadata: [
                        "itemID": .stringConvertible(itemID),
                        "error": .stringConvertible(error.localizedDescription),
                    ]
                )
            }
        }
    }
}

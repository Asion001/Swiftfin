//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Combine
import Foundation
import UIKit

@MainActor
final class SleepTimerController: ObservableObject {
    static let presetMinutes = [15, 30, 45, 60, 90]
    static let minimumDuration: TimeInterval = 60
    static let maximumDuration: TimeInterval = 24 * 60 * 60

    /// How the timer decides when to finish.
    enum Mode: Equatable {
        /// Pause after a wall-clock duration.
        case duration
        /// Let the current item play to its end, then stop instead of
        /// advancing to the next one.
        case endOfItem
    }

    @Published
    private(set) var configuredDuration: TimeInterval?
    @Published
    private(set) var deadline: Date?
    @Published
    private(set) var expirationCount = 0
    @Published
    private(set) var remainingDuration: TimeInterval = 0
    @Published
    private(set) var mode: Mode = .duration

    /// Which mode the timer was in when it last finished.
    ///
    /// Finishing resets `mode`, so observers reacting to `expirationCount`
    /// would otherwise always see `.duration` and report the wrong thing.
    @Published
    private(set) var lastFinishedMode: Mode = .duration

    var isActive: Bool {
        deadline != nil || mode == .endOfItem
    }

    var formattedRemainingDuration: String {
        Self.clockString(for: remainingDuration)
    }

    private weak var manager: MediaPlayerManager?
    private var cancellables = Set<AnyCancellable>()
    private var didReleaseIdleTimer = false
    private var ticker: Task<Void, Never>?

    private let expirationHandler: (() -> Void)?
    private let now: () -> Date
    private let startsTicker: Bool

    init(
        now: @escaping () -> Date = Date.init,
        startsTicker: Bool = true,
        expirationHandler: (() -> Void)? = nil
    ) {
        self.now = now
        self.startsTicker = startsTicker
        self.expirationHandler = expirationHandler
    }

    func attach(to manager: MediaPlayerManager) {
        guard self.manager !== manager else { return }

        cancellables.removeAll()
        self.manager = manager

        manager.$state
            .sink { [weak self] state in
                guard state == .stopped else { return }

                if self?.mode == .endOfItem {
                    self?.finishEndOfItem()
                } else {
                    self?.cancel()
                }
            }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] status in
                guard status == .playing else { return }
                self?.restoreIdleTimerIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
            .sink { [weak self] _ in
                self?.reconcile()
            }
            .store(in: &cancellables)
    }

    /// Stops playback when the current item ends.
    ///
    /// This is not a wall-clock deadline: seeking, pausing and rate changes all
    /// move the real end, so the manager is asked to stop when the item
    /// finishes and the countdown shown is just the item's remaining runtime.
    func setEndOfItem() {
        ticker?.cancel()
        ticker = nil
        configuredDuration = nil
        deadline = nil
        mode = .endOfItem
        manager?.stopsAtEndOfCurrentItem = true
        refreshRemainingItemDuration()
        startTickerIfNeeded()
    }

    func set(duration: TimeInterval) {
        mode = .duration
        manager?.stopsAtEndOfCurrentItem = false

        let normalizedDuration = min(
            Self.maximumDuration,
            max(Self.minimumDuration, duration.rounded())
        )

        configuredDuration = normalizedDuration
        deadline = now().addingTimeInterval(normalizedDuration)
        remainingDuration = normalizedDuration
        startTickerIfNeeded()
    }

    func add(duration: TimeInterval) {
        guard duration > 0, mode == .duration else { return }

        let currentDate = now()
        let baseDate = max(deadline ?? currentDate, currentDate)
        let newDeadline = min(
            baseDate.addingTimeInterval(duration),
            currentDate.addingTimeInterval(Self.maximumDuration)
        )

        deadline = newDeadline
        remainingDuration = max(0, newDeadline.timeIntervalSince(currentDate))
        configuredDuration = min(
            Self.maximumDuration,
            (configuredDuration ?? 0) + duration
        )
        startTickerIfNeeded()
    }

    func cancel() {
        ticker?.cancel()
        ticker = nil
        configuredDuration = nil
        deadline = nil
        remainingDuration = 0
        mode = .duration
        manager?.stopsAtEndOfCurrentItem = false
    }

    func invalidate() {
        cancel()
        cancellables.removeAll()
        manager = nil
    }

    func reconcile(at currentDate: Date? = nil) {
        if mode == .endOfItem {
            refreshRemainingItemDuration()
            return
        }

        guard let deadline else { return }

        let remaining = deadline.timeIntervalSince(currentDate ?? now())
        guard remaining <= 0 else {
            remainingDuration = remaining
            return
        }

        expire()
    }

    nonisolated static func clockString(for duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(duration)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Reports the end-of-item timer as finished.
    ///
    /// The manager stops playback itself in this mode, so the controller never
    /// reaches `expire()`; without this the timer would end with no feedback.
    private func finishEndOfItem() {
        cancel()
        lastFinishedMode = .endOfItem
        expirationCount += 1
    }

    /// Mirrors the item's remaining runtime so the menu can show a countdown.
    ///
    /// The manager owns the actual stop, so this is display only and never
    /// expires the timer itself.
    private func refreshRemainingItemDuration() {
        guard let manager, let runtime = manager.item.runtime else {
            remainingDuration = 0
            return
        }

        remainingDuration = max(0, (runtime - manager.seconds).seconds)
    }

    private func startTickerIfNeeded() {
        guard startsTicker, ticker == nil else { return }

        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.reconcile()
            }
        }
    }

    private func expire() {
        ticker?.cancel()
        ticker = nil
        configuredDuration = nil
        deadline = nil
        remainingDuration = 0
        lastFinishedMode = .duration
        expirationCount += 1

        if let expirationHandler {
            expirationHandler()
            return
        }

        manager?.setPlaybackRequestStatus(status: .paused)
        didReleaseIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func restoreIdleTimerIfNeeded() {
        guard didReleaseIdleTimer else { return }
        didReleaseIdleTimer = false
        UIApplication.shared.isIdleTimerDisabled = true
    }
}

enum SleepTimerStrings {
    static let title = String(localized: "sleep-timer.title", defaultValue: "Sleep timer")
    static let custom = String(localized: "sleep-timer.custom", defaultValue: "Custom duration")
    static let start = String(localized: "sleep-timer.start", defaultValue: "Start timer")
    static let cancel = String(localized: "sleep-timer.cancel", defaultValue: "Cancel timer")
    static let addFifteenMinutes = String(
        localized: "sleep-timer.add-fifteen",
        defaultValue: "Add 15 minutes"
    )
    static let paused = String(
        localized: "sleep-timer.paused",
        defaultValue: "Sleep timer finished. Playback paused."
    )
    static let finished = String(
        localized: "sleep-timer.finished",
        defaultValue: "Sleep timer finished."
    )
    static let finishEpisode = String(
        localized: "sleep-timer.finish-episode",
        defaultValue: "End of this episode"
    )
    static let finishMovie = String(
        localized: "sleep-timer.finish-movie",
        defaultValue: "End of this movie"
    )
    static let finishItem = String(
        localized: "sleep-timer.finish-item",
        defaultValue: "End of this item"
    )
    static let endOfItemExplanation = String(
        localized: "sleep-timer.end-of-item-explanation",
        defaultValue: "Playback stops when this finishes instead of continuing to the next one."
    )

    static func endsIn(_ value: String) -> String {
        String(localized: "sleep-timer.ends-in", defaultValue: "Ends in \(value)")
    }

    static let energyExplanation = String(
        localized: "sleep-timer.background-explanation",
        defaultValue: "The timer uses the actual clock, continues during background audio and buffering, and pauses playback when it finishes."
    )

    static func minutes(_ value: Int) -> String {
        String(localized: "sleep-timer.minutes", defaultValue: "\(value) minutes")
    }

    static func remaining(_ value: String) -> String {
        String(localized: "sleep-timer.remaining", defaultValue: "Pauses in \(value)")
    }
}
#endif

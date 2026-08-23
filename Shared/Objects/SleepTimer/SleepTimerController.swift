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

    @Published
    private(set) var configuredDuration: TimeInterval?
    @Published
    private(set) var deadline: Date?
    @Published
    private(set) var expirationCount = 0
    @Published
    private(set) var remainingDuration: TimeInterval = 0

    var isActive: Bool {
        deadline != nil
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
                self?.cancel()
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

    func set(duration: TimeInterval) {
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
        guard duration > 0 else { return }

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
    }

    func invalidate() {
        cancel()
        cancellables.removeAll()
        manager = nil
    }

    func reconcile(at currentDate: Date? = nil) {
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

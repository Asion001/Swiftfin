//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)

import FactoryKit
import JellyfinAPI
import SwiftUI

struct MediaDownloadButton: View {

    enum Style {
        case icon
        case itemAction
        case actionBar
    }

    @Injected(\.downloadManager)
    private var downloadManager

    @Router
    private var router

    @StateObject
    private var task: DownloadTask

    let style: Style

    init(item: BaseItemDto, style: Style = .icon) {
        let existingTask = Container.shared.downloadManager().task(for: item)
        self._task = StateObject(wrappedValue: existingTask ?? DownloadTask(item: item))
        self.style = style
    }

    private var isComplete: Bool {
        if case .complete = task.state {
            return true
        }
        return false
    }

    private var systemImage: String {
        switch task.state {
        case .cancelled, .ready:
            "arrow.down.circle"
        case .complete:
            "checkmark.circle.fill"
        case .downloading:
            "arrow.down.circle.fill"
        case .error:
            "exclamationmark.arrow.circlepath"
        }
    }

    var body: some View {
        Button(action: performAction) {
            switch style {
            case .icon:
                iconLabel
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            case .actionBar:
                iconLabel
            case .itemAction:
                iconLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .backport
                    .glassEffect(
                        .regular.selection(
                            tint: isComplete ? .green.opacity(0.35) : .gray.opacity(0.3),
                            foregroundColor: .primary
                        ),
                        in: RoundedRectangle(cornerRadius: 10, style: .circular)
                    )
            }
        }
        .buttonStyle(BasicHoverButtonStyle())
        .foregroundStyle(.primary, .secondary)
        .accessibilityLabel(isComplete ? L10n.downloads : L10n.download)
        .contextMenu {
            if isComplete {
                Button(L10n.delete, systemImage: "trash", role: .destructive) {
                    task.deleteRootFolder()
                    task.state = .ready
                    downloadManager.remove(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private var iconLabel: some View {
        if case let .downloading(progress) = task.state {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
        } else {
            Label(L10n.download, systemImage: systemImage)
        }
    }

    private func performAction() {
        switch task.state {
        case .cancelled, .ready:
            downloadManager.download(task: task)
        case .error:
            downloadManager.remove(task: task)
            downloadManager.download(task: task)
        case .complete, .downloading:
            router.route(to: .downloadTask(downloadTask: task))
        }
    }
}

#endif

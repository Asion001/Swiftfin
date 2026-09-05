//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

struct ContentGroupView<Provider: ContentGroupProvider>: View {

    @Environment(\.musicPlayerBottomInset)
    private var musicPlayerBottomInset

    @Router
    private var router

    @State
    private var contentGroupOptions: ContentGroupParentOption = .init()

    #if os(iOS)
    private var musicPlaybackParent: BaseItemDto? {
        guard let provider = viewModel.provider as? ItemTypeContentGroupProvider,
              provider.itemTypes.contains(.audio),
              let genre = provider.environment.filters.genres.first
        else {
            return nil
        }

        return BaseItemDto(
            name: genre.displayTitle,
            type: .musicGenre
        )
    }
    #endif

    @StateObject
    private var focusCoordinator: FocusCoordinator = .init()
    @StateObject
    private var viewModel: ContentGroupViewModel<Provider>

    @TabItemSelected
    private var tabItemSelected

    init(provider: Provider) {
        _viewModel = StateObject(wrappedValue: ContentGroupViewModel(provider: provider))
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    ContentGroupVStack(groups: viewModel.groups)
                        .edgePadding(contentGroupOptions.contains(.ignoreSafeAreaTop) ? .bottom : .vertical)
                        .padding(.bottom, musicPlayerBottomInset)
                        .onPreferenceChange(ContentGroupCustomizationKey.self) { value in
                            contentGroupOptions = value
                        }
                }
            }
            .trackingFrame(for: .scrollView)
            .ignoresSafeArea(
                edges: contentGroupOptions.contains(.ignoreSafeAreaTop) ? [.horizontal, .top] : .horizontal
            )
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.background.refresh()
            }
            .onReceive(tabItemSelected) { event in
                if event.isRepeat, event.isRoot {
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .content:
                if viewModel.groups.isEmpty {
                    ContentUnavailableView(
                        L10n.noResults.localizedCapitalized,
                        systemImage: "rectangle.on.rectangle.slash"
                    )
                    .focusable()
                } else {
                    contentView
                }
            case .error:
                viewModel.error.map(ErrorView.init)
            case .initial, .refreshing:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .animation(.linear(duration: 0.2), value: viewModel.background.states)
        .navigationTitle(viewModel.provider.displayTitle)
        #if os(iOS)
        .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
        #elseif os(tvOS)
        .toolbar(router.isRootOfPath ? .hidden : .automatic, for: .navigationBar)
        #endif
        .onFirstAppear {
            viewModel.refresh()
        }
        .refreshable {
            viewModel.refresh()
        }
        .sinceLastDisappear { interval in
            viewModel.refreshIfNeeded(sinceLastDisappear: interval)
        }
        .onSceneWillEnterForeground {
            viewModel.refreshIfPendingChanges()
        }
        .topBarTrailing {
            if #unavailable(iOS 26.0) {
                if viewModel.background.is(.refreshing) {
                    ProgressView()
                }
            }

            #if os(iOS)
            if let musicPlaybackParent {
                MusicCollectionPlayButton(parent: musicPlaybackParent)
            }
            #endif
        }
        .environmentObject(focusCoordinator)
    }
}

#if os(iOS)
private struct MusicCollectionPlayButton: View {

    let parent: BaseItemDto

    @State
    private var isLoading = false

    var body: some View {
        Button {
            play()
        } label: {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "play.fill")
            }
        }
        .disabled(isLoading)
        .accessibilityLabel(L10n.play)
    }

    private func play() {
        guard !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            defer { isLoading = false }

            guard let userSession = Container.shared.currentUserSession() else { return }

            let library = MusicTrackLibrary(parent: parent, limit: 1)
            let pageState = LibraryPageState(
                pageOffset: 0,
                pageSize: 1,
                userSession: userSession
            )

            guard let item = try? await library.retrievePage(
                environment: .default,
                pageState: pageState
            ).first,
                let provider = item.getPlaybackItemProvider(userSession: userSession)
            else {
                return
            }

            NavigationRoute.musicPlayer(
                provider: provider,
                queue: MusicMediaPlayerQueue(item: item, parent: parent)
            )
        }
    }
}
#endif

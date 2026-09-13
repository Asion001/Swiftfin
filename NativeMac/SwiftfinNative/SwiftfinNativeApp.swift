//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import MediaServerCore
import SwiftUI

@main
struct SwiftfinNativeApp: App {
    @StateObject
    private var model = NativeLibraryModel()

    var body: some Scene {
        Window(L10n.appName, id: "library") {
            NativeLibraryView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1160, height: 760)
        .commands {
            CommandGroup(after: .textEditing) {
                Button(L10n.search) { model.searchFocusRequest = UUID() }
                    .keyboardShortcut("f")
                    .disabled(!model.signedIn)
            }
            CommandGroup(after: .newItem) {
                Button(L10n.refresh) { Task { await model.reload() } }
                    .keyboardShortcut("r")
                    .disabled(!model.signedIn)
            }
        }
        Settings {
            Form {
                LabeledContent(L10n.server, value: model.address)
                LabeledContent(L10n.username, value: model.username)
                Button(L10n.signOut) { model.signOut() }
                    .disabled(!model.signedIn)
            }
            .formStyle(.grouped)
            .frame(width: 440)
            .padding()
        }
    }
}

private struct NativeLibraryView: View {
    @ObservedObject
    var model: NativeLibraryModel
    @FocusState
    private var searchFocused: Bool

    var body: some View {
        Group {
            if model.signedIn {
                catalog
            } else {
                login
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = model.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(message)
                    Spacer()
                    Button(L10n.dismiss) { model.errorMessage = nil }
                }
                .padding(12)
                .background(.regularMaterial)
            }
        }
    }

    private var login: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L10n.connect).font(.largeTitle.bold())
            Form {
                TextField(L10n.server, text: $model.address, prompt: Text(verbatim: "https://jellyfin.example.com"))
                    .textContentType(.URL)
                TextField(L10n.username, text: $model.username)
                    .textContentType(.username)
                SecureField(L10n.password, text: $model.password)
                    .textContentType(.password)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(model.connecting)
            HStack {
                if model.connecting {
                    ProgressView().controlSize(.small)
                }
                Button(L10n.signIn) { Task { await model.connect() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.connecting || model.address.isEmpty || model.username.isEmpty)
            }
        }
        .frame(width: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var catalog: some View {
        NavigationSplitView {
            List(selection: $model.selectedLibrary) {
                Section(L10n.libraries) {
                    ForEach(model.libraries) { library in
                        Label(library.title, systemImage: "rectangle.stack")
                            .tag(library.id)
                    }
                }
            }
            .navigationTitle(L10n.appName)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle").font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.username).fontWeight(.medium).lineLimit(1)
                        Text(L10n.jellyfin).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        SettingsLink { Text(L10n.settings) }
                        Button(L10n.signOut) { model.signOut() }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel(L10n.account)
                }
                .padding(16)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.search.isEmpty ? (model.path.last?.title ?? L10n.libraries) : L10n.searchResults)
                                .font(.largeTitle.bold())
                            if let total = model.total {
                                Text(total == 1 ? L10n.oneItem : String.localizedStringWithFormat(L10n.itemCount, total))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if model.path.count > 1 {
                            Button { Task { await model.goBack() } } label: {
                                Label(L10n.back, systemImage: "chevron.left")
                            }
                        }
                    }
                    if !folders.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                            ForEach(folders) { item in
                                Button { Task { await model.openFolder(item) } } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
                                        Text(item.title).fontWeight(.medium).lineLimit(2)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 22)], alignment: .leading, spacing: 28) {
                        ForEach(films) { item in
                            Button { model.select(item) } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    NativePoster(item: item, model: model)
                                        .aspectRatio(2 / 3, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(
                                                    model.selectedItem == item.id ? Color.accentColor : .primary.opacity(0.08),
                                                    lineWidth: model.selectedItem == item.id ? 3 : 1
                                                )
                                        }
                                    Text(item.title).font(.headline).lineLimit(2)
                                    if let year = item.year {
                                        Text(String(year)).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.title)
                            .accessibilityHint(L10n.showDetails)
                        }
                    }
                    if model.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if model.items.isEmpty {
                        ContentUnavailableView(L10n.noItems, systemImage: "magnifyingglass", description: Text(L10n.trySearch))
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    if model.next != nil {
                        Button(L10n.loadMore) { Task { await model.loadMore() } }
                            .disabled(model.loading).frame(maxWidth: .infinity)
                    }
                }
                .padding(28)
            }
            .navigationTitle(model.path.last?.title ?? L10n.libraries)
            .toolbar {
                ToolbarItem {
                    Button { model.showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                        .disabled(model.selectedItem == nil)
                        .help(L10n.showDetails)
                }
            }
            .inspector(isPresented: $model.showsInspector) {
                inspector.inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: L10n.search)
        .searchFocused($searchFocused)
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .task(id: model.selectedLibrary) { await model.chooseLibrary() }
        .task(id: model.selectedItem) { await model.loadDetail() }
        .task(id: model.search) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await model.reload()
        }
    }

    private var folders: [NativeLibraryModel.Item] {
        model.items.filter(\.isFolder)
    }

    private var films: [NativeLibraryModel.Item] {
        model.items.filter { !$0.isFolder }
    }

    @ViewBuilder
    private var inspector: some View {
        if let item = model.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NativePoster(item: item, model: model)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(maxWidth: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity)
                    Text(item.title).font(.title.bold()).textSelection(.enabled)
                    HStack(spacing: 12) {
                        if let year = item.year {
                            Text(String(year))
                        }
                        if let duration = item.duration {
                            Text(Duration.seconds(duration.seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        }
                    }.font(.subheadline).foregroundStyle(.secondary)
                    Divider()
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview).lineSpacing(4).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        } else if model.detailLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(L10n.detailsUnavailable, systemImage: "exclamationmark.circle")
            } actions: {
                Button(L10n.retry) { Task { await model.loadDetail() } }
            }
        }
    }
}

private struct NativePoster: View {
    let item: NativeLibraryModel.Item
    @ObservedObject
    var model: NativeLibraryModel
    @State
    private var image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)
                        Image(systemName: "film").font(.largeTitle).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: item.artwork) { image = await model.image(for: item) }
    }
}

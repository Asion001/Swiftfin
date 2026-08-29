//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import SwiftUI

// swiftlint:disable hard_coded_display_string

enum MPVConfigurationStrings {
    static let title = String(enhancedLocalized: "mpv.config.title", defaultValue: "MPV configuration")
    static let advanced = String(enhancedLocalized: "mpv.config.advanced", defaultValue: "Advanced")
    static let editConfiguration = String(enhancedLocalized: "mpv.config.edit-mpv", defaultValue: "Edit mpv.conf")
    static let editInput = String(enhancedLocalized: "mpv.config.edit-input", defaultValue: "Edit input.conf")
    static let reset = String(enhancedLocalized: "mpv.config.reset", defaultValue: "Reset to defaults")
    static let resetConfirmation = String(
        enhancedLocalized: "mpv.config.reset-confirmation",
        defaultValue: "Replace this file with Swiftfin's defaults? Your changes will be lost."
    )
    static let save = String(enhancedLocalized: "mpv.config.save", defaultValue: "Save")
    static let restartRequired = String(
        enhancedLocalized: "mpv.config.restart-required",
        defaultValue: "Configuration files are read when playback starts. Changes apply to the next video."
    )
    static let precedence = String(
        enhancedLocalized: "mpv.config.precedence",
        defaultValue: "MPV reads this file after Swiftfin applies its own settings, so options set here override them."
    )
    static let inputPrecedence = String(
        enhancedLocalized: "mpv.config.input-precedence",
        defaultValue: "Swiftfin owns touch and remote controls. Bindings added here apply to attached keyboards."
    )
    static let loadFailed = String(enhancedLocalized: "mpv.config.load-failed", defaultValue: "Could not read this file.")
    static let saveFailed = String(enhancedLocalized: "mpv.config.save-failed", defaultValue: "Could not save this file.")
}

/// Curated MPV settings plus raw access to the files MPV actually reads.
struct MPVConfigurationView: View {

    @Router
    private var router

    let store: MPVConfigurationStore

    var body: some View {
        Section {
            Button(MPVConfigurationStrings.editConfiguration) {
                router.route(
                    to: .mpvFileEditor(
                        title: MPVConfigurationStrings.editConfiguration,
                        url: store.configurationURL,
                        defaultContents: MPVConfigurationStore.defaultConfiguration,
                        footer: MPVConfigurationStrings.precedence
                    )
                )
            }

            Button(MPVConfigurationStrings.editInput) {
                router.route(
                    to: .mpvFileEditor(
                        title: MPVConfigurationStrings.editInput,
                        url: store.inputConfigurationURL,
                        defaultContents: MPVConfigurationStore.defaultInputConfiguration,
                        footer: MPVConfigurationStrings.inputPrecedence
                    )
                )
            }
        } header: {
            Text(MPVConfigurationStrings.advanced)
        } footer: {
            Text(MPVConfigurationStrings.restartRequired)
        }
    }
}

/// A plain-text editor over one of MPV's configuration files.
struct MPVFileEditorView: View {

    @Environment(\.dismiss)
    private var dismiss

    let title: String
    let url: URL
    let defaultContents: String
    let footer: String

    @State
    private var contents: String = ""
    @State
    private var errorMessage: String?
    @State
    private var isPresentingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $contents)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 320)
            } footer: {
                Text(footer)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(MPVConfigurationStrings.reset, role: .destructive) {
                    isPresentingResetConfirmation = true
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(MPVConfigurationStrings.save) {
                    save()
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog(
            MPVConfigurationStrings.resetConfirmation,
            isPresented: $isPresentingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(MPVConfigurationStrings.reset, role: .destructive) {
                contents = defaultContents
                save()
            }
        }
    }

    private func load() {
        do {
            /// The file may not exist yet if playback has never started, in
            /// which case the default template is the right starting point.
            contents = FileManager.default.fileExists(atPath: url.path)
                ? try String(contentsOf: url, encoding: .utf8)
                : defaultContents
        } catch {
            errorMessage = MPVConfigurationStrings.loadFailed
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = MPVConfigurationStrings.saveFailed
        }
    }
}

// swiftlint:enable hard_coded_display_string
#endif

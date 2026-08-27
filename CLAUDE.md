# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository context

This is **Asion001/Swiftfin**, a fork of `jellyfin/Swiftfin` (remote `upstream`) that adds an "Enhanced" iOS player and its own distribution channels (AltStore source, Mac Catalyst installer). Upstream is merged automatically by the `Sync Jellyfin Upstream` workflow, so keep fork-only changes small and conflict-friendly.

Swiftfin is a SwiftUI Jellyfin client targeting iOS 18+ / tvOS 26+ (plus Mac Catalyst in this fork).

## Setup

```bash
brew bundle --file Brewfile && carthage update --use-xcframeworks
```

Carthage supplies MobileVLCKit/TVVLCKit (pinned in `Cartfile`); everything else is SPM. Builds fail without the Carthage step. Local signing goes in `XcodeConfig/DevelopmentTeam.xcconfig` (gitignored) — never commit a development team.

## Build, test, lint

```bash
xcodebuild -quiet -skipMacroValidation -skipPackagePluginValidation -project Swiftfin.xcodeproj -scheme Swiftfin -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -quiet -skipMacroValidation -skipPackagePluginValidation -project Swiftfin.xcodeproj -scheme Swiftfin -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' CODE_SIGNING_ALLOWED=NO -only-testing:SwiftfinTests test
```

Single test: append the identifier, e.g. `-only-testing:SwiftfinTests/VideoEnhancementTests/testRouterRootStateTracksCoordinatorInsteadOfCachingFirstValue`.

Other schemes/destinations exercised by CI: `-scheme 'Swiftfin tvOS' -destination 'generic/platform=tvOS'`, and Mac Catalyst via `-destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGN_ENTITLEMENTS= ARCHS=arm64`.

CI blocks merges on all three of these:

```bash
swiftformat . --lint --config .swiftformat && swiftlint lint --strict --config .swiftlint.yml && swift Scripts/Translations/FindUnusedStrings.swift
```

`python3 -m unittest Scripts/test_update_altstore_source.py` covers the AltStore source generator.

Xcode build phases run `swiftformat .`, `swiftlint lint`, `swiftgen`, and `AlphabetizeStrings.swift` automatically on build, so an Xcode build will rewrite files. Xcode version is pinned in `.github/workflows/ci.yml` (`XCODE_VERSION`).

## Localization

- User-facing strings live in `Translations/en.lproj/Localizable.strings`; other locales come from Weblate — do not hand-edit them.
- `Shared/Strings/Strings.swift` is SwiftGen output. Never edit it; edit the `.strings` file and rebuild (or run `swiftgen`).
- Reference strings as `L10n.someKey`. The SwiftLint `hard_coded_display_string` custom rule flags literal strings passed to `Text`/`Button`/`Label`/`Toggle`/`Picker`/`Section`/`LabeledContent` and in `displayTitle` — run under `--strict`, so violations fail CI. Experimental fork-only strings use `String(localized:defaultValue:)` instead (see `VideoPlayerType.displayTitle`).
- Unused keys fail CI; remove keys along with their last usage.

## Code conventions

- Every Swift file needs the MPL header block that `swiftformat` inserts (`--header` in `.swiftformat`); copying an existing file's header is the easiest way.
- SwiftFormat config is authoritative: 4-space tabs, 140 max width, `--wraparguments before-first`, attributes on their own line, `--shortoptionals always`.
- `// MARK:` comments are expected for organization.

## Architecture

**Shared backend, per-platform views.** `Shared/` holds models, view models, services, and views usable on both platforms; `Swiftfin/` (target *Swiftfin iOS*) and `Swiftfin tvOS/` hold platform-specific views. Changing a shared view model usually means touching both clients. Within a shared view, split platforms with the `PlatformView` protocol (`iOSView` / `tvOSView`) or `#if os(iOS)`.

**View models are `@Stateful` state machines.** Most inherit `ViewModel` (`Shared/ViewModels/ViewModel.swift`), which injects `currentUserSession` and offers `authenticatedClient` / `send(_ request:)` for JellyfinAPI calls. They use the `StatefulMacro` package: a `@CasePathable enum Action` with a `transition` describing state moves, plus `State`, `BackgroundState`, `Event` enums, and `@Function(\Action.Cases.foo)` methods implementing each action. `Shared/ViewModels/SelectUserViewModel.swift` is the canonical example. The older hand-written `Stateful`/`Eventful` protocols in `Shared/Objects/` are legacy and being migrated away.

**Navigation is coordinator-based, not NavigationLink-based.** Views use the `@Router` property wrapper (`Shared/Coordinators/Navigation/Router.swift`) and call `router.route(to: .someRoute(...))`. Destinations are declared as static `NavigationRoute` factories in `Shared/Coordinators/Navigation/NavigationRoute/NavigationRoute+*.swift`, each carrying a transition style (`push`/`sheet`/`fullscreen`). Never cache the router across view updates — resolve it from the environment each time.

**Persistence has three layers.** `Defaults` (`Shared/Services/SwiftfinDefaults.swift`) for single-value settings, namespaced into an app suite and a per-user suite; `StoredValue` (`Shared/SwiftfinStore/StoredValue/`) for larger values and collections, backed by either UserDefaults or the SQL store; CoreStore (`Shared/SwiftfinStore/`) for servers/users/`AnyData` with a V1→V2→V3 migration chain including manual migration steps. Adding a schema version means extending the chain, not editing an existing schema.

**Dependency injection is FactoryKit.** Services register themselves via `extension Container` next to their implementation (`UserSessionManager`, `Keychain`, `DownloadManager`, `Notifications`, `MediaPlayerManager`) and are consumed with `@Injected`. `UserSessionManager` owns sign-in/sign-out, session restore, the socket connection, and the active `MediaPlayerManager`; view models re-resolve `userSession` on `didChangeServerConnection`.

**Playback.** `MediaPlayerManager` (also `@Stateful`) drives a `MediaPlayerProxy` — the protocol in `Shared/Objects/MediaPlayerManager/MediaPlayerProxy/MediaPlayerProxy.swift` with capability sub-protocols (`MediaPlayerSubtitleConfigurable`, `MediaPlayerScreenshotCapturing`, etc.) implemented by `+VLC`, `+AVPlayer`, and the fork's `+MPV` proxies. `VideoPlayerType` (`Shared/Objects/VideoPlayerType/`) selects the backend and supplies the Jellyfin device profile (direct-play/transcoding/subtitle profiles) for that backend, so player changes usually require touching both the proxy and the profile.

**The MPV player** is this fork's main addition and is iOS/iPadOS/Catalyst only. libmpv is embedded via MPVKit and driven from `Shared/Services/MPV/`: `MPVClientCore` owns the libmpv handle on a serial queue, `MPVConfigurationStore` owns the writable config/shaders/screenshots directories, and `MPVUpscaler`/`MPVUpscalerController` translate the user's upscaler selection into mpv options. MPV renders straight into a `CAMetalLayer` via `vo=gpu-next`, so it has no PiP or AirPlay video. Two settings enums are persisted with legacy-value migrations you must preserve: `VideoPlayerType` decodes `"enhanced"` as `.mpv`, and `VideoEnhancementProvider` decodes `"anime4K"` as `.shader`. MetalFX upscaling requires a patched libmpv and is probed at runtime (`MPVUpscaler.metalFXOptionName`) rather than assumed. See `Documentation/mpv.md`.

## Fork-specific workflows

- `enhancement-ci.yml` ("MPV Player CI") — MPV tests plus tvOS and Mac Catalyst compatibility builds.
- `altstore-release.yml` — builds the unsigned IPA (`dev.asion.swiftfin.enhanced`) and Mac Catalyst app, then regenerates `altstore-source.json` via `Scripts/update_altstore_source.py`. Do not hand-edit `altstore-source.json`.
- `sync-upstream.yml` — daily conflict-free merge from `jellyfin/Swiftfin`.

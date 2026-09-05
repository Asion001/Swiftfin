# Separate native macOS application

## Current result

Audited on 2026-09-05. `Swiftfin.xcodeproj` has iOS, tvOS and test targets. The existing Mac application is built from the iOS target with Mac Catalyst. Its arm64 Debug build succeeded during this player-fix task. This is not a separate AppKit application.

A separate macOS target is not implemented by this document. The user confirmed a separate native AppKit/SwiftUI application after finding the Catalyst build unsatisfactory. The implementation will use the macOS SDK and native Mac navigation, windows and controls.

## Proposed implementation

1. Add a `Swiftfin macOS` application target and shared scheme using the macOS SDK. Define its own Info.plist, entitlements, bundle identifier and signing settings. Start with arm64 for the MacBook; add Intel only after checking every binary dependency. Keep the existing Catalyst artifact available during the port.
2. Extract Foundation-based account, connection, catalog and playback domain code into shared modules. Share the provider boundary described in [the Silo plan](silo-native-integration-plan.md). The current `UserSession`, `MediaPlayerItem` and view models directly depend on Jellyfin DTOs; avoid building a second incompatible data model just for Mac.
3. Port app/session lifecycle to SwiftUI `App`, window scenes and AppKit. Replace UIKit navigation/presentation and platform helpers at their boundaries. The audit found UIKit references in 112 files under `Shared`; compiling them with `os(macOS)` alone will not supply their UIKit types.
4. Build a Mac navigation shell with sidebar, toolbar search, independently resizable library/detail/player windows, native Settings, menus and keyboard commands. Port account/server selection, library/home/search, detail/season/episode views, favorites, watched state, queue and downloads. Preserve the same provider capabilities and user state across these screens.
5. Share `MPVClientCore`, initial/playback options, configuration storage and upscaler option resolution after removing iOS-only compile guards and isolating Defaults/UI dependencies. Host its owned `CAMetalLayer` in `NSViewRepresentable`. Replace UIScreen/UIView sizing with AppKit backing coordinates, `backingScaleFactor`, display-change notifications and a tested EDR policy.
6. Implement Mac player lifecycle: window close/fullscreen, Space pause, seek and track shortcuts, scroll/trackpad behavior, fit/fill persistence, screenshot destination picker, live subtitle controls, statistics/logs, audio-output selection, Now Playing and power assertions. Stop the MPV context exactly once when its playback window ends; swapping views must retain the render layer.
7. Verify the MPVKit macOS slices and patched renderer. Enable MetalFX only after probing the option and testing its actual execution. A Catalyst link that references the macOS MetalFX framework is not evidence of a correct AppKit runtime. Test shader/MetalFX/off changes, Retina resizing and monitor/HDR transitions separately.
8. Use macOS Keychain for credentials. Handle Keychain failures visibly without silently copying Catalyst's ad-hoc-signing credential-file fallback. Migrate existing local preferences and saved servers only with explicit scope, and retain the old app's data until migration is verified.
9. Add a native macOS CI build/test job, bundle shaders/localizations/licenses, and produce a distinct local `.app`. Update the installer/release process only after that artifact is verified. Publishing, notarization and replacing the installed app are separate delivery actions.

## Definition of complete

- `xcodebuild -scheme 'Swiftfin macOS' -destination 'platform=macOS,arch=arm64' build` exits successfully; the result targets macOS, not Mac Catalyst or Designed for iPad.
- The app launches on the MacBook and completes sign-in, home/library/search, film and episode playback, tracks, subtitles, seek/resume, next episode, fit/fill, upscaling and statistics.
- Window/fullscreen/Retina/external-display changes work during playback, including pause and renderer changes. Keyboard navigation and standard Mac menus work without touch-only affordances.
- Native network, playback, storage and session tests pass, with live server progress confirmed. iOS/tvOS regressions remain green.
- Required binaries are embedded, architecture slices and signatures are checked, and the app works outside DerivedData. Mark signing/notarization and platform-limited features accurately.

Keep the native target and Silo provider as separate milestones. They can share modules, but neither a successful Catalyst compile nor a new login-only Mac shell satisfies full native parity.

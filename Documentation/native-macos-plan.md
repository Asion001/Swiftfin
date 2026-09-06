# Separate native macOS application

## Current result

Audited on 2026-09-05. `Swiftfin.xcodeproj` has iOS, tvOS and test targets. The existing Mac application is built from the iOS target with Mac Catalyst. Its arm64 Debug build succeeded during this player-fix task. This is not a separate AppKit application.

A separate macOS target is not implemented by this document. The user confirmed a separate native AppKit/SwiftUI application after finding the Catalyst build unsatisfactory. The implementation will use the macOS SDK and native Mac navigation, windows and controls.

## Proposed implementation

Planning refresh: 2026-09-06 against Swiftfin `348fc2fd`. This includes the new media-segment/intro-skip support and Catalyst framework-layout repair. Neither changes the requirement for a separate macOS application. No native app or native dependency build was produced during this planning pass.

### First prerequisite: native playback binaries

The installed MPVKit artifacts were inspected after the user confirmed the native port. `Libmpv`, `Libavcodec`, `Libavdevice`, `Libavfilter`, `Libavformat`, `Libavutil`, `Libswresample`, and `Libswscale` currently contain only iOS device, iOS simulator and Mac Catalyst slices. None has a `SupportedPlatform = macos` entry. The package manifest advertising macOS support does not make these particular release artifacts linkable by a native target.

Before integrating playback into the new application:

1. Build the patched MPVKit/FFmpeg stack for macOS arm64. The MPVKit build tooling has a `platform=macos` path, but its output still needs packaging and validation for SwiftPM consumption.
2. Produce XCFrameworks containing genuine macOS slices, preserving the existing iOS/Catalyst slices. Update artifact checksums and pin a tested dependency revision; do not change existing release URLs in place.
3. Confirm every transitive native dependency, including the macOS-only Lua dependency, resolves. Inspect Mach-O platform/architecture and linked libraries, then test the patched MoltenVK layer host and MetalFX option on the MacBook.
4. Only then connect the native `NSView` playback surface. A browser/player window with no usable playback dependency does not complete this prerequisite.

### N1 build recipe and evidence

Swiftfin pins MPVKit `1.0.0-swiftfin.4`, revision `05c7040dc34385634d67444113ca3638b59ac73a`. The audited local MPVKit checkout is `7ef6b704efc615d015a2db2e2f9319fb36159c2a`; its build code matches the pinned revision, but its MetalFX patch differs. Choose and record the patch revision before building. Do not silently mix binary provenance.

Verified in MPVKit's `Sources/BuildScripts/XCFrameworkBuild`:

- `base.swift`, `ArgumentOptions.parse`: `platform=ios` already adds the simulator; `platform=macos` selects macOS. There is no architecture-selection argument in this parser.
- `PlatformType.architectures` requests both arm64 and x86_64 for macOS. The first app can target arm64 while consuming a universal framework. An arm64-only dependency build requires an explicit tooling change; passing an invented `arch=arm64` flag will not select it.
- `createFramework` combines each architecture, writes headers/module maps, and calls `fixShallowBundles` for macOS. `createXCFramework` already packages framework slices. Extend and verify this existing path instead of writing a second packager.
- `createXCFramework` clears prior XCFramework outputs and builds from the selected platforms. Running a macOS-only build into the directory containing a complete release would lose those other output slices. Use isolated build directories and assemble the complete release deliberately.
- Working directory becomes `dist`; XCFrameworks are written under `dist/release/xcframework`, and zipped artifacts/checksums are produced by `packageRelease`. Some older prose in MPVKit's `FORK.md` describes a different output path; use the build implementation as the authority.
- The macOS libmpv configuration enables Cocoa, CoreAudio, VideoToolbox, LuaJIT and MetalFX. It can also produce a desktop executable for the host architecture; that executable is useful for diagnosis but does not replace framework integration testing.
- `0001-player-add-moltenvk-context.patch` bridges `wid` directly to `CAMetalLayer` and does not retain it. Keep `gpu-context=moltenvk` explicit for this hosting path; the native player owner must retain the layer until the MPV context has shut down. An `NSWindow` or `NSView` pointer is not a valid replacement for that layer pointer.

Proposed commands, to run in an isolated checkout of the selected MPVKit revision:

```sh
# Dependency smoke build; currently builds both Mac architectures.
make build platform=macos

# Separate full release build retaining the currently consumed Apple slices.
# The parser expands ios to ios + isimulator.
make build platform=ios,maccatalyst,macos
```

Do not upload that second build until a manifest comparison confirms it preserves every platform/architecture offered by the release being replaced, including transitive artifacts. Leave unused GPL products unchanged. Record Xcode/SDK version, source revisions, build options, build exit status and SHA-256 for every zip. Re-running a source build in a directory with cached source trees must not skip newly selected patches; use a fresh checkout/build directory for release validation.

N1 acceptance evidence:

| Check | Required result |
| --- | --- |
| Eight rebuilt framework plists | A macOS slice exists, with arm64 listed; all required prior slices remain present |
| Transitive dependency inventory | Every dependency selected for the macOS MPVKit product, including LuaJIT, has an appropriate slice |
| Link/run | A small macOS app imports libmpv, links using the macOS SDK, launches and renders a local sample into its owned layer |
| Mach-O and linking | App and applicable dynamic binaries report `MACOS`; static archive members are examined as needed; no unintended Homebrew/checkout absolute runtime dependency |
| Framework structure | Versioned macOS bundles and symlinks are valid; signing/embedding distinguishes static archives from runtime frameworks |
| Renderer controls | MetalFX is probed and visibly compared with off/shader paths; subtitle overlays remain outside the upscale pass |
| Lifecycle | Resize, Retina scale change, pause, fullscreen, close and reopen produce no stale layer, abandoned audio or renderer crash |

This build investigation remains actionable even without server credentials: use local representative media and keep server authentication out of the smoke app.

### Reviewable implementation batches

- **N1 — Playback dependency:** native artifacts and a small rendering/lifecycle smoke test; record build and playback evidence.
- **N2 — Shared server boundary:** provider-scoped identity, catalog, credentials and playback contracts shared with the Silo work; retain the current Jellyfin adapter while migrating callers incrementally.
- **N3 — Native application:** macOS target, SwiftUI sidebar/detail layout, native Settings, menus and window lifecycle; connect real Jellyfin login, library/search, details and episodes.
- **N4 — Native playback and parity:** MPV surface, tracks/subtitles, resume/queue, fill, upscaling, statistics and downloads, followed by MacBook and iOS regression checks.

N1 and N2 have independent acceptance gates. N3's navigation/layout and provider work can proceed while N1 is being validated; integrating the actual MPV surface depends on N1. N4 depends on both paths. This ordering does not require simultaneous agents.

Do not reuse Catalyst presentation controllers or the tablet navigation layout in N3. Use Mac window sizing, sidebar navigation, toolbar search, keyboard commands and pointer controls from the beginning. This addresses the user's dissatisfaction with the previous build's appearance as well as the binary-platform requirement.

### Detailed work

1. Add a `Swiftfin macOS` application target and shared scheme using the macOS SDK. Define its own Info.plist, entitlements, bundle identifier and signing settings. Start with arm64 for the MacBook; add Intel only after checking every binary dependency. Keep the existing Catalyst artifact available during the port.
2. Extract Foundation-based account, connection, catalog and playback domain code into shared modules. Share the provider boundary described in [the Silo plan](silo-native-integration-plan.md). The current `UserSession`, `MediaPlayerItem` and view models directly depend on Jellyfin DTOs; avoid building a second incompatible data model just for Mac.
3. Port app/session lifecycle to SwiftUI `App`, window scenes and AppKit. Replace UIKit navigation/presentation and platform helpers at their boundaries. The audit found UIKit references in 112 files under `Shared`; compiling them with `os(macOS)` alone will not supply their UIKit types.
4. Build a Mac navigation shell with sidebar, toolbar search, independently resizable library/detail/player windows, native Settings, menus and keyboard commands. Port account/server selection, library/home/search, detail/season/episode views, favorites, watched state, queue and downloads. Preserve the same provider capabilities and user state across these screens.
5. Share `MPVClientCore`, initial/playback options, configuration storage and upscaler option resolution after removing iOS-only compile guards and isolating Defaults/UI dependencies. Host its owned `CAMetalLayer` in `NSViewRepresentable`. Replace UIScreen/UIView sizing with AppKit backing coordinates, `backingScaleFactor`, display-change notifications and a tested EDR policy.
6. Implement Mac player lifecycle: window close/fullscreen, Space pause, seek and track shortcuts, scroll/trackpad behavior, fit/fill persistence, screenshot destination picker, live subtitle controls, statistics/logs, audio-output selection, Now Playing and power assertions. Stop the MPV context exactly once when its playback window ends; swapping views must retain the render layer.
7. Verify the MPVKit macOS slices and patched renderer. Enable MetalFX only after probing the option and testing its actual execution. A Catalyst link that references the macOS MetalFX framework is not evidence of a correct AppKit runtime. Test shader/MetalFX/off changes, Retina resizing and monitor/HDR transitions separately.
8. Use macOS Keychain for credentials. Handle Keychain failures visibly without silently copying Catalyst's ad-hoc-signing credential-file fallback. Migrate existing local preferences and saved servers only with explicit scope, and retain the old app's data until migration is verified.
9. Add a native macOS CI build/test job, bundle shaders/localizations/licenses, and produce a distinct local `.app`. Update the installer/release process only after that artifact is verified. Publishing, notarization and replacing the installed app are separate delivery actions.

## Native Mac screen and interaction contract

Initial platform choice: macOS 15 or later, arm64 application, built with the installed Xcode SDK. Confirm all selected dependencies against that deployment target in N1/N3; do not copy the iOS `IPHONEOS_DEPLOYMENT_TARGET` or Catalyst ABI flags into the native target.

| Surface | Native implementation and behavior |
| --- | --- |
| Main window | SwiftUI `NavigationSplitView`, standard titlebar/traffic lights and system sidebar; remember window geometry through normal scene restoration |
| Sidebar | Server/account/profile switcher, Home, Libraries, Favorites, Downloads and Settings access; roughly 220–280 points wide and user-resizable |
| Home/library | Adaptive poster grid with deliberate spacing at common MacBook window sizes; selection, context menus and keyboard focus; use real loading, empty and failure states |
| Search | Toolbar search, Command-F focus, cancellable requests and scoped results; preserve the selected server/profile and return location |
| Detail | Poster plus title/metadata/actions and readable overview; separate season/episode navigation; return to the previous scroll position |
| Player window | Dedicated playback window with native fullscreen; auto-hiding playback controls, a scrubber, play/pause, tracks, fit/fill and an inspector for stats/settings |
| Player input | Space pauses, arrows seek, Escape leaves fullscreen before closing a normal player window; text fields retain normal typing/arrow behavior; expose shortcuts in menus |
| Player inspector | Native form/list controls for subtitle appearance, audio/subtitle delay, upscaler, chapters, queue and live statistics; retain its selection during playback |
| Settings | Native Settings scene and Command-comma; grouped General, Playback, Subtitles, Downloads and Accounts panes |
| Notifications | Inline errors and lightweight player feedback; permission prompts only when invoking the relevant system feature |

Use system typography, light/dark appearance, focus indication and accessibility labels. Do not copy iPad sheets, large touch-only buttons or a bottom tab bar into the main Mac window. Do not hard-code full-screen-only layout. Validate a compact window, a normal MacBook window and a larger external display, including increased text size and keyboard-only use.

New intro/credit skip behavior is part of parity: port the rules in `MediaSegmentResolver` and the per-item state currently owned by `MediaSegmentsObserver`. Keep markers in source time, retain manual/automatic per-type preferences, and do not automatically skip the same marker again after a deliberate backward seek. Share the policy while replacing the UIKit-dependent presentation.

## Planned source changes

- `Swiftfin.xcodeproj/project.pbxproj` and a shared `Swiftfin macOS` scheme: native application and native test target; link only compatible dependencies.
- `Swiftfin macOS/`: App/scene entry, sidebar/navigation, catalog/detail views, native player surface/controls, Settings and platform services. These names describe proposed files, not existing implementations.
- `Shared/Services/MediaServers/`: the [provider contract](media-provider-contract.md), provider adapters and domain types.
- `Shared/Services/MPV/`: lift platform guards on the engine/configuration code after extracting UI/defaults dependencies; retain serialized option application and context restart behavior.
- `Shared/Objects/VideoEnhancement/` and `Shared/Objects/MediaSegments/`: extract portable policy from platform presentation and Jellyfin DTO conversion.
- `Shared/Services/UserSession/` and `Shared/SwiftfinStore/`: provider-scoped session/storage migration, leaving old records usable during rollout.
- Native CI/release scripts: add native build and artifact checks first; change the Mac updater's artifact only after the new app is verified.

## Definition of complete

- `xcodebuild -scheme 'Swiftfin macOS' -destination 'platform=macOS,arch=arm64' build` exits successfully; the result targets macOS, not Mac Catalyst or Designed for iPad.
- The app launches on the MacBook and completes sign-in, home/library/search, film and episode playback, tracks, subtitles, seek/resume, next episode, fit/fill, upscaling and statistics.
- Window/fullscreen/Retina/external-display changes work during playback, including pause and renderer changes. Keyboard navigation and standard Mac menus work without touch-only affordances.
- Native network, playback, storage and session tests pass, with live server progress confirmed. iOS/tvOS regressions remain green.
- Required binaries are embedded, architecture slices and signatures are checked, and the app works outside DerivedData. Mark signing/notarization and platform-limited features accurately.

Keep the native target and Silo provider as separate milestones. They can share modules, but neither a successful Catalyst compile nor a new login-only Mac shell satisfies full native parity.

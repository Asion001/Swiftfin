# Swiftfin Native catalog preview

A separate arm64 macOS 15+ SwiftUI application with native windows, sidebar, search, Settings and an optional detail inspector. It connects to Jellyfin through the shared provider boundary.

## Build and open

From the repository root with Xcode selected:

```sh
python3 Scripts/build_native_app.py --output /tmp/SwiftfinNative.app
open /tmp/SwiftfinNative.app
```

The script builds a release executable, embeds localized resources and signs locally. This is a development preview, not a notarized distribution. The packaged app does not require the temporary Swift build directory at runtime.

Enter your final HTTP/HTTPS Jellyfin address, including any reverse-proxy prefix, username and password. The server URL and local device/server identities persist; passwords and tokens stay in memory. Relaunching requires sign-in. Sign-out clears the local session and artwork cache. Server token revocation and Keychain persistence remain part of the session milestone. Existing iOS/Catalyst accounts are untouched.

Implemented: library discovery, paginated browsing, recursive library search, folder navigation, details and authenticated primary artwork. Command-F focuses search, Command-R refreshes and Command-comma opens Settings. Posters select the detail inspector; folders open directly. The sidebar account menu exposes sign-out.

Pending: playback connected to this catalog, resume/home sections, episode-specific navigation, sorting/filtering, multiple accounts, Keychain persistence, downloads and Silo. The MPV surface remains the separate `MPVRenderCheck` milestone until the playback adapter is ready. This preview has no nonfunctional Play button.

## Local verification

```sh
swift test
python3 Tests/Fixtures/jellyfin_catalog_server.py --port 8770
```

Connect to `http://127.0.0.1:8770/jellyfin`, using `fixture` for both username and password. The loopback-only server validates real request paths and authentication headers. Verify library/poster loading, search, selection, folders, Settings, sign-out and keyboard access. The fictional Northern Lights poster was generated for this fixture and is not real library content.

The `/redirect` base URL returns a redirect on login. The app must display an actionable error; the fixture log must contain no forwarded login request. No real credentials are needed for fixture checks.

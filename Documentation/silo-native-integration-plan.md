# Native Silo integration alongside Jellyfin

## Decision and evidence

Add Silo as a first-class server provider using its native HTTP API. Keep Jellyfin as a fully supported provider with unchanged saved connections. Silo's Jellyfin compatibility listener can be tested separately, but is not the implementation of native Silo support.

Source audit: 2026-09-05, Silo server commit [`3131494e52e069fc1ac10e1a31503c797d09f26e`](https://github.com/Silo-Server/silo-server/tree/3131494e52e069fc1ac10e1a31503c797d09f26e). Silo is pre-1.0; pin contract fixtures to this revision and refresh them deliberately. This is an implementation plan, not a completed integration or a claim of testing against a running Silo instance.

Primary references:

- [Native routes](https://github.com/Silo-Server/silo-server/blob/3131494e52e069fc1ac10e1a31503c797d09f26e/internal/api/router.go)
- [Playback v3 contract](https://github.com/Silo-Server/silo-server/blob/3131494e52e069fc1ac10e1a31503c797d09f26e/docs/architecture/playback-protocol-v3.md)
- [Playback JSON schemas and fixtures](https://github.com/Silo-Server/silo-server/tree/3131494e52e069fc1ac10e1a31503c797d09f26e/docs/design/schemas/playback-v3/v3)
- [Authentication implementation](https://github.com/Silo-Server/silo-server/blob/3131494e52e069fc1ac10e1a31503c797d09f26e/internal/api/handlers/auth.go)
- [Settings contract](https://github.com/Silo-Server/silo-server/blob/3131494e52e069fc1ac10e1a31503c797d09f26e/docs/settings-api.md)
- [Public project documentation](https://siloserver.org/docs/)

## Current Swiftfin seams

The backend is not currently interchangeable. `UserSession.client` is a concrete `JellyfinClient`; 38 files under `Shared/ViewModels` reference JellyfinAPI. `MediaPlayerItem` contains `BaseItemDto`, `MediaSourceInfo`, `DeviceProfile`, and Jellyfin stream indices. `MediaProgressObserver` sends Jellyfin session reports. `ServerSocketManager` exposes Jellyfin socket events directly.

Introduce a provider boundary at these seams instead of fabricating Jellyfin DTOs from Silo responses. A fake Jellyfin object would lose Silo profile identity, plan decisions, timeline offsets, and track identifiers.

Proposed shared modules:

| Module | Responsibility |
| --- | --- |
| `MediaDomain` | Provider/server/account/profile identity; catalog items, library queries, tracks, chapters, images, playback requests and state |
| `MediaServerProvider` | Capability discovery; authentication; library, detail, search, watched/favorite operations; playback planning and reporting |
| `JellyfinProvider` | Wrap existing JellyfinAPI calls and preserve their behavior |
| `SiloProvider` | URLSession transport, typed native DTOs, profile scope, playback v3 state machine, native events |
| `PlaybackEngine` | Local decoding, track selection, seeking, subtitles, screenshots, upscaling; no knowledge of either server's DTOs |
| Platform application | Navigation, account/profile picker, library screens, platform player surface and controls |

Use capability groups rather than one enormous protocol: authentication, catalog, playback, personal state, downloads, realtime, and administration. Account/provider changes cancel outstanding requests and close the previous session's subscriptions before publishing new data.

Persist `ServerProviderKind` (`jellyfin` / `silo`), a local connection UUID, canonical base URL, remote server identity when available, account ID, and optional profile ID. Existing records without a provider decode as Jellyfin. Keep remote IDs opaque and namespace database rows, artwork caches, downloads, settings, and credentials by provider + connection + account/profile. Matching titles or numeric IDs must never merge libraries or watch history across servers.

## Native API coverage

Paths below are relative to `/api/v1` and were checked against the router. Capability responses and schema fields, rather than a guessed version threshold, determine which controls appear.

| Feature | Native contract | Swiftfin work |
| --- | --- | --- |
| Connect and login | `/auth/providers`, `POST /auth/login`, `POST /auth/refresh`, `/auth/me`, `POST /auth/logout` | Provider picker, retained reverse-proxy base paths, single-flight token refresh, session expiry and revocation UI |
| Household profiles | `/profiles`, `POST /profiles/{id}/verify-pin`, `X-Profile-Id` | Separate account login from active profile selection; enforce PIN and profile access responses; clear profile caches when switching |
| Alternate login | `/auth/device/capability`, `/auth/device/start`, `/auth/device/poll`, OAuth provider routes | Native device approval and browser callback flow when advertised; never ask users to copy a raw access token |
| Library/home | `/user/libraries`, `/home/sections/{id}/items`, `/library/{id}/layout`, `/library/{id}/sections` | Native sections and pagination; distinguish an empty library from a failed request |
| Search and browse | `/catalog`, `/catalog/filters`, `/catalog/filters/search`, `POST /catalog/query` | Typed filters, debounced/cancellable search, stable paging and sorting |
| Details and episodes | `/catalog/items/{id}`, `/catalog/items/{id}/versions`, `/catalog/series/{id}/seasons`, `/catalog/series/{id}/seasons/{num}/episodes`, `/watch/{id}` | Native details, media-version selection, seasons, episode queues, artwork, people and metadata |
| Playback | `/playback/capability`, `POST /playback/start`, `POST /playback/{session_id}/replan` | Translate engine/output evidence into a v3 request; consume the returned plan |
| Playback lifecycle | `POST /playback/{session_id}/progress`, `DELETE /playback/{session_id}`, `POST /playback/route-events` | Accurate resume, pause/seek/stop reporting, finite recovery and diagnostics |
| Subtitles | Plan subtitle inventory; `/subtitles/{media_file_id}`, subtitle provider/search/download routes | Embedded and sidecar delivery, exact selection, ASS font attachments, conversion and burn-in fallback; local appearance controls |
| Personal state | `/watched/{id}`, `/favorites`, `/watchlist`, `/history`, `/progress`, `/sync/progress`, collection routes | Watched/unwatched, favorite/watchlist, resume and collections; scope all mutations to the active profile |
| Realtime | `/events/capability`, `/events/ws`, `/events/ws-ticket`, `/playback/sessions/{session_id}/control/ws` | Ticket/auth negotiation, reconnect, event deduplication, plan invalidation and remote controls |
| Downloads | `/downloads` routes and capability document | Native prepared-download lifecycle, progress, cancellation, expiration, offline catalog and progress reconciliation |
| Preferences | Native settings contract and playback preferences | Map documented settings to native controls; retain local device preferences separately from account/profile/server settings |
| Additional library types | Catalog plus audiobook, ebook, music/podcast features supported by the audited server | Audit each contract; native audio queue, audiobook chapters/resume, ebook/comic reader and reader progress are explicit later milestones |
| Silo-specific features | Recommendations, markers, calendar, notifications, requests, provider watch sync and sync-room contracts | Capability-gated native screens and playback actions; complete feature-by-feature conformance matrix before claiming full parity |
| Administration | Admin routes, capabilities and settings schema | Native server/library/user management and metadata/subtitle editing for authorized accounts; conceal unavailable operations for normal/child profiles |

Do not carry Silo server setup or infrastructure changes into this client task. No server deployment, scans, library rewrites, provider dashboard changes, or watch-history import is required to implement the client.

## Playback v3 requirements

1. Fetch capabilities before planning. Preserve unknown feature strings, but only advertise client features actually implemented. Match envelope and nested `protocol_version: 3` independently. Handle `426` as an update-required state.
2. Treat HTTP success and a playable decision separately. `POST /playback/start` returns `201` for both playable and terminal outcomes. Show the terminal reason; do not try to open an absent stream URL.
3. Let the server choose direct, progressive remux, HLS remux, or transcode delivery. Report measured MPV/native-engine capabilities and display/audio output evidence. Codec names alone do not prove HDR, Dolby Vision, multichannel passthrough, or sustained software decoding.
4. Keep source and player clocks distinct. Source position is player position plus the plan's timeline offset. Initial player seek comes from `player_start_seconds`; the scrubber's total comes from `source.duration_seconds`, which may be absent. A growing HLS playlist duration is not the movie runtime.
5. Honor seek restrictions. Remux streams may have an open-ended window and require a `seek_reanchor` replan. Do not apply Jellyfin's generic local-seek behavior to those plans.
6. Use the server's subtitle inventory, `track_id` and combined index. Do not infer ordinals from array lengths or copy Jellyfin's global stream-index mapping. Clear the old artifact on each replan; load ASS font bundles when provided. A burn-in track cannot be resized locally, so expose that state clearly.
7. Preserve opaque `plan_id` and `plan_attempt_key`; never recreate them. Reuse a start attempt ID only for byte-identical retries. Separate intent changes (tracks, output, quality) from failure recovery; keep an attempt history and a finite retry budget.
8. Negotiate authenticated media deliberately. Handle authorization for video, redirects, HLS manifests/segments, sidecars and fonts. Send credentials only to the server and explicitly authorized media origins. Redact tokens, signed URLs and auth headers from MPV logs and exported diagnostics.
9. Handle `plan_invalidated` using the documented replan flow. Route-event telemetry does not itself change a plan. Stop exactly once on close/end/profile switch, flush final source progress, and reject late callbacks from prior sessions.
10. Turn these rules into golden-fixture and state-machine tests before connecting the new provider to the player UI.

## Delivery sequence and acceptance gates

The native Mac direction is now confirmed: separate AppKit/SwiftUI application. Start the shared provider contracts before creating Mac-specific networking code. The native MPVKit artifacts are a separate prerequisite for Mac playback, not a reason to delay Silo's contract/fixture tests or change its protocol.

The first implementation batch should add a platform-independent `Shared/Services/MediaServers` boundary with provider-scoped identity, capabilities, catalog queries, media metadata, playback plans and progress reporting. Keep Jellyfin DTO conversion inside its adapter; UI and engine contracts should use the shared domain types. Compile these types in both existing clients and the future native target. Test legacy connection decoding, ID collisions across providers/profiles, source/player clock conversion and cancellation of stale session results before adding the Silo login UI.

Then introduce typed Silo v3 DTOs and fixture-driven decisions. Do not advertise Silo as connectable in the server picker until authentication, profile selection, catalog loading and playable/terminal plan handling form a complete path.

### 1. Backend boundary with Jellyfin unchanged

Extract domain IDs, capabilities, catalog queries and playback request/response types. Wrap Jellyfin's current paths. Migrate connection storage with a backward-compatible default; introduce provider-aware caches and credentials.

Gate: existing Jellyfin sign-in, library/search, direct/transcoded playback, tracks, resume, next episode, downloads and remote commands still work. Decode an existing installation's stored server/user records without losing credentials or preferences.

### 2. Silo account and native catalog

Implement transport/auth/profile handling and catalog screens. Add unit tests using captured, redacted fixtures plus a deterministic local HTTP fixture server. Include Unicode, empty/missing fields, pagination, server subpaths, cancellation, expired tokens and PIN failures.

Gate: Jellyfin and Silo connections coexist; selecting an account/profile only displays that scope's libraries, artwork and personal state. Login/logout/refresh work without exposing credentials in logs or plain settings.

### 3. Silo playback

Implement the v3 DTOs and planner first, then connect the existing MPV engine. Add source-clock conversion, embedded/sidecar subtitle mapping, authenticated media, progress, replans and final teardown. Port the same adapter to the native macOS engine surface.

Gate: live direct play, server remux and transcode; pause/resume, local seek and server reanchor; audio/subtitle changes; end and next episode. Exercise terminal `201`, `401`, `404`, `409`, `426`, unavailable adaptation and exhausted recovery. Validate reported position against the server after closing playback.

### 4. Daily-use parity

Complete watched/favorite/watchlist/collections, recommendations and markers, settings, realtime/remote control, notifications and prepared downloads. Add offline progress conflict rules based on the server contract.

Gate: reconnect, server restart, profile switch, download interruption and remote commands work without duplicate sessions or cross-profile state. Test Jellyfin and Silo concurrently in the same app installation.

### 5. Full Silo coverage

Track every client-visible feature in a checked feature matrix: video, music, podcasts, audiobooks, ebooks/comics, discovery/calendar, requests, watch sync, watch-together, account/session controls and administration. Each row needs its native screen, endpoint contract, capability predicate, error behavior and test evidence. Where the server has no supported third-party contract, record the gap and obtain upstream clarification rather than implement against undocumented browser internals.

Gate: every claimed feature works natively on its supported platform. Explicitly mark unsupported or platform-limited features; a web link or Jellyfin compatibility connection does not count as native completion.

## Live validation needed

Use a user-provided Silo test server/account with representative movies, episodes, music and subtitle formats, plus a Jellyfin regression server. Fixtures can start immediately; real credentials are only needed for the live gates. Include SRT, authored ASS and image subtitles, anamorphic/rotated video, 1080p-to-Retina upscaling, HDR/SDR, multiple audio outputs, server subpaths and distributed proxy origins. Verify server-side session/progress evidence alongside actual iPad and Mac playback.

Native macOS and Silo should share the new domain/provider modules. Keep their UI and protocol migrations separately reviewable so a macOS navigation issue cannot block the Jellyfin regression work.

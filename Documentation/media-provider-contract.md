# Shared media-provider implementation contract

Status: proposed, 2026-09-06. No interfaces below have been implemented yet. This is the first shared-code batch for the [native Mac port](native-macos-plan.md) and [Silo integration](silo-native-integration-plan.md).

## Module boundary

Begin under `Shared/Services/MediaServers` with Foundation/Codable/Sendable types. Keep UIKit, AppKit, SwiftUI, Defaults, CoreStore, JellyfinAPI and Silo wire DTOs out of the domain layer. Storage, transport and UI adapters depend on it. This allows host-side tests and an eventual package extraction without rewriting the new Mac client.

Use focused interfaces rather than adding every possible operation to `MediaPlayerManager`:

| Interface | Operations and ownership |
| --- | --- |
| `ServerAuthentication` | Discover login methods, authenticate, refresh, select/verify a profile, sign out; return opaque session handles rather than exposing tokens to views |
| `MediaCatalog` | Libraries, home sections, paged queries, detail, versions, episodes, artwork requests and markers |
| `PersonalMediaState` | Watched, favorite/watchlist, collections and progress; all writes require a captured session scope |
| `PlaybackPlanning` | Capabilities, start, replan, progress, route diagnostics, end; retain provider-specific session/attempt data internally |
| `MediaEvents` | Async event stream with reconnect and scope identity; expose domain events instead of Jellyfin socket enums |
| `OfflineMedia` | Capability, prepare, download state, cancel, remove and reconcile progress; use persisted jobs independent of a screen's lifetime |

Do not require providers to pretend they support every interface. Model supported, unsupported and temporarily unavailable capability states separately. A timeout must not permanently hide a supported feature.

## Identity and persistence

An endpoint is a route to a server, not the identity of that server. Existing Swiftfin already keeps multiple `ServerConnection` entries per `ServerState`; preserve that behavior.

| Type | Meaning |
| --- | --- |
| `ServerRecordID` | Stable local UUID for one configured server/provider; shared by its LAN/VPN/public endpoints |
| `ServerProviderKind` | Jellyfin or Silo; missing legacy value decodes as Jellyfin |
| `RemoteServerID` | Opaque identity from the server, when available; used with provider kind to detect a duplicate server record |
| `EndpointID` | A local connection ID with URL and routing preferences; switching it does not reset catalog IDs or credentials |
| `AccountID`, `ProfileID` | Opaque provider IDs; a Jellyfin user is its viewing scope without inventing a Silo profile |
| `SessionScope` | Server record + provider + account + optional profile + in-memory generation |
| `MediaID` | Server record + opaque item ID; media files/versions and tracks have separate IDs |

Cache/persistence keys include the stable server record and relevant account/profile scope. An artwork key can omit account/profile only if the response is explicitly shareable across those scopes. The session generation belongs to cancellation/race protection, not durable record identity. URLs, display names and unqualified remote IDs are not primary keys.

Source-backed migration notes:

- `SwiftfinStore.swift` currently uses V3 `AnyData`; server/user lists are encoded records stored through `StoredValues`. `V2ServerModel` and `V2UserModel` are historical migration schemas. Do not edit their definitions to add the new provider state.
- `SwiftfinStore+ServerState.swift` owns `ServerState` and alternative endpoints. Preserve server connection ordering and active connection selection while assigning stable local server IDs.
- `SwiftinStore+UserState.swift` reads credentials using `"\(id)-accessToken"`; `UserSessionState` stores a signed-in user ID. These need a provider/server-qualified lookup before Silo records are accepted.
- `UserSession.client`, `MediaPlayerItem`, `MediaProgressObserver` and `ServerSocketManager` expose Jellyfin-specific values today. Migrate them through adapters, one call path at a time; do not cast a Silo response into a synthetic `BaseItemDto`.

Migration procedure:

1. Add a versioned identity mapping alongside existing V3 records. Decode legacy server/user records as Jellyfin and assign stable local IDs transactionally. Reopening after an interrupted migration reuses the existing mapping.
2. Introduce namespaced credential lookup, with a fallback read of the old key only for an unambiguous legacy Jellyfin account. Verify the new Keychain write/read before marking that credential migrated. Keep the old value for backward compatibility during rollout.
3. If the old key could refer to multiple server accounts, require sign-in for that account rather than copying one token into multiple namespaces. A profile ID alone never selects an account token.
4. Migrate signed-in scope, provider-aware caches and settings through the identity mapping. Initially retain existing Jellyfin preference suites behind a compatibility adapter; do not globally rename all owner IDs in one pass.
5. Write schema/version and active-scope changes only after the necessary records are available. Store tokens exclusively through the credential service; the serialized mapping contains no secrets.
6. The separate native Mac bundle may lack access to the Catalyst app's Keychain group/container. First launch must support ordinary sign-in. Never work around that by searching other app containers for credentials or importing plaintext token files silently.

## Catalog and engine-facing types

`CatalogItem` contains domain ID, kind, title, overview, artwork references, duration when known, personal state and navigation relationships. Preserve unknown kinds as unsupported metadata, not a decoding crash. Page responses include an opaque continuation; adapters own provider-specific offset/filter syntax. Keep unknown total counts distinct from zero.

`PlaybackRequest` captures the item/file/version, requested source position, audio/subtitle intent and current engine/output capabilities. `PlaybackDecision` is playable, terminal, or an explicit provider error; HTTP success does not imply playable media.

`EnginePlaybackPlan` supplies a media resource handle, delivery class, source duration, timeline mapping, seek policy, track inventory, chapter/marker data and presentation notices. Resource handles resolve URLs and authentication through the adapter. Views never concatenate stream URLs or auth headers.

Engine capability evidence names the engine/build and actual platform output. Shared capability types must be expressive enough to preserve Silo v3 evidence requirements; the Jellyfin adapter converts only the applicable subset into its DeviceProfile. Do not simplify Silo's evidence into one list of codec strings.

`PlayerEvent` includes loaded, first frame, paused/resumed, position, buffering, selected tracks, failure and ended, tagged with the playback generation. The playback coordinator converts those events into provider reports. `MPVClientCore` stays on its serial queue, while observable UI state stays on the main actor.

## Lifecycle and recovery

Session lifecycle: signed out → authenticating → authenticated without profile / ready → refreshing or expired. Refresh is single-flight per account, with a bounded retry after authorization failure. Explicitly selecting a profile increments the session generation, cancels old catalog requests, closes subscriptions and ends the active playback session before new profile data appears.

Playback lifecycle: idle → planning → loading → playing/paused/buffering → replanning → stopping → stopped. Any active state may enter a terminal failure. Only one coordinator owns the current plan. An engine callback or network response with an older generation cannot mutate the active state.

- Start retry: retain the original encoded request bytes and attempt ID for an identical retry; a changed intent gets the protocol-appropriate new request identity.
- Intent change: audio/subtitle/quality/output selection goes through the provider policy. Direct local track selection remains possible when the current plan explicitly permits it.
- Recovery: bound attempts, retain opaque server attempt keys, and stop if no distinct permitted route remains. A repeated terminal result is not a cue to retry indefinitely.
- Stop: enqueue the final source progress and provider stop in order, once per session. Window close, item end and profile switch may race; duplicate UI signals do not create duplicate stop ownership. Network delivery is best effort with bounded retries and visible diagnostics.
- Endpoint switch: preserve the same server/account identity, re-resolve resources using the new endpoint and discard stale in-flight requests. Never forward credentials to an unrelated origin just because a redirect was returned.

## Required contract tests

| Case | Expected behavior |
| --- | --- |
| Same remote user/item ID on Jellyfin and Silo | Distinct session, credential and cache keys |
| Same server reached through LAN and public endpoint | Same saved account, item identity, playback preference and personal state |
| Profile switches while search is loading | The old response is discarded; no old artwork or results are published |
| Two requests receive an expired-token response | One refresh occurs; each request retries at most within its policy |
| Silo start returns terminal HTTP 201 | Terminal UI; no engine load and no forced Jellyfin fallback |
| Source start 120 s, stream origin/offset 116 s, player start 4 s | Start engine at 4 s; engine position 14 s reports source position 130 s |
| Remux plan has an open seek window | Seek intent triggers reanchor; engine duration does not replace full source duration |
| Subtitle inventory has an undeliverable bitmap entry | Preserve its identity/ordinal; later tracks do not shift index |
| Replan turns subtitles off after an ASS artifact | Clear the previous subtitle artifact and selection |
| Player closes while a replan is pending | Stop the owned session; discard the late replacement plan |
| Duplicate end/close events | One logical final progress/stop sequence |
| Backward seek into an already auto-skipped intro | Respect the deliberate seek; do not repeat the automatic skip |
| Interrupted migration after creating the identity map | Resume idempotently; keep old records and recoverable sign-in state |
| New Mac app cannot read old Keychain credentials | Show sign-in; do not erase old app data or copy plaintext credentials |

Use protocol fixtures and a deterministic HTTP test server for these tests. Actual playback/image quality and server-side progress confirmation remain separate hardware/live-server gates.

## First four commits to implement

1. **Domain and fixtures:** identity, catalog/playback types and pure timeline/seek tests. Compile on iOS, tvOS and macOS without either server SDK leaking into domain code.
2. **Jellyfin adapter:** wrap existing catalog/detail/marker and playback paths; migrate one library/detail/player flow end to end while existing screens continue using their current adapter where necessary.
3. **Session/storage bridge:** add identity migration, scoped credentials, cancellation and generation checks; prove old Jellyfin sign-in and endpoint switching still work.
4. **Silo contract adapter:** capability/auth/profile DTOs plus start/replan decision fixtures and timeline/track mapping. Enable a real Silo connection only when the catalog-to-playback flow passes its live gate.

The native app can consume the first working Jellyfin path after commits 2–3. Full Silo parity remains the phased work in its integration plan; these foundation commits do not claim that parity.

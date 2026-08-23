# Swiftfin Enhanced AltStore distribution

This fork publishes unsigned iOS builds for AltStore Classic. AltStore signs the app for the installing Apple ID, so the repository does not store Apple certificates, provisioning profiles, account credentials, or signing secrets.

## Source URL

Add this URL in AltStore Classic:

```text
https://raw.githubusercontent.com/Asion001/Swiftfin/main/altstore-source.json
```

AltStore PAL cannot use this source because PAL requires Apple-notarized alternative-distribution packages rather than ordinary IPA files.

## Automation

- `Sync Jellyfin Upstream` checks `jellyfin/Swiftfin` every day and on manual dispatch. It merges and pushes only when Git reports no conflicts. A conflict leaves `main` unchanged, fails the workflow, and creates or updates an issue when repository issues are enabled.
- `Enhanced Player CI` tests pull requests, the pinned Anime4KMetal revision, the AltStore source generator, and Swiftfin's enhancement tests.
- `Publish AltStore Release` runs for every non-source-only push to `main`. It repeats the release-blocking tests, creates an unsigned device IPA with the separate `dev.asion.swiftfin.enhanced` bundle identifier, publishes a GitHub release, and prepends the verified release metadata to `altstore-source.json`.

The source updater reads version and privacy information from the built app, calculates the IPA size and SHA-256 checksum, retains the newest 20 releases, and refuses bundle-identifier or metadata mismatches.

## Update behavior

AltStore treats the first entry in the app's `versions` array as the newest release. Each successful build receives a calendar version and a numeric timestamp build number. AltStore Classic periodically refreshes the source and offers the newer build; free Apple accounts must still refresh installed applications every seven days through AltServer.

The CI IPA deliberately has no special entitlements. In particular, Wi-Fi SSID detection is excluded because free Apple development signing does not support Swiftfin's Wi-Fi-information entitlement. Jellyfin connections and Anime4K Metal playback do not require that entitlement.

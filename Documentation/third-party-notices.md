# Third-Party Notices

Swiftfin Enhanced no longer bundles Anime4KMetal or Anime4K shader code. Its
real-time scaling path uses Apple system frameworks (`MetalFX`, `Metal`, and
`Core Image`) supplied by iOS, iPadOS, and macOS. Mac Catalyst uses Core
Image's Lanczos scaler because MetalFX is not exposed to Catalyst apps.

The notices for Swiftfin's other dependencies remain available from their
respective packages and license files in the source tree.

# Native Mac design direction

Status: catalog redesign implemented; remaining flows below are planned. Updated 2026-09-13.

## Product intent

Make a personal media library easy to recognize, browse and resume on a MacBook. Native windows, keyboard navigation, selection and menus should feel familiar; artwork supplies the visual character. Jellyfin and Silo should share user-facing concepts without exposing protocol details in ordinary navigation.

## First design pass

The initial three-column browser devoted almost half the window to an empty detail pane. Film rows lacked artwork, and account actions were available only through Settings. The redesign provides:

- A compact native library sidebar with account actions at the bottom.
- A responsive 2:3 poster grid, readable titles/years, and visible selection.
- Folder controls that navigate directly, without an extra detail step.
- An optional native inspector with poster, title, runtime and overview. Browsing uses the content area until details are requested.
- Toolbar search with Command-F and native Settings/refresh shortcuts. Search clears obsolete selection; failed detail requests offer retry.
- System colors, typography and focus behavior. Missing artwork uses a semantic film icon instead of invented poster content.

Artwork remains scoped to the account/server, avoids authentication in URLs, and clears its bounded memory cache on sign-out. The generated test poster is explicitly fixture content; production uses server artwork.

## Next screens

1. **Home and resume:** genuine continue-watching progress, recent additions and next episodes. Keep a few useful sections; avoid a decorative hero that delays browsing.
2. **Movie/series details:** clear Resume/Play only when a usable playback plan exists. Put version/quality choices beside playback and organize seasons/episodes with watched/resume state. Use a dedicated route when series content outgrows the inspector.
3. **Player:** a separate native window with standard fullscreen, keyboard shortcuts and accessible controls. Put subtitles, audio and upscaling in an inspector; keep statistics directly reachable. Restore fill consistently.
4. **Servers:** a server/account switcher that preserves each viewing scope. Jellyfin/Silo capabilities determine available actions. Route attempts and protocol diagnostics belong in an advanced view.
5. **Accessibility and density:** verify keyboard-only use, VoiceOver, both system appearances, high contrast, long titles, large libraries and minimum window widths. Add poster/list options only when both are fully usable.

## Validation limits

The native preview was visually inspected using loopback Jellyfin fixtures for login, artwork, search, selection, folders and Settings. The inspector was checked at a 960-pixel window width; Command-F and singular search counts were verified. Stopping the fixture produced an actionable detail error, and restarting it followed by Try Again restored details and cleared the error. This is not a completed player or full accessibility audit. Real-server playback, account persistence and native Silo parity remain separate gates in the implementation plans.

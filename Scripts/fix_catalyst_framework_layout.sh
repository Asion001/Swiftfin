#!/bin/bash
set -euo pipefail

# Mac Catalyst does not use shallow bundles, so every framework embedded in the
# app has to carry the versioned macOS layout: the binary and resources under
# `Versions/A`, with `Versions/Current` and top-level symlinks pointing at them.
# Xcode checks this while embedding and fails the build outright:
#
#   error: Framework .../Libmpv.framework contains Info.plist, expected
#   Versions/Current/Resources/Info.plist since the platform does not use
#   shallow bundles
#
# Several of MPVKit's Catalyst slices ship flat rather than versioned. Only
# Libmpv is embedded in the app, so it is the one the build stops on, but the
# repair is applied to every slice it finds. Rewriting them in place before the
# build is what lets the Mac app build at all.
#
# The real fix belongs in the MPVKit fork that produces the xcframeworks; delete
# this once its Catalyst slices are packaged like their versioned siblings.
#
# Rewriting an already-versioned framework is skipped, so this is safe to run
# repeatedly over a warm derived data directory.

search_root="${1:-}"

if [ -z "$search_root" ]; then
  echo "usage: $0 <search-root>" >&2
  exit 2
fi

if [ ! -d "$search_root" ]; then
  echo "error: no such directory: $search_root" >&2
  exit 2
fi

repaired=0

while IFS= read -r -d '' framework; do
  name="$(basename "$framework" .framework)"

  # Already versioned, or not a framework bundle this can rewrite.
  if [ -d "$framework/Versions" ] || [ ! -f "$framework/Info.plist" ] || [ ! -f "$framework/$name" ]; then
    continue
  fi

  versions="$framework/Versions/A"
  mkdir -p "$versions/Resources"

  mv "$framework/$name" "$versions/$name"
  mv "$framework/Info.plist" "$versions/Resources/Info.plist"

  for directory in Headers Modules PrivateHeaders; do
    if [ -d "$framework/$directory" ]; then
      mv "$framework/$directory" "$versions/$directory"
    fi
  done

  ln -s A "$framework/Versions/Current"
  ln -s "Versions/Current/$name" "$framework/$name"
  ln -s "Versions/Current/Resources" "$framework/Resources"

  for directory in Headers Modules PrivateHeaders; do
    if [ -d "$versions/$directory" ]; then
      ln -s "Versions/Current/$directory" "$framework/$directory"
    fi
  done

  echo "Repaired Catalyst framework layout: $framework"
  repaired=$((repaired + 1))
done < <(find "$search_root" -type d -path '*maccatalyst*' -name '*.framework' -print0)

echo "Repaired $repaired framework(s)."

#!/bin/bash
set -euo pipefail

# Runner images can contain different Homebrew formula versions. Use the same
# formatter for lint jobs and Xcode's format phase, including release builds.
version=0.63.0
checksum=28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f
formatter_dir="${RUNNER_TEMP:?}/swiftformat-$version"
mkdir -p "$formatter_dir"
curl --fail --location --retry 3 \
  "https://github.com/nicklockwood/SwiftFormat/releases/download/$version/swiftformat.zip" \
  --output "$formatter_dir/swiftformat.zip"
printf '%s  %s\n' "$checksum" "$formatter_dir/swiftformat.zip" | shasum -a 256 --check
unzip -oq "$formatter_dir/swiftformat.zip" -d "$formatter_dir"
chmod +x "$formatter_dir/swiftformat"
test "$("$formatter_dir/swiftformat" --version)" = "$version"
echo "$formatter_dir" >> "${GITHUB_PATH:?}"
echo "SWIFTFORMAT_BIN_DIR=$formatter_dir" >> "${GITHUB_ENV:?}"
"$formatter_dir/swiftformat" --version

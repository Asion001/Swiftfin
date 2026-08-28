#!/bin/bash

# Builds Swiftfin Enhanced and installs it on a paired iOS device, skipping the
# release pipeline entirely. See Documentation/device-testing.md.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_identifier="${SWIFTFIN_BUNDLE_IDENTIFIER:-dev.asion.swiftfin.enhanced}"
configuration="Debug"
derived_data="${SWIFTFIN_DERIVED_DATA:-$repository_root/build/DeviceDeploy}"
device_query="${SWIFTFIN_DEVICE:-}"
launch=true
list_only=false

usage() {
    printf '%s\n' \
        "Usage: Scripts/deploy_device.sh [options]" \
        "" \
        "  --device <name|udid>  Device to install on. Defaults to \$SWIFTFIN_DEVICE," \
        "                        or the only connected device." \
        "  --release             Build the Release configuration instead of Debug." \
        "  --bundle-id <id>      Bundle identifier to build with." \
        "                        Defaults to $bundle_identifier, matching the" \
        "                        AltStore build so it upgrades in place." \
        "  --no-launch           Install without launching the app." \
        "  --list                List paired devices and exit." \
        "  -h, --help            Show this message."
}

while [ $# -gt 0 ]; do
    case "$1" in
        --device)
            device_query="${2:-}"
            shift 2
            ;;
        --release)
            configuration="Release"
            shift
            ;;
        --bundle-id)
            bundle_identifier="${2:-}"
            shift 2
            ;;
        --no-launch)
            launch=false
            shift
            ;;
        --list)
            list_only=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "this script builds with Xcode and only runs on macOS"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found; install Xcode and its command line tools"

# Devices are listed rather than filtered by xcodebuild so that a missing or
# ambiguous device is reported here instead of as a destination resolution
# failure several minutes into a build.
list_devices() {
    local output
    output="$(mktemp)"
    xcrun devicectl list devices --quiet --json-output "$output" >/dev/null
    python3 - "$output" "$device_query" <<'PYTHON'
import json
import sys

path, query = sys.argv[1], sys.argv[2].lower()

with open(path) as stream:
    payload = json.load(stream)

rows = []
for device in payload.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    if not str(hardware.get("platform", "")).lower().startswith("ios"):
        continue

    name = device.get("deviceProperties", {}).get("name", "unnamed")
    udid = hardware.get("udid", "")
    state = device.get("connectionProperties", {}).get("tunnelState", "unknown")

    if query and query not in name.lower() and query != udid.lower():
        continue

    rows.append((name, udid, state))

# A device that is reachable now sorts first, so an unqualified run picks the
# one actually plugged in or on the network rather than a stale pairing.
rows.sort(key=lambda row: (row[2] != "connected", row[0]))

for row in rows:
    print("\t".join(row))
PYTHON
    rm -f "$output"
}

devices="$(list_devices)"

if [ "$list_only" = true ]; then
    if [ -z "$devices" ]; then
        printf 'No paired iOS devices.\n'
    else
        printf 'name\tudid\tstate\n%s\n' "$devices"
    fi
    exit 0
fi

if [ -z "$devices" ]; then
    if [ -n "$device_query" ]; then
        fail "no paired iOS device matches '$device_query'; run with --list to see them"
    fi
    fail "no paired iOS devices; pair one in Xcode (Window > Devices and Simulators)"
fi

connected_count="$(printf '%s\n' "$devices" | awk -F '\t' '$3 == "connected"' | wc -l | tr -d ' ')"

if [ -z "$device_query" ] && [ "$connected_count" -gt 1 ]; then
    printf 'More than one device is connected. Pass --device:\n\n%s\n' "$devices" >&2
    exit 1
fi

device_line="$(printf '%s\n' "$devices" | head -n 1)"
device_name="$(printf '%s' "$device_line" | cut -f 1)"
device_udid="$(printf '%s' "$device_line" | cut -f 2)"
device_state="$(printf '%s' "$device_line" | cut -f 3)"

[ -n "$device_udid" ] || fail "could not read a device identifier from devicectl"

if [ "$device_state" != "connected" ]; then
    printf 'warning: %s is %s; the install will fail if it cannot be reached\n' \
        "$device_name" "$device_state" >&2
fi

[ -d "$repository_root/Carthage/Build" ] || fail \
    "Carthage dependencies are missing; run: brew bundle --file Brewfile && carthage update --use-xcframeworks"

# Signing is the one thing this cannot supply for you, and Xcode reports its
# absence as a generic build failure a long way from the cause.
team_file="$repository_root/XcodeConfig/DevelopmentTeam.xcconfig"
if [ ! -f "$team_file" ] || ! grep -q '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Za-z0-9]' "$team_file"; then
    fail "set your team in XcodeConfig/DevelopmentTeam.xcconfig, e.g. 'DEVELOPMENT_TEAM = ABCDE12345'"
fi

printf 'Building %s for %s (%s)\n' "$configuration" "$device_name" "$bundle_identifier"
started_at="$(date +%s)"

xcodebuild \
    -quiet \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -project "$repository_root/Swiftfin.xcodeproj" \
    -scheme Swiftfin \
    -configuration "$configuration" \
    -destination "platform=iOS,id=$device_udid" \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_identifier" \
    build

app="$derived_data/Build/Products/$configuration-iphoneos/Swiftfin iOS.app"
[ -d "$app" ] || fail "expected an app bundle at $app"

printf 'Installing\n'

if ! xcrun devicectl device install app --device "$device_udid" "$app"; then
    printf '%s\n' \
        "" \
        "If the install was refused because the app is already installed:" \
        "iOS only replaces an app when the new signature comes from the same" \
        "team. An AltStore build signed with a different Apple ID has to be" \
        "deleted from the device first, or pass --bundle-id to install this" \
        "build alongside it." >&2
    exit 1
fi

if [ "$launch" = true ]; then
    xcrun devicectl device process launch \
        --device "$device_udid" \
        --terminate-existing \
        "$bundle_identifier" >/dev/null
fi

printf 'Done in %ss\n' "$(( $(date +%s) - started_at ))"

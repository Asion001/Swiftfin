#!/bin/bash

set -euo pipefail

repository="${SWIFTFIN_REPOSITORY:-Asion001/Swiftfin}"
asset_name="Swiftfin-Enhanced-Mac.zip"
checksum_name="$asset_name.sha256"
bundle_identifier="dev.asion.swiftfin.enhanced.macos"
app_name="Swiftfin Enhanced.app"
install_directory="${SWIFTFIN_INSTALL_DIRECTORY:-$HOME/Applications}"
target_app="$install_directory/$app_name"
support_directory="${SWIFTFIN_SUPPORT_DIRECTORY:-$HOME/Library/Application Support/Swiftfin Enhanced}"
receipt="$support_directory/release.sha256"
launch_agent="$HOME/Library/LaunchAgents/dev.asion.swiftfin-enhanced.updater.plist"
updater_script="$support_directory/update.sh"
enable_updates=false
check_only=false

usage() {
    printf '%s\n' \
        "Usage: $0 [--enable-auto-update] [--check] [--remove-auto-update]" \
        "" \
        "  --enable-auto-update  Install a daily background update check." \
        "  --check               Update only when a newer release is available." \
        "  --remove-auto-update  Remove the background update check."
}

remove_auto_update() {
    launchctl bootout "gui/$UID" "$launch_agent" >/dev/null 2>&1 || true
    rm -f "$launch_agent" "$updater_script"
    printf 'Automatic updates removed.\n'
}

install_auto_update() {
    mkdir -p "$support_directory" "$HOME/Library/LaunchAgents"
    curl --fail --location --silent --show-error \
        "https://raw.githubusercontent.com/$repository/main/Scripts/install_macos.sh" \
        --output "$updater_script"
    chmod 755 "$updater_script"

    temporary_plist="$launch_agent.tmp.$$"
    cat > "$temporary_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.asion.swiftfin-enhanced.updater</string>
    <key>ProgramArguments</key>
    <array>
        <string>$updater_script</string>
        <string>--check</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>86400</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$support_directory/update.log</string>
    <key>StandardErrorPath</key>
    <string>$support_directory/update.log</string>
</dict>
</plist>
PLIST
    plutil -lint "$temporary_plist" >/dev/null
    mv "$temporary_plist" "$launch_agent"
    launchctl bootout "gui/$UID" "$launch_agent" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID" "$launch_agent"
    printf 'Automatic daily updates enabled.\n'
}

for argument in "$@"; do
    case "$argument" in
        --enable-auto-update)
            enable_updates=true
            ;;
        --check)
            check_only=true
            ;;
        --remove-auto-update)
            remove_auto_update
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/swiftfin-enhanced.XXXXXX")"
staging_app="$install_directory/.Swiftfin Enhanced.new.$$"
backup_app="$install_directory/.Swiftfin Enhanced.previous.$$"

cleanup() {
    if [[ -d "$backup_app" && ! -d "$target_app" ]]; then
        mv "$backup_app" "$target_app"
    fi
    rm -rf "$temporary_directory" "$staging_app"
}
trap cleanup EXIT

release_base="${SWIFTFIN_RELEASE_BASE:-https://github.com/$repository/releases/latest/download}"
curl --fail --location --silent --show-error "$release_base/$asset_name" --output "$temporary_directory/$asset_name"
curl --fail --location --silent --show-error "$release_base/$checksum_name" --output "$temporary_directory/$checksum_name"

expected_checksum="$(awk 'NR == 1 { print $1 }' "$temporary_directory/$checksum_name")"
actual_checksum="$(shasum -a 256 "$temporary_directory/$asset_name" | awk '{ print $1 }')"
if [[ ! "$expected_checksum" =~ ^[0-9a-fA-F]{64}$ ]] || [[ "$actual_checksum" != "$expected_checksum" ]]; then
    printf 'The downloaded Mac package failed SHA-256 verification.\n' >&2
    exit 65
fi

if [[ "$check_only" == true && -f "$receipt" ]] && [[ "$(cat "$receipt")" == "$actual_checksum" ]]; then
    exit 0
fi

if [[ -d "$target_app" ]] && pgrep -f "$target_app/Contents/MacOS/" >/dev/null 2>&1; then
    if [[ "$check_only" == true ]]; then
        printf 'Swiftfin Enhanced is running; the update will be retried later.\n'
        exit 0
    fi
    printf 'Quit Swiftfin Enhanced and run the installer again.\n' >&2
    exit 69
fi

ditto -x -k "$temporary_directory/$asset_name" "$temporary_directory/unpacked"
downloaded_app="$temporary_directory/unpacked/$app_name"
if [[ ! -d "$downloaded_app" ]]; then
    printf 'The release archive does not contain %s.\n' "$app_name" >&2
    exit 65
fi

downloaded_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$downloaded_app/Contents/Info.plist")"
if [[ "$downloaded_identifier" != "$bundle_identifier" ]]; then
    printf 'Unexpected app identifier: %s\n' "$downloaded_identifier" >&2
    exit 65
fi
codesign --verify --deep --strict "$downloaded_app"

mkdir -p "$install_directory" "$support_directory"
ditto --norsrc --noextattr "$downloaded_app" "$staging_app"
xattr -dr com.apple.quarantine "$staging_app" 2>/dev/null || true

if [[ -d "$target_app" ]]; then
    mv "$target_app" "$backup_app"
fi
if ! mv "$staging_app" "$target_app"; then
    if [[ -d "$backup_app" ]]; then
        mv "$backup_app" "$target_app"
    fi
    printf 'Could not install the app. The previous copy was restored.\n' >&2
    exit 74
fi
rm -rf "$backup_app"
printf '%s\n' "$actual_checksum" > "$receipt"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target_app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$target_app/Contents/Info.plist")"
printf 'Installed Swiftfin Enhanced %s (%s) in %s\n' "$version" "$build" "$target_app"

if [[ "$enable_updates" == true ]]; then
    install_auto_update
fi

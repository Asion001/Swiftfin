#!/usr/bin/env python3

"""Add a verified IPA release to Swiftfin Enhanced's AltStore source."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
from pathlib import Path
from urllib.parse import urlparse


VERSION_PATTERN = re.compile(r"^[0-9]+(?:\.[0-9]+){1,2}$")


def privacy_permissions(info: dict[str, object]) -> dict[str, str]:
    return {
        key: value
        for key, value in sorted(info.items())
        if key.endswith("UsageDescription") and isinstance(value, str)
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def update_source(
    source_path: Path,
    ipa_path: Path,
    info_plist_path: Path,
    release_date: str,
    download_url: str,
    description: str,
    max_versions: int = 20,
) -> dict[str, object]:
    source = json.loads(source_path.read_text(encoding="utf-8"))
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)

    bundle_identifier = info.get("CFBundleIdentifier")
    version = info.get("CFBundleShortVersionString")
    build_version = info.get("CFBundleVersion")
    minimum_os_version = info.get("MinimumOSVersion")

    if not isinstance(bundle_identifier, str) or not bundle_identifier:
        raise ValueError("Info.plist is missing CFBundleIdentifier")
    if not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
        raise ValueError(f"invalid CFBundleShortVersionString: {version!r}")
    if not isinstance(build_version, str) or not build_version.isdigit():
        raise ValueError(f"invalid CFBundleVersion: {build_version!r}")
    if not isinstance(minimum_os_version, str) or not VERSION_PATTERN.fullmatch(
        minimum_os_version
    ):
        raise ValueError(f"invalid MinimumOSVersion: {minimum_os_version!r}")
    if urlparse(download_url).scheme != "https":
        raise ValueError("download URL must use HTTPS")
    if not ipa_path.is_file() or ipa_path.stat().st_size == 0:
        raise ValueError("IPA is missing or empty")
    if max_versions < 1:
        raise ValueError("max versions must be positive")

    apps = source.get("apps")
    if not isinstance(apps, list) or len(apps) != 1 or not isinstance(apps[0], dict):
        raise ValueError("source must contain exactly one app")

    app = apps[0]
    if app.get("bundleIdentifier") != bundle_identifier:
        raise ValueError(
            "source bundle identifier does not match built app: "
            f"{app.get('bundleIdentifier')!r} != {bundle_identifier!r}"
        )

    release = {
        "version": version,
        "buildVersion": build_version,
        "marketingVersion": f"Enhanced {version} ({build_version})",
        "date": release_date,
        "localizedDescription": description,
        "downloadURL": download_url,
        "size": ipa_path.stat().st_size,
        "sha256": sha256(ipa_path),
        "minOSVersion": minimum_os_version,
    }

    versions = app.get("versions", [])
    if not isinstance(versions, list):
        raise ValueError("app versions must be a list")
    versions = [
        item
        for item in versions
        if not (
            isinstance(item, dict)
            and item.get("version") == version
            and item.get("buildVersion") == build_version
        )
    ]
    app["versions"] = [release, *versions][:max_versions]
    app["appPermissions"] = {
        "entitlements": [],
        "privacy": privacy_permissions(info),
    }

    source_path.write_text(
        json.dumps(source, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return source


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--info-plist", required=True, type=Path)
    parser.add_argument("--date", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--max-versions", default=20, type=int)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    update_source(
        source_path=arguments.source,
        ipa_path=arguments.ipa,
        info_plist_path=arguments.info_plist,
        release_date=arguments.date,
        download_url=arguments.download_url,
        description=arguments.description,
        max_versions=arguments.max_versions,
    )


if __name__ == "__main__":
    main()

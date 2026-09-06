#!/usr/bin/env python3
"""Build the AppKit render gate from an MPVKit `make build platform=macos` tree."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shlex
import subprocess


def output(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpvkit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="Destination .app bundle")
    args = parser.parse_args()
    checkout = args.mpvkit.resolve()
    dist = checkout / "dist"
    destination = args.output.resolve()
    if destination.suffix != ".app":
        parser.error("--output must end in .app")
    libraries = sorted(dist.glob("*/macos/thin/arm64/lib"))
    header = dist / "libmpv/macos/thin/arm64/include/mpv/client.h"
    if not header.is_file():
        parser.error("Build MPVKit with platform=macos before running this script")
    env = os.environ.copy()
    env["PKG_CONFIG_PATH"] = ":".join(str(path / "pkgconfig") for path in libraries)
    # System zlib/xml2 metadata may come from pkg-config's SDK search path.
    # Reject non-system dynamic dependencies after linking below.
    flags = shlex.split(output("pkg-config", "--libs", "--static", "mpv", env=env))
    flags = [flag for flag in flags if flag != "-pthread"]
    binary = destination / "Contents/MacOS/SwiftfinMPVRenderCheck"
    binary.parent.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parents[1] / "NativeMac/MPVRenderCheck/main.swift"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "5", "-target", "arm64-apple-macos15.0",
        "-sdk", output("xcrun", "--sdk", "macosx", "--show-sdk-path"),
        "-module-cache-path", str(destination.parent / "native-mpv-module-cache"),
        "-import-objc-header", str(header), str(source), "-o", str(binary),
        *[f"-L{path}" for path in libraries], *flags, "-lc++",
    ], check=True)
    linked = output("otool", "-L", str(binary))
    for line in linked.splitlines()[1:]:
        dependency = line.strip().split(" (", 1)[0]
        if not dependency.startswith(("/System/Library/", "/usr/lib/")):
            raise RuntimeError(f"Non-system dynamic dependency must be bundled: {dependency}")
    with (destination / "Contents/Info.plist").open("wb") as file:
        plistlib.dump({
            "CFBundleExecutable": binary.name,
            "CFBundleIdentifier": "org.swiftfin.NativeMPVRenderCheck",
            "CFBundleName": "Swiftfin MPV Render Check",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "15.0",
            "NSHighResolutionCapable": True,
        }, file)
    resources = destination / "Contents/Resources"
    resources.mkdir(exist_ok=True)
    (resources / "build-provenance.json").write_text(json.dumps({
        "mpvkitRevision": output("git", "-C", str(checkout), "rev-parse", "HEAD"),
        "mpvkitChanges": output("git", "-C", str(checkout), "status", "--porcelain"),
        "architecture": output("lipo", "-archs", str(binary)),
        "linkedLibraries": linked,
    }, indent=2) + "\n")
    subprocess.run(["codesign", "--force", "--sign", "-", str(destination)], check=True)
    print(destination)


if __name__ == "__main__":
    main()

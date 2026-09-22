#!/usr/bin/env python3
"""Build and locally sign the native macOS catalog application."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scratch-path", type=Path, default=Path("/tmp/swiftfin-native-build"))
    args = parser.parse_args()
    destination = args.output.resolve()
    if destination.suffix != ".app":
        parser.error("--output must end in .app")
    root = Path(__file__).resolve().parents[1]
    build = ["swift", "build", "--package-path", str(root), "--scratch-path", str(args.scratch_path.resolve()),
             "--configuration", "release", "--arch", "arm64"]
    subprocess.run([*build, "--product", "SwiftfinNative"], check=True)
    binaries = Path(subprocess.check_output([*build, "--show-bin-path"], text=True).strip())
    executable = destination / "Contents/MacOS/SwiftfinNative"
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binaries / "SwiftfinNative", executable)
    resources = destination / "Contents/Resources"
    resources.mkdir(parents=True, exist_ok=True)
    name = "SwiftfinMediaServerCore_SwiftfinNative.bundle"
    shutil.copytree(binaries / name, resources / name, dirs_exist_ok=True)
    with (destination / "Contents/Info.plist").open("wb") as file:
        plistlib.dump({
            "CFBundleExecutable": "SwiftfinNative", "CFBundleIdentifier": "org.swiftfin.Native",
            "CFBundleName": "Swiftfin Native", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1",
            "LSMinimumSystemVersion": "15.0", "NSHighResolutionCapable": True,
            "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True, "NSAllowsLocalNetworking": True},
        }, file)
    subprocess.run(["codesign", "--force", "--sign", "-", str(destination)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(destination)], check=True)
    print(destination)


if __name__ == "__main__":
    main()

import json
import plistlib
import tempfile
import unittest
from pathlib import Path

from Scripts.update_altstore_source import update_source


class UpdateAltStoreSourceTests(unittest.TestCase):
    def test_prepends_verified_release_and_declares_privacy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_path = root / "source.json"
            ipa_path = root / "Swiftfin.ipa"
            plist_path = root / "Info.plist"
            source_path.write_text(
                json.dumps(
                    {
                        "name": "Swiftfin Enhanced",
                        "apps": [
                            {
                                "bundleIdentifier": "dev.asion.swiftfin.enhanced",
                                "versions": [
                                    {"version": "2026.8.22", "buildVersion": "1"}
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            ipa_path.write_bytes(b"test ipa")
            with plist_path.open("wb") as stream:
                plistlib.dump(
                    {
                        "CFBundleIdentifier": "dev.asion.swiftfin.enhanced",
                        "CFBundleShortVersionString": "2026.8.23",
                        "CFBundleVersion": "123",
                        "MinimumOSVersion": "18.6",
                        "NSLocalNetworkUsageDescription": "Connect to Jellyfin.",
                        "Unrelated": "ignored",
                    },
                    stream,
                )

            result = update_source(
                source_path=source_path,
                ipa_path=ipa_path,
                info_plist_path=plist_path,
                release_date="2026-08-23T12:00:00Z",
                download_url="https://example.com/Swiftfin.ipa",
                description="Automated build",
            )

            app = result["apps"][0]
            release = app["versions"][0]
            self.assertEqual(release["version"], "2026.8.23")
            self.assertEqual(release["buildVersion"], "123")
            self.assertEqual(release["minOSVersion"], "18.6")
            self.assertEqual(release["size"], len(b"test ipa"))
            self.assertEqual(len(release["sha256"]), 64)
            self.assertEqual(
                app["appPermissions"],
                {
                    "entitlements": [],
                    "privacy": {
                        "NSLocalNetworkUsageDescription": "Connect to Jellyfin."
                    },
                },
            )

    def test_rejects_bundle_identifier_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_path = root / "source.json"
            ipa_path = root / "Swiftfin.ipa"
            plist_path = root / "Info.plist"
            source_path.write_text(
                json.dumps(
                    {
                        "apps": [
                            {
                                "bundleIdentifier": "dev.asion.swiftfin.enhanced",
                                "versions": [],
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            ipa_path.write_bytes(b"test ipa")
            with plist_path.open("wb") as stream:
                plistlib.dump(
                    {
                        "CFBundleIdentifier": "wrong.bundle",
                        "CFBundleShortVersionString": "2026.8.23",
                        "CFBundleVersion": "123",
                        "MinimumOSVersion": "18.6",
                    },
                    stream,
                )

            with self.assertRaisesRegex(ValueError, "bundle identifier"):
                update_source(
                    source_path=source_path,
                    ipa_path=ipa_path,
                    info_plist_path=plist_path,
                    release_date="2026-08-23T12:00:00Z",
                    download_url="https://example.com/Swiftfin.ipa",
                    description="Automated build",
                )


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Reject unsuitable update archives and mismatched release identities."""
import importlib.util
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
import warnings
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("prepare_update", ROOT / "scripts/prepare-update.py")
updates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updates)


class UpdateDistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.archive = Path(self.temporary.name) / "update.zip"
        settings = updates.sparkle.config()
        self.info = dict(CFBundleIdentifier="com.nanami.fuyi", CFBundleShortVersionString="0.2.1",
                         CFBundleVersion="14", SUFeedURL=settings["feed_url"], SUPublicEDKey=settings["public_key"],
                         SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True)

    def write(self, info=None, additional=None):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("译芽.app/Contents/Info.plist", plistlib.dumps(info or self.info))
            if additional:
                for path, data in additional:
                    archive.writestr(path, data)
        return self.archive

    def test_valid_app_only_archive(self):
        self.assertEqual(updates.archive_info(self.write()), self.info)

    def test_ditto_utf8_names_without_zip_utf8_flag(self):
        class DittoZipInfo(zipfile.ZipInfo):
            def _encodeFilenameFlags(self):
                return self.filename.encode("utf-8"), self.flag_bits & ~0x800
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr(DittoZipInfo("译芽.app/Contents/Info.plist"), plistlib.dumps(self.info))
        self.assertEqual(updates.archive_info(self.archive), self.info)

    def test_both_release_tag_forms(self):
        for tag in ["v0.2.1", "v0.2.1-build-14"]:
            updates.validate_tag(tag, self.info)

    def test_wrong_tag_version_or_build(self):
        for tag in ["v0.2.0", "v0.2.1-build-13", "latest", "v0.2.1/other"]:
            with self.assertRaises(ValueError):
                updates.validate_tag(tag, self.info)

    def test_wrong_bundle_identity(self):
        with self.assertRaises(ValueError):
            updates.archive_info(self.write(dict(self.info, CFBundleIdentifier="another.application")))

    def test_wrong_feed_or_public_key(self):
        for field in ["SUFeedURL", "SUPublicEDKey"]:
            with self.assertRaises(ValueError):
                updates.archive_info(self.write(dict(self.info, **{field: "different"})))

    def test_signature_checks_must_be_enabled(self):
        for field in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"]:
            with self.assertRaises(ValueError):
                updates.archive_info(self.write(dict(self.info, **{field: False})))

    def test_invalid_build(self):
        for build in ["0", "-1", "1.2", "commit-sha", ""]:
            with self.assertRaises(ValueError):
                updates.archive_info(self.write(dict(self.info, CFBundleVersion=build)))

    def test_forbidden_credentials(self):
        for name in ["api-key.json", "ed25519.key"]:
            with self.assertRaises(ValueError):
                updates.archive_info(self.write(additional=[("译芽.app/Contents/Resources/" + name, b"SYNTHETIC")]))

    def test_path_traversal_and_absolute_path(self):
        for name in ["译芽.app/../../escape", "/outside"]:
            with self.assertRaises(ValueError):
                updates.archive_info(self.write(additional=[(name, b"fixture")]))

    def test_escaping_symlink(self):
        for target in ["/outside", "../../../../outside"]:
            entry = zipfile.ZipInfo("译芽.app/Contents/Frameworks/link")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            with self.assertRaises(ValueError):
                updates.archive_info(self.write(additional=[(entry, target.encode())]))

    def test_internal_framework_symlink(self):
        entry = zipfile.ZipInfo("译芽.app/Contents/Frameworks/Sparkle.framework/Versions/Current")
        entry.create_system = 3
        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.assertEqual(updates.archive_info(self.write(additional=[(entry, b"B")])), self.info)

    def test_first_install_archive_is_not_an_update(self):
        with self.assertRaises(ValueError):
            updates.archive_info(self.write(additional=[("先读我.txt", b"guide")]))

    def test_duplicate_metadata(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with self.assertRaises(ValueError):
                updates.archive_info(self.write(additional=[("译芽.app/Contents/Info.plist", plistlib.dumps(self.info))]))

    def test_published_history_keeps_original_downloads_and_notes(self):
        namespace = updates.NAMESPACE
        published = ET.ElementTree(ET.fromstring(f'''<rss xmlns:sparkle="{namespace}"><channel>
          <item><sparkle:version>12</sparkle:version><description>Old release notes</description>
            <enclosure url="https://example.com/old-release/old.zip" sparkle:edSignature="OLD"/></item>
        </channel></rss>'''))
        feed = Path(self.temporary.name) / "appcast.xml"
        feed.write_text(f'''<rss xmlns:sparkle="{namespace}"><channel>
          <item><sparkle:version>14</sparkle:version><enclosure url="https://example.com/new-release/new.zip"/>
            <sparkle:deltas><enclosure sparkle:deltaFrom="12" url="published.delta"/>
              <enclosure sparkle:deltaFrom="13" url="draft.delta"/></sparkle:deltas></item>
          <item><sparkle:version>12</sparkle:version><description>Rewritten</description>
            <enclosure url="https://example.com/new-release/old.zip"/></item>
          <item><sparkle:version>13</sparkle:version><enclosure url="draft.zip"/></item>
        </channel></rss>''')
        updates.preserve_published_history(feed, published, "14")
        items = ET.parse(feed).findall("./channel/item")
        self.assertEqual([i.findtext(f"{{{namespace}}}version") for i in items], ["14", "12"])
        self.assertEqual(items[1].findtext("description"), "Old release notes")
        self.assertEqual(items[1].find("enclosure").attrib,
                         {"url": "https://example.com/old-release/old.zip", f"{{{namespace}}}edSignature": "OLD"})
        deltas = items[0].findall(f"{{{namespace}}}deltas/enclosure")
        self.assertEqual([e.get(f"{{{namespace}}}deltaFrom") for e in deltas], ["12"])

    def test_empty_online_history_excludes_unpublished_delta_bases(self):
        namespace = updates.NAMESPACE
        feed = Path(self.temporary.name) / "appcast.xml"
        feed.write_text(f'''<rss xmlns:sparkle="{namespace}"><channel><item>
          <sparkle:version>14</sparkle:version><enclosure url="new.zip"/>
          <sparkle:deltas><enclosure sparkle:deltaFrom="13" url="draft.delta"/></sparkle:deltas>
        </item></channel></rss>''')
        updates.preserve_published_history(feed, ET.ElementTree(ET.fromstring("<rss><channel/></rss>")), "14")
        self.assertIsNone(ET.parse(feed).find(f"./channel/item/{{{namespace}}}deltas"))

    def test_generated_feed_requires_unique_current_build(self):
        feed = Path(self.temporary.name) / "appcast.xml"
        for content in ["<rss><channel/></rss>",
                        f'<rss xmlns:sparkle="{updates.NAMESPACE}"><channel>' +
                        '<item><sparkle:version>14</sparkle:version></item>' * 2 + '</channel></rss>']:
            feed.write_text(content)
            with self.assertRaises(ValueError):
                updates.preserve_published_history(feed, ET.ElementTree(ET.fromstring("<rss><channel/></rss>")), "14")


if __name__ == "__main__":
    unittest.main(verbosity=2)

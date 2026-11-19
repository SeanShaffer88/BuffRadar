"""Exercise the real packager on isolated source trees, without release credentials."""

import os
import runpy
import shutil
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main
from zipfile import ZipFile, ZipInfo


PACK = runpy.run_path(str(Path(__file__).with_name("package.py")))
VERIFY = runpy.run_path(str(Path(__file__).with_name("checkpackage.py")))
PROJECT = Path(__file__).resolve().parent.parent


class PackageTest(TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory(prefix="br-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        self.version, self.sources = PACK["source_manifest"](PROJECT)
        # Recreate a canonical independent checkout in reverse entry order.
        for name, source in reversed(list(self.sources.items())):
            base = "editions/forever" if name in PACK["EDITION"] else "BuffRadar"
            path = self.project / base / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, path)
        self.toc = self.project / "editions/forever/BuffRadar.toc"
        self.archive = self.project / f"dist/BuffRadar-{self.version}-Forever.zip"
        self.sums = self.archive.with_name("SHA256SUMS.txt")

    def test_repeat_is_byte_identical_after_mtime_changes_and_verifies(self):
        PACK["pack"](self.project, f"v{self.version}")
        first, digest = self.archive.read_bytes(), self.sums.read_bytes()
        for path in self.project.rglob("*.lua"):
            os.utime(path, (1_600_000_000, 1_600_000_000))
        PACK["pack"](self.project)
        self.assertEqual(first, self.archive.read_bytes())
        self.assertEqual(digest, self.sums.read_bytes())
        VERIFY["check_package"](self.archive, self.project)
        self.sums.write_bytes(b"not the computed digest\n")
        with self.assertRaisesRegex(ValueError, "does not match"):
            VERIFY["check_package"](self.archive, self.project)

    def test_mismatched_tag_and_wrong_or_duplicate_metadata_fail_before_build(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            PACK["pack"](self.project, "v0.0.0")
        self.assertFalse(self.archive.exists())
        toc = self.toc.read_text(encoding="utf-8")
        self.toc.write_text(toc.replace("## Interface: 16001", "## Interface: 120105"), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "valid Interface"):
            PACK["pack"](self.project)
        self.toc.write_text(toc + "\n## Version: 0.0.0\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "valid Version"):
            PACK["pack"](self.project)
        self.assertFalse(self.archive.exists())

    def test_undeclared_source_and_escaped_toc_path_fail(self):
        extra = self.project / "BuffRadar" / "extra.txt"
        extra.write_text("not part of the addon", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "inventory"):
            PACK["source_manifest"](self.project)
        extra.unlink()
        with self.toc.open("a", encoding="utf-8") as stream:
            stream.write("\n../outside.lua\n")
        with self.assertRaisesRegex(ValueError, "must match"):
            PACK["source_manifest"](self.project)

    def test_cross_platform_path_aliases_fail(self):
        for name in ("../x.lua", "/x.lua", "x//z.lua", "dir/./foo.lua", "dir\\foo.lua", "C:/foo.lua", "x/COM1.lua", "x /foo.lua"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                PACK["canonical"](name)
        image = self.project / "BuffRadar/Media/ICON.PNG"
        if image.exists():  # Case-insensitive volume already prevents the duplicate.
            return
        image.write_bytes(b"different icon")
        with self.assertRaisesRegex(ValueError, "Case-folded duplicate"):
            PACK["source_manifest"](self.project)

    def test_source_and_binding_drift_are_rejected(self):
        source = self.project / "BuffRadar/Bindings.xml"
        PACK["pack"](self.project)
        source.write_bytes(source.read_bytes().replace(b"BUFFRADAR_MUTE", b"BUFFRADAR_OTHER"))
        with self.assertRaisesRegex(ValueError, "Stale package entry Bindings.xml"):
            VERIFY["check_package"](self.archive, self.project)
        PACK["pack"](self.project)
        with self.assertRaisesRegex(ValueError, "Invalid binding definition"):
            VERIFY["check_package"](self.archive, self.project)

    def test_verifier_refuses_archive_metadata_and_directory_aliases(self):
        PACK["pack"](self.project)
        with ZipFile(self.archive, "a") as edited:
            edited.comment = b"unverified metadata"
        with self.assertRaisesRegex(ValueError, "deterministic archive"):
            VERIFY["load_archive"](self.archive, require_deterministic=True)
        with ZipFile(self.archive, "w") as edited:
            edited.writestr(ZipInfo("BuffRadar/Media/icon.png"), b"icon")
            edited.writestr(ZipInfo("BuffRadar/MEDIA/logo.png"), b"logo")
        with self.assertRaisesRegex(ValueError, "Case-folded duplicate"):
            VERIFY["load_archive"](self.archive)

    def test_symlink_is_never_packaged(self):
        path = self.project / "BuffRadar" / "linked.lua"
        try:
            path.symlink_to(self.toc)
        except (NotImplementedError, OSError) as exc:
            self.skipTest(f"Symbolic links unavailable: {exc}")
        with self.assertRaisesRegex(ValueError, "non-linked"):
            PACK["source_manifest"](self.project)
        path.unlink()
        directory = self.project / "BuffRadar" / "linked-dir"
        directory.symlink_to(self.toc.parent, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "non-linked"):
            PACK["source_manifest"](self.project)


if __name__ == "__main__":
    main(verbosity=2)

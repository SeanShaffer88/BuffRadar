#!/usr/bin/env python3
"""Build the supported Forever ZIP from a shared, confined source manifest."""

import argparse
import hashlib
import os
import re
import stat
import tempfile
from pathlib import Path, PurePosixPath
from zipfile import ZIP_STORED, ZipFile, ZipInfo

EDITION = {"BuffRadar.toc", "README.md", "CHANGELOG.md", "DESCRIPTION.md", "FEATURES.md"}
SHARED_ASSETS = {"Bindings.xml", "LICENSE", "Media/icon.png", "Media/logo.png", "Media/droplet.ogg"}
INTERFACE = "16001"
FIXED_DATE = (1980, 1, 1, 0, 0, 0)
FIXED_MODE = 0o100644 << 16
WINDOWS_DEVICE = re.compile(r"^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)", re.IGNORECASE)


def metadata(toc, field, pattern):
    values = re.findall(rf"^## {field}:[ \t]*(.*)$", toc, re.MULTILINE)
    if len(values) != 1 or re.fullmatch(pattern, values[0].strip()) is None:
        raise ValueError(f"Expected exactly one valid {field} in the Forever TOC")
    return values[0].strip()


def canonical(name):
    path = PurePosixPath(name)
    if not path.parts or path.as_posix() != name or path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Invalid package path: {name!r}")
    for part in path.parts:
        if part.endswith((" ", ".")) or WINDOWS_DEVICE.match(part) or re.search(r'[\\<>:"|?*\x00-\x1f]', part):
            raise ValueError(f"Non-portable package path: {name!r}")
    return path


def register_path(name, seen):
    """Reject spelling aliases for both members and their directory components."""
    path = canonical(name)
    for part in (path, *path.parents):
        spelling = part.as_posix()
        previous = seen.setdefault(spelling.casefold(), spelling)
        if previous != spelling:
            raise ValueError(f"Case-folded duplicate: {previous}, {spelling}")
    return path


def checked(path, directory=False):
    info = path.lstat()
    linked = stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT
    valid = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    if linked or not valid:
        raise ValueError(f"Not a regular, non-linked {'directory' if directory else 'file'}: {path}")
    return path


def source_files(base):
    """Walk only real directories; never follow symlinks, junctions or special files."""
    for path in base.iterdir():
        if path.is_dir():
            yield from source_files(checked(path, directory=True))
        else:
            yield checked(path)


def source_manifest(project):
    shared = checked(project / "BuffRadar", directory=True)
    edition = checked(checked(project / "editions", directory=True) / "forever", directory=True)
    toc_path = checked(edition / "BuffRadar.toc")
    toc = toc_path.read_text(encoding="utf-8-sig")
    metadata(toc, "Interface", INTERFACE)
    version = metadata(toc, "Version", r"[0-9]+\.[0-9]+\.[0-9]+")
    manifest = {}
    for path in source_files(shared):
        name = path.relative_to(shared).as_posix()
        if name not in EDITION:
            manifest[name] = path
    manifest.update({name: checked(edition / name) for name in EDITION})
    seen = {}
    for name in sorted(manifest):
        register_path(name, seen)
    load_order = [line.strip().replace("\\", "/") for line in toc.splitlines()
                  if line.strip() and not line.lstrip().startswith("#")]
    lua = {name for name in manifest if name.endswith(".lua")}
    if not lua or len(load_order) != len(lua) or set(load_order) != lua:
        raise ValueError("Packaged Lua must match the Forever TOC exactly")
    expected = lua | SHARED_ASSETS | EDITION
    if set(manifest) != expected:
        raise ValueError(f"Package inventory differs from the declared assets: {sorted(set(manifest) ^ expected)}")
    return version, dict(sorted(manifest.items()))


def checksum(archive, filename=None):
    with archive.open("rb") as source:
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(64 * 1024), b""):
            digest.update(chunk)
    return f"{digest.hexdigest()}  {filename or archive.name}\n"


def pack(project, expected_tag=None):
    version, files = source_manifest(project)
    if expected_tag is not None and expected_tag != f"v{version}":
        raise ValueError(f"Tag {expected_tag!r} does not match the Forever TOC version v{version}")
    dist = project / "dist"
    dist.mkdir(exist_ok=True)
    checked(dist, directory=True)
    filename = f"BuffRadar-{version}-Forever.zip"
    with tempfile.TemporaryDirectory(prefix=".package-", dir=dist) as directory:
        staging = Path(directory)
        archive = staging / filename
        with ZipFile(archive, "w", compression=ZIP_STORED) as package:
            # Stored ZIPs avoid different zlib versions changing compressed bytes.
            # Explicit metadata (date, permission bits, OS) ignores source mtimes.
            for name, source in files.items():
                entry = ZipInfo(f"BuffRadar/{name}", FIXED_DATE)
                entry.create_system, entry.external_attr = 3, FIXED_MODE
                package.writestr(entry, source.read_bytes())
        sums = checksum(archive)
        (staging / "SHA256SUMS.txt").write_bytes(sums.encode("ascii"))
        os.replace(archive, dist / filename)
        os.replace(staging / "SHA256SUMS.txt", dist / "SHA256SUMS.txt")
    print(sums, end="")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--tag", help="require the exact version tag (vX.Y.Z) before writing files")
    options = cli.parse_args()
    try:
        pack(Path(__file__).resolve().parent.parent, options.tag)
    except (OSError, ValueError) as exc:
        cli.exit(1, f"Forever package failed: {exc}\n")

#!/usr/bin/env python3
"""Patch a freshly built desktop config into the live one, three-way.

    sync-desktop.py <new> <base> <live> <backup>

<new>   the tree install-desktop.sh just built from the repo
<base>  the tree that was built and applied last time
<live>  ~/.config

Only what changed upstream since <base> is touched. A file the repo did not
change is left exactly as it is on disk, so local edits and everything the
desktop generates for itself (palettes, wallpaper state) survive. A file that
changed on both sides is merged with `git merge-file`; when that conflicts the
upstream version wins and the local one is kept under <backup>.

Prints one "<action>\t<path>" line per touched file:
updated, merged, conflict, removed, kept.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def listing(root: Path) -> set[Path]:
    if not root.is_dir():
        return set()
    return {p.relative_to(root) for p in root.rglob("*") if p.is_symlink() or p.is_file()}


def read(path: Path) -> bytes | None:
    if path.is_symlink():
        return b"\0link:" + os.readlink(path).encode()
    if path.is_file():
        return path.read_bytes()
    return None


def install(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=".sync-")
    os.close(fd)
    os.unlink(tmp)
    shutil.copy2(src, tmp, follow_symlinks=False)
    os.replace(tmp, dest)


def write(data: bytes, mode_from: Path, dest: Path) -> None:
    fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=".sync-")
    with os.fdopen(fd, "wb") as fh:
        fh.write(data)
    os.chmod(tmp, mode_from.stat().st_mode & 0o777)
    os.replace(tmp, dest)


def merge(live: Path, base: Path, new: Path) -> bytes | None:
    for p in (live, base, new):
        if p.is_symlink() or b"\0" in p.read_bytes():
            return None
    res = subprocess.run(
        ["git", "merge-file", "-p", str(live), str(base), str(new)],
        capture_output=True,
    )
    return res.stdout if res.returncode == 0 else None


def main(new: Path, base: Path, live: Path, backup: Path) -> int:
    new_files, base_files = listing(new), listing(base)

    for rel in sorted(new_files):
        n, b, cur = read(new / rel), read(base / rel), read(live / rel)
        if n == b or cur == n:
            continue
        if cur is None or cur == b:
            install(new / rel, live / rel)
            print(f"updated\t{rel}")
            continue
        merged = merge(live / rel, base / rel, new / rel) if b is not None else None
        if merged is not None:
            write(merged, new / rel, live / rel)
            print(f"merged\t{rel}")
            continue
        (backup / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(live / rel, backup / rel, follow_symlinks=False)
        install(new / rel, live / rel)
        print(f"conflict\t{rel}")

    for rel in sorted(base_files - new_files):
        cur = read(live / rel)
        if cur is None:
            continue
        if cur == read(base / rel):
            (live / rel).unlink()
            print(f"removed\t{rel}")
        else:
            print(f"kept\t{rel}")

    return 0


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("usage: sync-desktop.py <new> <base> <live> <backup>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(*(Path(a) for a in sys.argv[1:])))

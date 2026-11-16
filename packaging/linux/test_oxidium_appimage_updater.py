#!/usr/bin/env python3
"""Isolated tests for the Oxidium AppImage update bridge."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
UPDATER = ROOT / "packaging/linux/oxidium-appimage-updater.sh"
ASSET = "oxidium-linux-x86_64.AppImage"


def write_executable(path: Path, text: str) -> None:
    path.write_text(text)
    path.chmod(0o755)


def fixture(current: str, latest: str, *, bad_checksum: bool = False):
    temp = tempfile.TemporaryDirectory(prefix="oxidium-updater-test-")
    root = Path(temp.name)
    self_image = root / "Oxidium.AppImage"
    self_image.write_text("old-appimage\n")
    self_image.chmod(0o755)

    current_bin = root / "current-launcher"
    write_executable(
        current_bin,
        f"""#!/bin/sh
printf '%s\\n' 'horizon-launcher {current}'
""",
    )

    marker = root / "launched"
    release = root / "release"
    release.mkdir()
    candidate = release / ASSET
    write_executable(
        candidate,
        f"""#!/bin/sh
if [ "\${{1:-}}" = "--appimage-extract-and-run" ] && [ "\${{2:-}}" = "--version" ]; then
  printf '%s\\n' 'horizon-launcher {latest}'
  exit 0
fi
printf '%s\\n' launched > "\$OXIDIUM_TEST_MARKER"
""",
    )

    digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
    if bad_checksum:
        digest = "0" * 64
    (release / "SHA256SUMS").write_text(f"{digest}  {ASSET}\n")
    metadata = root / "release.json"
    metadata.write_text('{"tag_name":"launcher@' + latest + '"}\n')

    env = os.environ.copy()
    env.update(
        {
            "APPIMAGE": str(self_image),
            "OXIDIUM_LAUNCHER_BIN": str(current_bin),
            "OXIDIUM_UPDATE_API": metadata.as_uri(),
            "OXIDIUM_UPDATE_BASE_URL": release.as_uri(),
            "OXIDIUM_UPDATE_LOG": str(root / "update.log"),
            "OXIDIUM_TEST_MARKER": str(marker),
            "HOME": str(root / "home"),
        }
    )
    return temp, root, self_image, candidate, marker, env


def run(current: str, latest: str, *, bad_checksum: bool = False):
    temp, root, self_image, candidate, marker, env = fixture(
        current, latest, bad_checksum=bad_checksum
    )
    before = self_image.read_bytes()
    candidate_bytes = candidate.read_bytes()
    completed = subprocess.run(
        [str(UPDATER)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    return temp, root, self_image, marker, before, candidate_bytes, completed


def test_upgrade() -> None:
    temp, root, self_image, marker, before, candidate, completed = run("0.2.28", "0.2.29")
    try:
        assert completed.returncode == 0, completed.stderr
        assert self_image.read_bytes() == candidate
        assert (Path(str(self_image) + ".previous")).read_bytes() == before
        assert marker.read_text().strip() == "launched"
        assert "installed 0.2.29" in (root / "update.log").read_text()
    finally:
        temp.cleanup()


def test_downgrade_is_refused() -> None:
    temp, root, self_image, marker, before, _candidate, completed = run("0.2.28", "0.2.12")
    try:
        assert completed.returncode == 0, completed.stderr
        assert self_image.read_bytes() == before
        assert not Path(str(self_image) + ".previous").exists()
        assert not marker.exists()
    finally:
        temp.cleanup()


def test_bad_checksum_is_refused() -> None:
    temp, root, self_image, marker, before, _candidate, completed = run(
        "0.2.28", "0.2.29", bad_checksum=True
    )
    try:
        assert completed.returncode == 0, completed.stderr
        assert self_image.read_bytes() == before
        assert not Path(str(self_image) + ".previous").exists()
        assert not marker.exists()
        assert "checksum mismatch" in (root / "update.log").read_text()
    finally:
        temp.cleanup()


if __name__ == "__main__":
    test_upgrade()
    test_downgrade_is_refused()
    test_bad_checksum_is_refused()
    print("Oxidium AppImage updater tests passed")

import hashlib
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / "manifest.json").read_text())["version"]
NAME = f"super-t-{VERSION}"
ARCHIVE = ROOT / "dist" / f"{NAME}.tar.gz"


class DistributionTests(unittest.TestCase):
    def test_archive_is_reproducible(self):
        before = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
        subprocess.run(["bash", "-c", "umask 077; make dist"], cwd=ROOT, check=True, capture_output=True)
        self.assertEqual(before, hashlib.sha256(ARCHIVE.read_bytes()).hexdigest())
        checksum = ARCHIVE.with_suffix(".gz.sha256").read_text().split()[0]
        self.assertEqual(before, checksum)

    def test_archive_contains_runnable_plugin(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            with tarfile.open(ARCHIVE) as archive:
                for member in archive.getmembers():
                    path = Path(member.name)
                    self.assertEqual(path.parts[0], NAME)
                    self.assertNotIn("..", path.parts)
                    self.assertFalse(member.issym() or member.islnk())
                    self.assertNotIn(".git", path.parts)
                    self.assertNotIn("__pycache__", path.parts)
                    self.assertFalse(path.suffix in (".pyc", ".pyo"))
                archive.extractall(target)
            plugin = target / NAME
            for pattern in ("*.qml", "*.js", "*.py", "*.sh"):
                for source in ROOT.glob(pattern):
                    self.assertEqual(source.read_bytes(), (plugin / source.name).read_bytes())
            subprocess.run(["python3", "-B", "scripts/validate.py"], cwd=plugin, check=True, capture_output=True)
            notes = target / "notes"
            notes.mkdir()
            (notes / "inbox.md").write_text("# Inbox\n- [ ] Open\n- [x] Done\n")
            result = subprocess.run(
                ["bash", str(plugin / "scan.sh"), str(notes)],
                cwd=plugin, check=True, capture_output=True, text=True,
                env={**os.environ, "XDG_STATE_HOME": str(target / "state"), "PYTHONDONTWRITEBYTECODE": "1"},
            )
            data = json.loads(result.stdout)
            self.assertTrue(data["ok"])
            self.assertEqual(data["lists"][0]["total"], 2)
            self.assertEqual(data["lists"][0]["done"], 1)

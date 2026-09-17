import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENTRY_POINTS = {
    "bar": "bar",
    "bar-widget": "barWidget",
    "menu": "menu",
    "overlay": "overlay",
    "panel": "panel",
    "service": "service",
}


def validate(root, tag=None):
    manifest = json.loads((root / "manifest.json").read_text())
    if type(manifest.get("schemaVersion")) is not int or manifest["schemaVersion"] != 1:
        raise ValueError("schemaVersion must be 1")
    for field in ("id", "name", "version", "author", "description"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ValueError(f"Missing manifest {field}")
    plugin_id = manifest["id"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", plugin_id) or ".." in plugin_id or plugin_id.startswith("omarchy."):
        raise ValueError("Invalid or reserved plugin id")
    version = manifest["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?", version):
        raise ValueError("Use a semantic release version")
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} must match v{version}")
    kinds = manifest.get("kinds")
    entries = manifest.get("entryPoints")
    if not isinstance(kinds, list) or not kinds or not all(isinstance(kind, str) and kind in ENTRY_POINTS for kind in kinds):
        raise ValueError("Declare supported plugin kinds")
    if not isinstance(entries, dict):
        raise ValueError("entryPoints must be an object")
    for kind in kinds:
        if ENTRY_POINTS[kind] not in entries:
            raise ValueError(f"Missing entry point for {kind}")
    for entry in entries.values():
        if not isinstance(entry, str) or not entry or ".." in entry or "\n" in entry or Path(entry).is_absolute():
            raise ValueError(f"Unsafe entry point: {entry!r}")
        if not (root / entry).is_file():
            raise ValueError(f"Missing entry point: {entry}")
    section = manifest.get("barWidget", {}).get("defaultSection", "right")
    if section not in ("left", "center", "right"):
        raise ValueError("Invalid default bar section")
    for path in root.rglob("*"):
        if ".git" not in path.relative_to(root).parts and path.is_symlink():
            raise ValueError(f"Symlink inside plugin: {path}")
    for name in ("README.md", "LICENSE", "CHANGELOG.md"):
        if not (root / name).is_file():
            raise ValueError(f"Missing {name}")
    changelog = (root / "CHANGELOG.md").read_text()
    heading = f"## {version}\n"
    if heading not in changelog:
        raise ValueError(f"Missing changelog for {version}")
    notes = changelog.split(heading, 1)[1].split("\n## ", 1)[0].strip()
    if not notes:
        raise ValueError("Release notes must not be empty")
    return notes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--tag")
    parser.add_argument("--notes", type=Path)
    args = parser.parse_args()
    try:
        notes = validate(args.root.resolve(), args.tag)
        if args.notes:
            args.notes.write_text(notes + "\n")
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"Validation failed: {error}\n")
    print("Manifest, entry points and release metadata are valid")


if __name__ == "__main__":
    main()

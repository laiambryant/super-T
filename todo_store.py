from __future__ import annotations

import json
import os
import stat
import tempfile
from typing import Any

from todo_tags import tags_info
from todo_tasks import counts


class StoreError(RuntimeError):
    def __init__(self, message: str, code: str = "io_error") -> None:
        super().__init__(message)
        self.code = code


def _has_controls(value: str) -> bool:
    return any(ord(char) < 32 or ord(char) == 127 for char in value)


def _inside(root: str, path: str) -> bool:
    try:
        return os.path.commonpath((root, path)) == root
    except ValueError:
        return False


def canonical_directory(value: object, *, require_exists: bool) -> str:
    if not isinstance(value, str):
        raise StoreError("Todo directory must be an absolute path", "invalid_directory")
    if _has_controls(value):
        raise StoreError("Todo directory cannot contain control characters", "invalid_directory")
    raw = value.strip()
    if not raw:
        raise StoreError("No todo directory configured", "invalid_directory")
    if raw.startswith("~"):
        if raw == "~" or raw.startswith("~/"):
            raw = os.path.expanduser(raw)
        else:
            raise StoreError("Only ~ or ~/ paths are supported for the todo directory", "invalid_directory")
    if not os.path.isabs(raw):
        raise StoreError("Todo directory must be an absolute path", "invalid_directory")
    directory = os.path.realpath(os.path.normpath(raw))
    if os.path.exists(directory):
        if not os.path.isdir(directory):
            raise StoreError("Todo directory is a file, not a directory", "invalid_directory")
        if require_exists and not os.access(directory, os.R_OK | os.X_OK):
            raise StoreError("Todo directory is not readable", "unreadable_directory")
    elif require_exists:
        raise StoreError("Todo directory does not exist", "missing_directory")
    return directory


def resolve_markdown_path(directory: str, value: object, *, require_exists: bool = True) -> str:
    if not isinstance(value, str) or not value or _has_controls(value):
        raise StoreError("List path is invalid", "invalid_path")
    if not os.path.isabs(value):
        raise StoreError("List path must be absolute", "invalid_path")
    path = os.path.realpath(os.path.normpath(value))
    if path == directory or not _inside(directory, path):
        raise StoreError("List path is outside the configured todo directory", "invalid_path")
    if not path.lower().endswith(".md"):
        raise StoreError("List path must point to a Markdown file", "invalid_path")
    if require_exists:
        try:
            metadata = os.lstat(value)
        except FileNotFoundError as error:
            raise StoreError("List no longer exists", "missing_list") from error
        except OSError as error:
            raise StoreError("Could not read the selected list", "io_error") from error
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise StoreError("List must be a regular Markdown file", "invalid_path")
    return path


def read_text(path: str) -> str:
    try:
        with open(path, "rb") as handle:
            raw = handle.read()
    except FileNotFoundError as error:
        raise StoreError("List no longer exists", "missing_list") from error
    except OSError as error:
        raise StoreError("Could not read the selected list", "io_error") from error
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise StoreError("Lists must be valid UTF-8 Markdown files", "invalid_encoding") from error


def scan_lists(directory: str) -> list[dict[str, Any]]:
    lists: list[dict[str, Any]] = []
    failures: list[OSError] = []

    def walk_error(error: OSError) -> None:
        failures.append(error)

    for current, dirs, files in os.walk(directory, topdown=True, followlinks=False, onerror=walk_error):
        dirs[:] = sorted(name for name in dirs if not os.path.islink(os.path.join(current, name)))
        for filename in sorted(files):
            if not filename.lower().endswith(".md"):
                continue
            candidate = os.path.join(current, filename)
            if os.path.islink(candidate):
                continue
            try:
                path = resolve_markdown_path(directory, candidate)
                text = read_text(path)
            except StoreError as error:
                raise StoreError(str(error), error.code) from error
            total, done = counts(text)
            tags, tags_error = tags_info(text)
            relative = os.path.relpath(path, directory).replace(os.sep, "/")
            entry: dict[str, Any] = {
                "path": path,
                "name": relative[:-3],
                "total": total,
                "done": done,
                "tags": tags,
            }
            if tags_error:
                entry["tagsError"] = tags_error
            lists.append(entry)
    if failures:
        raise StoreError("Todo directory contains an unreadable folder", "unreadable_directory")
    return sorted(lists, key=lambda entry: entry["name"])


def _list_name(value: object) -> tuple[list[str], str]:
    if not isinstance(value, str):
        raise StoreError("Name is empty", "invalid_name")
    name = value.strip()
    if name.lower().endswith(".md"):
        name = name[:-3]
    if not name:
        raise StoreError("Name is empty", "invalid_name")
    if _has_controls(name) or name.startswith("~") or os.path.isabs(name) or "\\" in name:
        raise StoreError("Name must be relative to the todo directory", "invalid_name")
    pieces = name.split("/")
    if any(not piece for piece in pieces):
        raise StoreError("Name must be relative to the todo directory", "invalid_name")
    if any(piece in (".", "..") for piece in pieces):
        raise StoreError("Name must not contain . or .. segments", "invalid_name")
    return pieces, name


def _ensure_directory(directory: str) -> None:
    try:
        os.makedirs(directory, mode=0o700, exist_ok=True)
    except OSError as error:
        raise StoreError("Could not create the todo directory", "io_error") from error
    if not os.path.isdir(directory) or not os.access(directory, os.W_OK | os.X_OK):
        raise StoreError("Todo directory is not writable", "unwritable_directory")


def _safe_parent(directory: str, pieces: list[str]) -> str:
    current = directory
    for piece in pieces:
        current = os.path.join(current, piece)
        try:
            metadata = os.lstat(current)
        except FileNotFoundError:
            try:
                os.mkdir(current)
            except OSError as error:
                raise StoreError("Could not create " + current, "io_error") from error
            continue
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise StoreError("List name crosses a symbolic link or file", "invalid_name")
        if not _inside(directory, os.path.realpath(current)):
            raise StoreError("List name escapes the todo directory", "invalid_name")
    return current


def create_list(directory: str, name: object) -> tuple[str, str, str]:
    pieces, clean_name = _list_name(name)
    _ensure_directory(directory)
    parent = _safe_parent(directory, pieces[:-1])
    path = os.path.join(parent, pieces[-1] + ".md")
    if not _inside(directory, os.path.realpath(parent)):
        raise StoreError("List name escapes the todo directory", "invalid_name")
    text = "# " + pieces[-1] + "\n\n"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags, 0o666)
    except FileExistsError as error:
        raise StoreError(clean_name + " already exists", "already_exists") from error
    except OSError as error:
        raise StoreError("Could not write " + path, "io_error") from error
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(text.encode("utf-8"))
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as error:
        try:
            os.unlink(path)
        except OSError:
            pass
        raise StoreError("Could not write " + path, "io_error") from error
    return path, clean_name, text


def _fsync_directory(directory: str) -> None:
    try:
        descriptor = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError:
        pass


def atomic_write(path: str, text: str) -> None:
    try:
        metadata = os.lstat(path)
    except OSError as error:
        raise StoreError("List no longer exists", "missing_list") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise StoreError("List must be a regular Markdown file", "invalid_path")
    parent = os.path.dirname(path)
    try:
        descriptor, temporary = tempfile.mkstemp(prefix=".super-t-", dir=parent)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(text.encode("utf-8"))
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, stat.S_IMODE(metadata.st_mode))
        os.replace(temporary, path)
        _fsync_directory(parent)
    except OSError as error:
        try:
            if "temporary" in locals() and os.path.exists(temporary):
                os.unlink(temporary)
        except OSError:
            pass
        raise StoreError("Could not save " + path, "io_error") from error


def atomic_json(path: str, value: object) -> None:
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    if os.path.lexists(path) and os.path.islink(path):
        raise StoreError("Plugin state path is a symbolic link", "state_error")
    encoded = (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    descriptor, temporary = tempfile.mkstemp(prefix=".super-t-", dir=parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        _fsync_directory(parent)
    except OSError as error:
        try:
            if os.path.exists(temporary):
                os.unlink(temporary)
        except OSError:
            pass
        raise StoreError("Could not save plugin state", "state_error") from error

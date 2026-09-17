from __future__ import annotations

import json
import os
from typing import Any

from todo_store import StoreError, atomic_json, atomic_write, read_text


def _error(message: str) -> StoreError:
    return StoreError(message, "recovery_required")


def _load_json(path: str) -> Any:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _load_journal(path: str) -> tuple[list[dict[str, str]], dict[str, Any] | None]:
    try:
        value = _load_json(path)
        changes = value["changes"]
        state = value.get("state")
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise _error("A previous save journal is unreadable; no files were changed") from error
    if not isinstance(changes, list) or not changes:
        raise _error("A previous save journal is invalid; no files were changed")
    for change in changes:
        if not isinstance(change, dict) or not all(isinstance(change.get(key), str) for key in ("path", "before", "after")):
            raise _error("A previous save journal is invalid; no files were changed")
    if state is not None:
        required = ("path", "before", "after", "beforeExists")
        if (not isinstance(state, dict) or not all(key in state for key in required)
                or not isinstance(state["path"], str) or not isinstance(state["beforeExists"], bool)):
            raise _error("A previous save journal is invalid; no files were changed")
    return changes, state


def _document_states(changes: list[dict[str, str]]) -> list[str]:
    states: list[str] = []
    for change in changes:
        current = read_text(change["path"])
        if current == change["after"]:
            states.append("after")
        elif current == change["before"]:
            states.append("before")
        else:
            raise _error("A previous save conflicts with an external edit")
    return states


def _state_value(path: str) -> tuple[bool, Any]:
    if not os.path.exists(path):
        return False, None
    try:
        return True, _load_json(path)
    except (OSError, ValueError) as error:
        raise _error("A previous save has an unreadable state file") from error


def _state_status(state: dict[str, Any] | None) -> str | None:
    if state is None:
        return None
    exists, current = _state_value(state["path"])
    before_matches = (not exists and not state["beforeExists"]) or (exists and current == state["before"])
    if before_matches:
        return "before"
    if exists and current == state["after"]:
        return "after"
    raise _error("A previous save conflicts with todo state")


def _restore_state(state: dict[str, Any] | None, target: str) -> None:
    if state is None:
        return
    current = _state_status(state)
    if current == target:
        return
    if target == "after":
        atomic_json(state["path"], state["after"])
        return
    if state["beforeExists"]:
        atomic_json(state["path"], state["before"])
        return
    try:
        os.unlink(state["path"])
    except FileNotFoundError:
        pass
    except OSError as error:
        raise StoreError("Could not restore todo state", "state_error") from error


def _clear_journal(path: str) -> None:
    try:
        os.unlink(path)
    except OSError as error:
        raise StoreError("Could not clear the completed save journal", "state_error") from error


def recover_transaction(journal_path: str) -> None:
    if not os.path.exists(journal_path):
        return
    changes, state = _load_journal(journal_path)
    documents = _document_states(changes)
    _state_status(state)
    if all(item == "after" for item in documents):
        _restore_state(state, "after")
    elif all(item == "before" for item in documents):
        _restore_state(state, "before")
    else:
        for change, status in zip(changes, documents):
            if status == "after":
                atomic_write(change["path"], change["before"])
        _restore_state(state, "before")
    _clear_journal(journal_path)


def apply_transaction(
    changes: list[dict[str, str]], journal_path: str,
    *, state_path: str | None = None, state_before: Any = None,
    state_after: Any = None, state_before_exists: bool = False,
) -> None:
    recover_transaction(journal_path)
    paths: set[str] = set()
    for change in changes:
        path = change["path"]
        if path in paths:
            raise StoreError("A save cannot write the same list twice", "invalid_request")
        paths.add(path)
        if read_text(path) != change["before"]:
            raise StoreError("The list changed on disk; reload it before saving", "conflict")
    state = None
    if state_path is not None:
        state = {"path": state_path, "before": state_before, "after": state_after,
                 "beforeExists": state_before_exists}
    atomic_json(journal_path, {"version": 2, "changes": changes, "state": state})
    try:
        written = []
        for change in changes:

            for previous in written:
                if read_text(previous["path"]) != previous["after"]:
                    raise StoreError("A saved list changed during the operation", "conflict")
            if read_text(change["path"]) != change["before"]:
                raise StoreError("The list changed on disk; reload it before saving", "conflict")
            atomic_write(change["path"], change["after"])
            written.append(change)
        if state is not None:
            atomic_json(state_path, state_after)
    except StoreError:
        recover_transaction(journal_path)
        raise
    _clear_journal(journal_path)

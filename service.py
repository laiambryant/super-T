#!/usr/bin/env python3

from __future__ import annotations

from contextlib import contextmanager
import json
import sys
from typing import Any, Iterator

from todo_state import (
    LockedState, StateError, add_undo, completion_change, find_undo, locked_state,
    move_tracked_event, normalize_position, reload_state, remap_events, remove_undo,
    save_position, save_state, state_copy, state_exists, summary, undo_completion,
    undo_event_refs,
)
from todo_store import (
    StoreError, canonical_directory, create_list, read_text, resolve_markdown_path,
    scan_lists,
)
from todo_tags import TagsError, replace_tags, tags_info
from todo_tasks import TaskError, parse_tasks, task_at_line
from todo_selection import edit_tasks, move_tasks
from todo_transaction import apply_transaction, recover_transaction


class RequestError(ValueError):
    def __init__(self, message: str, code: str = "invalid_request") -> None:
        super().__init__(message)
        self.code = code


def _string(request: dict[str, Any], key: str) -> str:
    value = request.get(key)
    if not isinstance(value, str):
        raise RequestError(key + " must be text")
    return value


def _line(value: object, label: str = "line") -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise RequestError(label + " must be a non-negative integer")
    return value


def _directory(request: dict[str, Any], exists: bool) -> str:
    return canonical_directory(request.get("dir"), require_exists=exists)


@contextmanager
def _state_for(directory: str) -> Iterator[LockedState]:
    with locked_state(directory) as locked:
        recover_transaction(locked.paths.journal)
        reload_state(locked, directory)
        yield locked


def _commit(
    locked: LockedState, changes: list[dict[str, str]], completion: dict[str, Any] | list[dict[str, Any]] | None,
    event_refs: list[dict[str, Any]] | None, state_before: dict[str, Any], state_before_exists: bool,
) -> str:
    token = add_undo(locked, changes, completion, event_refs)
    try:
        apply_transaction(
            changes, locked.paths.journal, state_path=locked.paths.data,
            state_before=state_before, state_after=locked.value, state_before_exists=state_before_exists,
        )
    except StoreError:
        reload_state(locked, locked.value["directory"])
        raise
    return token


def _completion(request: dict[str, Any], before_text: str, after_text: str) -> tuple[Any, Any, dict[str, Any]] | None:
    value = request.get("completion")
    if value is None:
        return None
    if not isinstance(value, dict) or not isinstance(value.get("checked"), bool):
        raise RequestError("completion must include a line and checked boolean", "invalid_completion")
    line = _line(value.get("line"), "completion line")
    before = task_at_line(before_text, line)
    after = task_at_line(after_text, line)
    if before is None or after is None:
        raise RequestError("Completion line no longer identifies a task", "invalid_completion")
    if after.checked != value["checked"] or before.checked == after.checked:
        raise RequestError("Completion does not match a checkbox transition", "invalid_completion")
    return before, after, {"line": line, "checked": after.checked}


def _identity(request: dict[str, Any]) -> dict[str, Any] | None:
    value = request.get("identity")
    if value is None:
        return None
    if not isinstance(value, dict) or value.get("kind") not in ("add", "delete", "edit", "toggle"):
        raise RequestError("identity kind is invalid")
    return {"kind": value["kind"], "line": _line(value.get("line"), "identity line")}


def _expected_current(directory: str, request: dict[str, Any]) -> tuple[str, str, str]:
    path = resolve_markdown_path(directory, request.get("path"))
    expected = _string(request, "expected")
    current = read_text(path)
    if current != expected:
        raise StoreError("The list changed on disk; reload it before saving", "conflict")
    return path, expected, current


def _scan(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory):
        return {"dir": directory, "lists": scan_lists(directory)}


def _read(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory):
        path = resolve_markdown_path(directory, request.get("path"))
        text = read_text(path)
        tags, tag_error = tags_info(text)
        reply: dict[str, Any] = {"path": path, "text": text, "tags": tags}
        if tag_error:
            reply["tagsError"] = tag_error
        return reply


def _create(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, False)
    with _state_for(directory):
        path, name, text = create_list(directory, request.get("name"))
        return {"path": path, "name": name, "text": text}


def _write(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory) as locked:
        path, expected, current = _expected_current(directory, request)
        text = _string(request, "text")
        completion = _completion(request, expected, text)
        if text == current:
            return {"path": path, "text": text, "undoToken": None, "completion": None}
        state_before = state_copy(locked)
        existed = state_exists(locked)
        refs = remap_events(locked, path, current, text, _identity(request))
        delta = completion_change(locked, path, completion[0], completion[1]) if completion else None
        changes = [{"path": path, "before": current, "after": text}]
        token = _commit(locked, changes, delta, refs, state_before, existed)
        result: dict[str, Any] = {"path": path, "text": text, "undoToken": token, "completion": None}
        if completion:
            result["completion"] = {"path": path, **completion[2]}
        return result


def _move(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory) as locked:
        source, _, current_source = _expected_current(directory, request)
        target = resolve_markdown_path(directory, request.get("target"))
        if target == source:
            raise RequestError("Choose a different destination list")
        target_expected = request.get("targetExpected")
        if target_expected is not None and not isinstance(target_expected, str):
            raise RequestError("targetExpected must be text")
        current_target = read_text(target)
        if target_expected is not None and current_target != target_expected:
            raise StoreError("The destination list changed on disk; reload it before moving", "conflict")
        lines = request["lines"] if "lines" in request else [_line(request.get("line"))]
        source_text, target_text, source_map, target_map, moved = move_tasks(current_source, lines, current_target)
        target_line = min(moved.values())
        state_before = state_copy(locked)
        existed = state_exists(locked)
        refs = remap_events(locked, target, current_target, target_text, {"kind": "mapping", "lines": target_map})
        inserted = {task.line: task for task in parse_tasks(target_text)}
        for task in parse_tasks(current_source):
            if task.line in moved:
                refs += move_tracked_event(locked, source, task, target, inserted[moved[task.line]])
        refs += remap_events(locked, source, current_source, source_text, {"kind": "mapping", "lines": source_map})

        changes = [
            {"path": target, "before": current_target, "after": target_text},
            {"path": source, "before": current_source, "after": source_text},
        ]
        token = _commit(locked, changes, None, refs, state_before, existed)
        return {"path": target, "text": target_text, "sourcePath": source,
                "sourceText": source_text, "line": target_line, "undoToken": token}


def _batch(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory) as locked:
        path, _, current = _expected_current(directory, request)
        text, mapping = edit_tasks(current, request.get("lines"), request.get("action"), request.get("bodies"))
        result = {"path": path, "text": text, "lineMapping": mapping}
        if text == current and all(old == new for old, new in mapping.items()):
            return {**result, "undoToken": None}
        state_before = state_copy(locked)
        existed = state_exists(locked)
        refs = remap_events(locked, path, current, text, {"kind": "mapping", "lines": mapping})
        deltas = []
        if request.get("action") == "toggle":
            after = {task.line: task for task in parse_tasks(text)}
            for task in parse_tasks(current):
                delta = completion_change(locked, path, task, after[task.line])
                if delta:
                    deltas.append(delta)
        token = _commit(locked, [{"path": path, "before": current, "after": text}],
                        deltas, refs, state_before, existed)
        return {**result, "undoToken": token}


def _tags(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory) as locked:
        path, _, current = _expected_current(directory, request)
        text, tags = replace_tags(current, request.get("tags"))
        if text == current:
            return {"path": path, "text": text, "tags": tags, "undoToken": None}
        state_before = state_copy(locked)
        existed = state_exists(locked)
        refs = remap_events(locked, path, current, text)
        token = _commit(locked, [{"path": path, "before": current, "after": text}], None, refs, state_before, existed)
        return {"path": path, "text": text, "tags": tags, "undoToken": token}


def _undo(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory) as locked:
        entry = find_undo(locked, request.get("token"))
        original = entry["changes"]
        changes: list[dict[str, str]] = []

        for change in reversed(original):
            if not all(isinstance(change.get(key), str) for key in ("path", "before", "after")):
                raise RequestError("Undo record is invalid", "invalid_undo")
            resolve_markdown_path(directory, change["path"])
            changes.append({"path": change["path"], "before": change["after"], "after": change["before"]})
        state_before = state_copy(locked)
        existed = state_exists(locked)
        undo_event_refs(locked, entry.get("eventRefs"))
        undo_completion(locked, entry.get("completion"))
        remove_undo(locked, entry["token"])
        try:
            apply_transaction(
                changes, locked.paths.journal, state_path=locked.paths.data,
                state_before=state_before, state_after=locked.value, state_before_exists=existed,
            )
        except StoreError:
            reload_state(locked, directory)
            raise
        return {"restored": [{"path": change["path"], "text": change["after"]} for change in changes],
                "completion": None}


def _session(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, False)
    with _state_for(directory) as locked:
        return {"position": locked.value.get("position")}


def _save_session(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, False)
    with _state_for(directory) as locked:
        position = normalize_position(request.get("position"))
        if position is not None:
            position["path"] = resolve_markdown_path(directory, position["path"], require_exists=False)
        save_position(locked, position)
        save_state(locked)
        return {"position": position}


def _summary(request: dict[str, Any]) -> dict[str, Any]:
    directory = _directory(request, True)
    with _state_for(directory) as locked:
        lists = scan_lists(directory)
        total = sum(int(item["total"]) for item in lists)
        done = sum(int(item["done"]) for item in lists)
        return summary(locked, total, done)


OPERATIONS = {
    "scan": _scan, "read": _read, "create": _create, "write": _write,
    "move": _move, "batch": _batch, "tags": _tags, "undo": _undo, "session": _session,
    "save_session": _save_session, "summary": _summary,
}


def dispatch(request: object) -> dict[str, Any]:
    if not isinstance(request, dict):
        raise RequestError("Request must be a JSON object")
    operation = request.get("op")
    if not isinstance(operation, str) or operation not in OPERATIONS:
        raise RequestError("Unknown todo service operation")
    return {"ok": True, "op": operation, **OPERATIONS[operation](request)}


def failure(error: Exception, operation: object = None) -> dict[str, Any]:
    if isinstance(error, (StoreError, StateError, RequestError)):
        code = error.code
    elif isinstance(error, TaskError):
        code = "invalid_markdown"
    elif isinstance(error, TagsError):
        code = "unsupported_tags"
    else:
        code = "internal_error"
    reply: dict[str, Any] = {"ok": False, "error": str(error), "code": code}
    if isinstance(operation, str):
        reply["op"] = operation
    return reply


def main() -> int:
    raw = sys.stdin.readline()
    if not raw:
        return 0
    operation: object = None
    request: object = None
    try:
        request = json.loads(raw)
        if isinstance(request, dict):
            operation = request.get("op")
        reply = dispatch(request)
    except json.JSONDecodeError:
        reply = {"ok": False, "error": "Request is not valid JSON", "code": "invalid_json"}
    except Exception as error:
        reply = failure(error, operation)

        if operation == "scan" and isinstance(request, dict):
            reply["dir"] = request.get("dir", "")
            reply["lists"] = []
    sys.stdout.write(json.dumps(reply, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

from contextlib import contextmanager
from copy import deepcopy
from dataclasses import dataclass
from datetime import date
from difflib import SequenceMatcher
import fcntl
import hashlib
import json
import os
import uuid
from typing import Any, Iterator

from todo_store import StoreError, atomic_json
from todo_tasks import Task, parse_tasks, task_signature


class StateError(RuntimeError):
    def __init__(self, message: str, code: str = "state_error") -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class StatePaths:
    data: str
    lock: str
    journal: str


@dataclass
class LockedState:
    paths: StatePaths
    value: dict[str, Any]


def _state_root() -> str:
    configured = os.environ.get("XDG_STATE_HOME", "").strip()
    if not configured or not os.path.isabs(configured):
        configured = os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(configured, "super-t")


def paths_for(directory: str) -> StatePaths:
    digest = hashlib.sha256(directory.encode("utf-8")).hexdigest()
    stem = os.path.join(_state_root(), digest)
    return StatePaths(stem + ".json", stem + ".lock", stem + ".journal.json")


def _default(directory: str) -> dict[str, Any]:
    return {"version": 1, "directory": directory, "position": None, "undo": [], "events": []}


def _load(path: str, directory: str) -> dict[str, Any]:
    if not os.path.exists(path):
        return _default(directory)
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError) as error:
        raise StateError("Todo state is unreadable; no files were changed") from error
    if not isinstance(state, dict) or state.get("version") != 1 or state.get("directory") != directory:
        raise StateError("Todo state belongs to a different directory or is invalid")
    if not isinstance(state.get("undo"), list) or not isinstance(state.get("events"), list):
        raise StateError("Todo state is invalid")
    if state.get("position") is not None and not isinstance(state["position"], dict):
        raise StateError("Todo state is invalid")
    return state


@contextmanager
def locked_state(directory: str) -> Iterator[LockedState]:
    paths = paths_for(directory)
    try:
        os.makedirs(os.path.dirname(paths.data), mode=0o700, exist_ok=True)
        descriptor = os.open(paths.lock, os.O_CREAT | os.O_RDWR, 0o600)
    except OSError as error:
        raise StateError("Could not lock todo state") from error
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield LockedState(paths, _load(paths.data, directory))
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def reload_state(locked: LockedState, directory: str) -> None:
    locked.value = _load(locked.paths.data, directory)


def save_state(locked: LockedState) -> None:
    try:
        atomic_json(locked.paths.data, locked.value)
    except StoreError as error:
        raise StateError(str(error), error.code) from error


def state_copy(locked: LockedState) -> dict[str, Any]:
    return deepcopy(locked.value)


def state_exists(locked: LockedState) -> bool:
    return os.path.exists(locked.paths.data)


def normalize_position(value: object) -> dict[str, Any] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise StateError("Saved position must be an object or null", "invalid_position")
    path = value.get("path")
    index = value.get("taskIndex")
    if not isinstance(path, str) or not path:
        raise StateError("Saved position needs a list path", "invalid_position")
    if not isinstance(index, int) or isinstance(index, bool) or index < 0:
        raise StateError("Saved position needs a non-negative task index", "invalid_position")
    position: dict[str, Any] = {"path": path, "taskIndex": index}
    for key in ("line",):
        if key in value:
            item = value[key]
            if not isinstance(item, int) or isinstance(item, bool) or item < 0:
                raise StateError("Saved task line must be non-negative", "invalid_position")
            position[key] = item
    if "text" in value:
        text = value["text"]
        if not isinstance(text, str) or len(text) > 10000:
            raise StateError("Saved task text is invalid", "invalid_position")
        position["text"] = text
    return position


def save_position(locked: LockedState, position: dict[str, Any] | None) -> None:
    locked.value["position"] = position


def add_undo(
    locked: LockedState, changes: list[dict[str, str]], completion: dict[str, Any] | list[dict[str, Any]] | None,
    event_refs: list[dict[str, Any]] | None = None,
) -> str:
    token = uuid.uuid4().hex
    entry = {"token": token, "changes": deepcopy(changes), "completion": completion,
             "eventRefs": deepcopy(event_refs or [])}
    undo = locked.value["undo"]
    undo.append(entry)
    locked.value["undo"] = undo[-40:]
    return token


def find_undo(locked: LockedState, token: object) -> dict[str, Any]:
    if not isinstance(token, str) or not token:
        raise StateError("Undo token is invalid", "invalid_undo")
    for entry in reversed(locked.value["undo"]):
        if isinstance(entry, dict) and entry.get("token") == token:
            changes = entry.get("changes")
            if not isinstance(changes, list) or not all(isinstance(change, dict) for change in changes):
                break
            return entry
    raise StateError("That change can no longer be undone", "missing_undo")


def remove_undo(locked: LockedState, token: str) -> None:
    locked.value["undo"] = [entry for entry in locked.value["undo"] if entry.get("token") != token]


def _event_signature(task: Task) -> str:
    raw = task_signature(task).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _event_ref(path: str, task: Task) -> dict[str, Any]:
    return {"path": path, "line": task.line, "signature": _event_signature(task)}


def _same_ref(event: dict[str, Any], path: str, task: Task) -> bool:
    ref = event.get("ref")
    return (isinstance(ref, dict) and ref.get("path") == path
            and ref.get("line") == task.line
            and ref.get("signature") == _event_signature(task))


def _hinted_mapping(before: list[Task], after: list[Task], hint: object) -> dict[int, int] | None:
    if not isinstance(hint, dict):
        return None
    if hint.get("kind") == "mapping":
        lines = hint["lines"]
        new_indices = {task.line: index for index, task in enumerate(after)}
        return {index: new_indices[lines[task.line]] for index, task in enumerate(before)
                if task.line in lines and lines[task.line] in new_indices}
    kind, line = hint.get("kind"), hint.get("line")
    if not isinstance(line, int) or isinstance(line, bool):
        return None
    old_index = next((index for index, task in enumerate(before) if task.line == line), None)
    new_index = next((index for index, task in enumerate(after) if task.line == line), None)
    old_signatures = [_event_signature(task) for task in before]
    new_signatures = [_event_signature(task) for task in after]
    if kind == "delete" and old_index is not None and len(after) == len(before) - 1:
        candidate = old_signatures[:old_index] + old_signatures[old_index + 1:]
        if candidate == new_signatures:
            return {index: index if index < old_index else index - 1
                    for index in range(len(before)) if index != old_index}
    if kind == "add" and new_index is not None and len(after) == len(before) + 1:
        candidate = new_signatures[:new_index] + new_signatures[new_index + 1:]
        if candidate == old_signatures:
            return {index: index if index < new_index else index + 1 for index in range(len(before))}
    if kind in ("edit", "toggle") and old_index is not None and new_index is not None and len(after) == len(before):
        return {index: index for index in range(len(before))}
    return None


def _set_ref(event: dict[str, Any], after: dict[str, Any] | None) -> dict[str, Any]:
    before = deepcopy(event.get("ref"))
    event["ref"] = deepcopy(after)
    return {"id": event.get("id"), "before": before, "after": deepcopy(after)}


def remap_events(
    locked: LockedState, path: str, before_text: str, after_text: str, hint: object = None,
) -> list[dict[str, Any]]:
    before = parse_tasks(before_text)
    after = parse_tasks(after_text)
    old_signatures = [_event_signature(task) for task in before]
    new_signatures = [_event_signature(task) for task in after]
    mapping = _hinted_mapping(before, after, hint)
    if mapping is None:
        mapping = {}
        matcher = SequenceMatcher(a=old_signatures, b=new_signatures, autojunk=False)
        for tag, old_start, old_end, new_start, new_end in matcher.get_opcodes():
            if tag == "equal" or (tag == "replace" and old_end - old_start == new_end - new_start):
                for old_index, new_index in zip(range(old_start, old_end), range(new_start, new_end)):
                    mapping[old_index] = new_index
    changes: list[dict[str, Any]] = []
    for event in locked.value["events"]:
        if not isinstance(event, dict) or not isinstance(event.get("ref"), dict):
            continue
        ref = event["ref"]
        if ref.get("path") != path:
            continue
        old_index = next((index for index, task in enumerate(before)
                          if task.line == ref.get("line")
                          and _event_signature(task) == ref.get("signature")), None)
        ambiguous = (old_index is not None and old_signatures != new_signatures
                     and old_signatures.count(old_signatures[old_index]) > 1
                     and not isinstance(hint, dict))
        if old_index is not None and old_index in mapping and not ambiguous:
            changes.append(_set_ref(event, _event_ref(path, after[mapping[old_index]])))
        elif old_index is not None:

            changes.append(_set_ref(event, None))
    return changes


def move_tracked_event(
    locked: LockedState, source_path: str, source_task: Task,
    target_path: str, target_task: Task,
) -> list[dict[str, Any]]:
    for event in reversed(locked.value["events"]):
        if isinstance(event, dict) and event.get("active") is True and _same_ref(event, source_path, source_task):
            return [_set_ref(event, _event_ref(target_path, target_task))]
    return []


def undo_event_refs(locked: LockedState, changes: object) -> None:
    if not isinstance(changes, list):
        return
    for change in reversed(changes):
        if not isinstance(change, dict) or not isinstance(change.get("id"), str):
            continue
        for event in locked.value["events"]:
            if isinstance(event, dict) and event.get("id") == change["id"]:
                event["ref"] = deepcopy(change.get("before"))
                break


def completion_change(locked: LockedState, path: str, before: Task, after: Task) -> dict[str, Any] | None:
    if before.checked == after.checked:
        return None
    events = locked.value["events"]
    if after.checked:
        event_id = uuid.uuid4().hex
        events.append({
            "id": event_id,
            "ref": _event_ref(path, after),
            "date": date.today().isoformat(),
            "active": True,
        })
        return {"id": event_id, "undoActive": False}
    for event in reversed(events):
        if event.get("active") is True and _same_ref(event, path, before):
            event["active"] = False
            return {"id": event.get("id"), "undoActive": True}
    return None


def undo_completion(locked: LockedState, delta: object) -> None:
    if isinstance(delta, list):
        for item in reversed(delta):
            undo_completion(locked, item)
        return
    if not isinstance(delta, dict):
        return
    event_id = delta.get("id")
    active = delta.get("undoActive")
    if not isinstance(event_id, str) or not isinstance(active, bool):
        return
    for event in locked.value["events"]:
        if isinstance(event, dict) and event.get("id") == event_id:
            event["active"] = active
            return


def summary(locked: LockedState, total: int, done: int) -> dict[str, Any]:
    today = date.today()
    completed_days: set[date] = set()
    closed_today = 0
    for event in locked.value["events"]:
        if not isinstance(event, dict) or event.get("active") is not True:
            continue
        try:
            completed = date.fromisoformat(str(event.get("date", "")))
        except ValueError:
            continue
        completed_days.add(completed)
        if completed == today:
            closed_today += 1
    streak = 0

    cursor = today if today in completed_days else date.fromordinal(today.toordinal() - 1)
    while cursor in completed_days:
        streak += 1
        cursor = cursor.fromordinal(cursor.toordinal() - 1)
    percent = round((done * 100.0 / total) if total else 0.0, 1)
    return {"total": total, "done": done, "percent": percent,
            "closedToday": closed_today, "streak": streak}

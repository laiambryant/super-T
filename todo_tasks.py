from __future__ import annotations

from dataclasses import dataclass
import re


TASK_RE = re.compile(r"^([ \t]*)([-*+])([ \t]+)\[([ xX])\]([ \t]?)(.*)$")
FENCE_START_RE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")


class TaskError(ValueError):
    pass


@dataclass(frozen=True)
class Task:
    line: int
    indent: int
    checked: bool
    text: str
    raw: str
    ending: str


def line_parts(text: str) -> list[tuple[str, str]]:
    parts: list[tuple[str, str]] = []
    start = 0
    for match in re.finditer(r"\r\n|\n|\r", text):
        parts.append((text[start:match.start()], match.group(0)))
        start = match.end()
    if start < len(text):
        parts.append((text[start:], ""))
    return parts


def join_parts(parts: list[tuple[str, str]]) -> str:
    return "".join(content + ending for content, ending in parts)


def preferred_ending(parts: list[tuple[str, str]], fallback: str = "\n") -> str:
    for _, ending in parts:
        if ending:
            return ending
    return fallback


def _frontmatter_end(parts: list[tuple[str, str]]) -> int | None:
    if not parts:
        return None
    first = parts[0][0]
    if first.startswith("\ufeff"):
        first = first[1:]
    if first.strip() != "---":
        return None
    for index in range(1, len(parts)):
        if parts[index][0].strip() in ("---", "..."):
            return index
    return -1


def _opens_fence(raw: str) -> tuple[str, int] | None:
    match = FENCE_START_RE.match(raw)
    if not match:
        return None
    marker, info = match.groups()

    if marker[0] == "`" and "`" in info:
        return None
    return marker[0], len(marker)


def _closes_fence(raw: str, marker: str, minimum: int) -> bool:
    match = re.match(r"^[ \t]*(" + re.escape(marker) + r"+)[ \t]*$", raw)
    return bool(match and len(match.group(1)) >= minimum)


def parse_tasks(text: str) -> list[Task]:
    parts = line_parts(text)
    frontmatter_end = _frontmatter_end(parts)
    if frontmatter_end == -1:
        return []
    start = frontmatter_end + 1 if frontmatter_end is not None else 0
    tasks: list[Task] = []
    fence: tuple[str, int] | None = None
    for line_no in range(start, len(parts)):
        raw, ending = parts[line_no]
        if fence:
            if _closes_fence(raw, fence[0], fence[1]):
                fence = None
            continue
        opened = _opens_fence(raw)
        if opened:
            fence = opened
            continue
        match = TASK_RE.match(raw)
        if not match:
            continue
        tasks.append(Task(
            line=line_no,
            indent=len(match.group(1)),
            checked=match.group(4) != " ",
            text=match.group(6),
            raw=raw,
            ending=ending,
        ))
    return tasks


def counts(text: str) -> tuple[int, int]:
    tasks = parse_tasks(text)
    return len(tasks), sum(task.checked for task in tasks)


def task_at_line(text: str, line: int) -> Task | None:
    if not isinstance(line, int) or isinstance(line, bool) or line < 0:
        return None
    for task in parse_tasks(text):
        if task.line == line:
            return task
    return None


def _replace_raw(text: str, task: Task, replacement: str) -> str:
    parts = line_parts(text)
    if task.line >= len(parts) or parts[task.line][0] != task.raw:
        raise TaskError("The selected task changed before it could be saved")
    parts[task.line] = (replacement, parts[task.line][1])
    return join_parts(parts)


def set_checked(text: str, line: int, checked: bool) -> str | None:
    task = task_at_line(text, line)
    if task is None:
        return None
    match = TASK_RE.match(task.raw)
    assert match is not None
    raw = task.raw[:match.start(4)] + ("x" if checked else " ") + task.raw[match.end(4):]
    return _replace_raw(text, task, raw)


def set_task_text(text: str, line: int, body: str) -> str | None:
    task = task_at_line(text, line)
    if task is None:
        return None
    next_body = re.sub(r"[\r\n]+", " ", str(body)).strip()
    if not next_body:
        return None
    match = TASK_RE.match(task.raw)
    assert match is not None
    raw = "".join((match.group(1), match.group(2), match.group(3), "[", match.group(4), "]", match.group(5), next_body))
    return _replace_raw(text, task, raw)


def remove_task(text: str, line: int) -> str | None:
    task = task_at_line(text, line)
    if task is None:
        return None
    parts = line_parts(text)
    del parts[task.line]
    return join_parts(parts)


def append_raw_task(text: str, raw: str, source_ending: str = "") -> tuple[str, int]:
    if not TASK_RE.match(raw):
        raise TaskError("The selected line is not a task")
    parts = line_parts(text)
    tasks = parse_tasks(text)
    ending = preferred_ending(parts, source_ending or "\n")
    had_final_ending = bool(parts and parts[-1][1])

    if tasks:
        insert_at = tasks[-1].line + 1
    else:
        insert_at = len(parts)
        while insert_at > 0 and not parts[insert_at - 1][0].strip():
            insert_at -= 1

    if insert_at > 0 and not parts[insert_at - 1][1]:
        before, _ = parts[insert_at - 1]
        parts[insert_at - 1] = (before, ending)

    if insert_at < len(parts) or had_final_ending or not parts:
        inserted_ending = ending
    else:
        inserted_ending = ""
    parts.insert(insert_at, (raw, inserted_ending))
    result = join_parts(parts)
    if task_at_line(result, insert_at) is None:
        raise TaskError("Cannot add a task inside frontmatter or an unfinished code fence")
    return result, insert_at


def append_task(text: str, body: str) -> tuple[str, int] | None:
    next_body = re.sub(r"[\r\n]+", " ", str(body)).strip()
    if not next_body:
        return None
    tasks = parse_tasks(text)
    if tasks:
        match = TASK_RE.match(tasks[-1].raw)
        assert match is not None
        raw = "".join((match.group(1), match.group(2), match.group(3), "[ ]", match.group(5), next_body))
        return append_raw_task(text, raw, tasks[-1].ending)
    return append_raw_task(text, "- [ ] " + next_body)


def move_task(source: str, line: int, target: str) -> tuple[str, str, int]:
    from todo_selection import move_tasks
    next_source, next_target, _, _, moved = move_tasks(source, [line], target)
    return next_source, next_target, moved[line]


def task_signature(task: Task) -> str:
    match = TASK_RE.match(task.raw)
    assert match is not None
    return task.raw[:match.start(4)] + task.raw[match.end(4):]


def matches(task: Task, filter_text: str) -> bool:
    return str(filter_text or "").strip().lower() in task.text.lower()

from __future__ import annotations

from todo_tasks import (
    TASK_RE, TaskError, join_parts, line_parts, parse_tasks, preferred_ending,
)


def selected_tasks(text, lines):
    if (not isinstance(lines, list) or not lines
            or any(not isinstance(line, int) or isinstance(line, bool) or line < 0 for line in lines)):
        raise TaskError("Select one or more task lines")
    tasks = {task.line: task for task in parse_tasks(text)}
    if any(line not in tasks for line in lines):
        raise TaskError("A selected task no longer exists")
    return [tasks[line] for line in sorted(set(lines))]


def block_end(parts, task):
    end = task.line + 1
    for index in range(end, len(parts)):
        raw = parts[index][0]
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" \t"))
        if indent <= task.indent:
            break
        end = index + 1
    return end


def root_blocks(text, lines):
    parts = line_parts(text)
    roots = []
    for task in selected_tasks(text, lines):
        if not roots or task.line >= roots[-1][1]:
            roots.append((task, block_end(parts, task)))
    return roots


def reindent(parts, start, end, old, new):
    for index in range(start, end):
        raw, ending = parts[index]
        if raw.strip():
            parts[index] = (new + raw[len(old):], ending)


def reorder_tasks(text, lines, direction):
    original = line_parts(text)
    tasks = parse_tasks(text)
    roots = root_blocks(text, lines)
    selected = {task.line for task, _ in roots}
    order = list(range(len(original)))

    def ordered_parts():
        return [(original[old][0], original[new][1]) for new, old in enumerate(order)]

    for root, _ in (roots if direction < 0 else reversed(roots)):
        parts = ordered_parts()
        current_tasks = parse_tasks(join_parts(parts))
        line = order.index(root.line)
        task = next(task for task in current_tasks if task.line == line)
        end = block_end(parts, task)
        if direction < 0:
            neighbor = next((row for row in reversed(current_tasks)
                             if row.line < line and row.indent <= task.indent), None)
        else:
            neighbor = next((row for row in current_tasks if row.line >= end), None)
        if neighbor is None or neighbor.indent != task.indent or order[neighbor.line] in selected:
            continue
        neighbor_end = block_end(parts, neighbor)
        first, first_end, second, second_end = (
            (neighbor.line, neighbor_end, line, end) if direction < 0
            else (line, end, neighbor.line, neighbor_end)
        )
        if any(raw.strip() for raw, _ in parts[first_end:second]):
            continue
        order[first:second_end] = (order[second:second_end] + order[first_end:second]
                                   + order[first:first_end])

    positions = {old: new for new, old in enumerate(order)}
    mapping = {task.line: positions[task.line] for task in tasks}
    result = join_parts(ordered_parts())
    if {task.line for task in parse_tasks(result)} != set(mapping.values()):
        raise TaskError("Cannot reorder tasks across an unfinished Markdown block")
    return result, mapping


def edit_tasks(text, lines, action, bodies=None):
    if action in ("up", "down"):
        return reorder_tasks(text, lines, -1 if action == "up" else 1)
    tasks = parse_tasks(text)
    selected = selected_tasks(text, lines)
    parts = line_parts(text)
    mapping = {task.line: task.line for task in tasks}
    if action == "toggle":
        checked = not all(task.checked for task in selected)
        for task in selected:
            if task.checked != checked:
                match = TASK_RE.match(task.raw)
                raw = task.raw[:match.start(4)] + ("x" if checked else " ") + task.raw[match.end(4):]
                parts[task.line] = (raw, task.ending)
        return join_parts(parts), mapping
    if action == "edit":
        if (not isinstance(bodies, list) or len(bodies) != len(selected)
                or any(not isinstance(body, str) or not body.strip() or "\n" in body or "\r" in body
                       for body in bodies)):
            raise TaskError("Keep one non-empty line per selected task")
        for task, body in zip(selected, bodies):
            match = TASK_RE.match(task.raw)
            parts[task.line] = (task.raw[:match.start(6)] + body.strip(), task.ending)
        return join_parts(parts), mapping
    if action not in ("delete", "indent", "outdent"):
        raise TaskError("Unknown selection action")
    roots = root_blocks(text, lines)
    affected = {index for task, end in roots for index in range(task.line, end)}
    if action == "delete":
        kept = [(index, part) for index, part in enumerate(parts) if index not in affected]
        mapping = {old: new for new, (old, _) in enumerate(kept) if old in mapping}
        result = join_parts([part for _, part in kept])
        if {task.line for task in parse_tasks(result)} != set(mapping.values()):
            raise TaskError("Cannot delete a task across an unfinished Markdown block")
        return result, mapping
    for task, end in roots:
        old = TASK_RE.match(task.raw).group(1)
        if action == "indent":
            previous = next((row for row in reversed(tasks)
                             if row.line < task.line and row.line not in affected), None)
            if previous is None:
                raise TaskError("A task needs another task above it")
            new = TASK_RE.match(previous.raw).group(1) + "  "

            if len(new) <= len(old):
                continue
        else:
            parent = next((row for row in reversed(tasks)
                           if row.line < task.line and row.indent < task.indent), None)
            new = TASK_RE.match(parent.raw).group(1) if parent else ""
        reindent(parts, task.line, end, old, new)
    return join_parts(parts), mapping


def move_tasks(source, lines, target):
    source_parts = line_parts(source)
    target_parts = line_parts(target)
    roots = root_blocks(source, lines)
    moved = []
    removed = set()
    for task, end in roots:
        old = TASK_RE.match(task.raw).group(1)
        reindent(source_parts, task.line, end, old, "")
        for index in range(task.line, end):
            moved.append((index, source_parts[index]))
            removed.add(index)
    kept = [(index, part) for index, part in enumerate(source_parts) if index not in removed]
    source_mapping = {old: new for new, (old, _) in enumerate(kept)}
    target_tasks = parse_tasks(target)
    insert_at = block_end(target_parts, target_tasks[-1]) if target_tasks else len(target_parts)
    if not target_tasks:
        while insert_at > 0 and not target_parts[insert_at - 1][0].strip():
            insert_at -= 1
    ending = preferred_ending(target_parts, preferred_ending(source_parts))
    final_ending = bool(target_parts and target_parts[-1][1])
    if insert_at and not target_parts[insert_at - 1][1]:
        target_parts[insert_at - 1] = (target_parts[insert_at - 1][0], ending)
    inserted = [(raw, ending) for _, (raw, _) in moved]
    if insert_at == len(target_parts) and target_parts and not final_ending:
        inserted[-1] = (inserted[-1][0], "")
    target_mapping = {task.line: task.line if task.line < insert_at else task.line + len(inserted)
                      for task in target_tasks}
    target_parts[insert_at:insert_at] = inserted
    target_text = join_parts(target_parts)
    moved_mapping = {old: insert_at + index for index, (old, _) in enumerate(moved)}
    parsed = {task.line for task in parse_tasks(target_text)}
    source_tasks = parse_tasks(source)
    source_text = join_parts([part for _, part in kept])
    expected_source = {source_mapping[task.line] for task in source_tasks if task.line not in removed}
    expected_target = set(target_mapping.values()) | {moved_mapping[task.line] for task in source_tasks if task.line in removed}
    if parsed != expected_target or {task.line for task in parse_tasks(source_text)} != expected_source:
        raise TaskError("Cannot move tasks inside frontmatter or an unfinished code fence")
    return source_text, target_text, source_mapping, target_mapping, moved_mapping

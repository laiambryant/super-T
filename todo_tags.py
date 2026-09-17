from __future__ import annotations

import json
import re
from dataclasses import dataclass

from todo_tasks import join_parts, line_parts, preferred_ending


TAG_KEY_RE = re.compile(r"^tags[ \t]*:(.*)$")


class TagsError(ValueError):
    pass


@dataclass(frozen=True)
class TagSpan:
    start: int
    end: int
    value: str
    item_lines: tuple[int, ...]


def _frontmatter_bounds(parts: list[tuple[str, str]]) -> tuple[int, int] | None:
    if not parts:
        return None
    first = parts[0][0]
    if first.startswith("\ufeff"):
        first = first[1:]
    if first.strip() != "---":
        return None
    for index in range(1, len(parts)):
        if parts[index][0].strip() in ("---", "..."):
            return 0, index
    raise TagsError("Frontmatter opens with --- but has no closing marker")


def _tags_span(parts: list[tuple[str, str]], end: int) -> TagSpan | None:
    found: TagSpan | None = None
    for index in range(1, end):
        match = TAG_KEY_RE.match(parts[index][0])
        if not match:
            continue
        if found is not None:
            raise TagsError("Multiple top-level tags properties are unsupported")
        value = match.group(1).strip()
        span_end = index + 1
        item_lines: list[int] = []
        if not value or value.startswith("#"):
            while span_end < end:
                child = parts[span_end][0]
                stripped = child.strip()
                if not stripped or stripped.startswith("#"):
                    span_end += 1
                    continue
                if re.match(r"^[ \t]*-[ \t]+.+$", child):
                    item_lines.append(span_end)
                    span_end += 1
                    continue
                if re.match(r"^[ \t]*-", child):
                    raise TagsError("A tag cannot be empty")
                if child.startswith((" ", "\t")):
                    raise TagsError("Complex YAML tags are unsupported; edit them in Obsidian first")
                break
        elif index + 1 < end and parts[index + 1][0].startswith((" ", "\t")):
            raise TagsError("Complex YAML tags are unsupported; edit them in Obsidian first")
        found = TagSpan(index, span_end, value, tuple(item_lines))
    return found


def _uncomment(value: str) -> str:
    quote = ""
    escaped = False
    for index, char in enumerate(value):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\" and quote == '"':
                escaped = True
            elif char == quote:
                quote = ""
        elif char in ("'", '"'):
            quote = char
        elif char == "#" and (index == 0 or value[index - 1].isspace()):
            return value[:index].rstrip()
    return value.strip()


def _scalar(value: str) -> str:
    value = _uncomment(value)
    if not value:
        raise TagsError("A tag cannot be empty")
    if value.startswith('"'):
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError as error:
            raise TagsError("Unsupported quoted YAML tag") from error
        if not isinstance(decoded, str):
            raise TagsError("A tag must be text")
        return decoded
    if value.startswith("'"):
        if len(value) < 2 or not value.endswith("'"):
            raise TagsError("Unsupported quoted YAML tag")
        return value[1:-1].replace("''", "'")
    if value[0] in "[{&*!|>@`":
        raise TagsError("Complex YAML tags are unsupported; edit them in Obsidian first")
    return value


def _flow_tags(value: str) -> list[str]:
    value = _uncomment(value)
    if not (value.startswith("[") and value.endswith("]")):
        return [_scalar(value)]
    body = value[1:-1].strip()
    if not body:
        return []
    items: list[str] = []
    start = 0
    quote = ""
    escaped = False
    for index, char in enumerate(body + ","):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\" and quote == '"':
                escaped = True
            elif char == quote:
                quote = ""
        elif char in ("'", '"'):
            quote = char
        elif char == ",":
            item = body[start:index].strip()
            if not item:
                raise TagsError("Empty entries in a YAML tags list are unsupported")
            items.append(_scalar(item))
            start = index + 1
    if quote:
        raise TagsError("Unsupported quoted YAML tag")
    return items


def normalize_tags(tags: object) -> list[str]:
    if not isinstance(tags, list):
        raise TagsError("Tags must be an array of text values")
    result: list[str] = []
    seen: set[str] = set()
    for value in tags:
        if not isinstance(value, str):
            raise TagsError("Tags must be an array of text values")
        tag = value.strip()
        if tag.startswith("#"):
            tag = tag[1:].strip()
        if not tag or any(ord(char) < 32 or ord(char) == 127 for char in tag):
            raise TagsError("Tags cannot be blank or contain control characters")
        segments = tag.split("/")
        if (not all(segments) or tag.isnumeric()
                or any(not all(char.isalnum() or char in "_-" for char in segment)
                       for segment in segments)):
            raise TagsError("Tags may use letters, digits, _, -, and / only")
        if tag not in seen:
            result.append(tag)
            seen.add(tag)
    return result


def tags_info(text: str) -> tuple[list[str], str | None]:
    try:
        parts = line_parts(text)
        bounds = _frontmatter_bounds(parts)
        if bounds is None:
            return [], None
        _, end = bounds
        span = _tags_span(parts, end)
        if span is None:
            return [], None
        if span.value and not span.value.startswith("#"):
            return normalize_tags(_flow_tags(span.value)), None
        values: list[str] = []
        for index in span.item_lines:
            child = parts[index][0].strip()
            if not child or child.startswith("#"):
                continue
            if not child.startswith("-"):
                raise TagsError("Complex YAML tags are unsupported; edit them in Obsidian first")
            values.append(_scalar(child[1:].strip()))
        return normalize_tags(values), None
    except TagsError as error:
        return [], str(error)


def replace_tags(text: str, tags: object) -> tuple[str, list[str]]:
    normalized = normalize_tags(tags)
    _, parse_error = tags_info(text)
    if parse_error:
        raise TagsError(parse_error)
    tag_line = "tags: " + json.dumps(normalized, ensure_ascii=False)
    parts = line_parts(text)
    bounds = _frontmatter_bounds(parts)
    if bounds is None:
        ending = preferred_ending(parts)
        if parts and parts[0][0].startswith("\ufeff"):
            first, first_ending = parts[0]
            parts[0] = (first[1:], first_ending)
            opener = "\ufeff---"
        else:
            opener = "---"
        return join_parts([(opener, ending), (tag_line, ending), ("---", ending)] + parts), normalized

    _, end = bounds
    span = _tags_span(parts, end)
    ending = preferred_ending(parts)
    if span is None:
        parts.insert(end, (tag_line, ending))
    else:
        tag_ending = parts[span.start][1] or ending
        parts[span.start] = (tag_line, tag_ending)

        for index in reversed(span.item_lines):
            del parts[index]
    return join_parts(parts), normalized

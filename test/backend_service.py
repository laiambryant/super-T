from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import os


ROOT = Path(__file__).resolve().parent.parent


class ServiceCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.directory = self.base / "todos"
        self.environment = {**os.environ, "XDG_STATE_HOME": str(self.base / "state")}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def call(self, operation: str, **payload: object) -> dict[str, object]:
        request = {"op": operation, "dir": str(self.directory), **payload}
        result = subprocess.run(
            [sys.executable, str(ROOT / "service.py")], input=json.dumps(request) + "\n",
            text=True, capture_output=True, cwd=ROOT, env=self.environment, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def ok(self, operation: str, **payload: object) -> dict[str, object]:
        reply = self.call(operation, **payload)
        self.assertTrue(reply["ok"], reply)
        return reply

    def create(self, name: str, text: str) -> Path:
        path = self.directory / (name + ".md")
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        return path

    def read_exact(self, path: Path) -> str:
        with path.open(encoding="utf-8", newline="") as handle:
            return handle.read()

    def test_create_scan_read_and_directory_validation(self) -> None:
        missing = self.call("scan")
        self.assertEqual((missing["ok"], missing["code"]), (False, "missing_directory"))
        created = self.ok("create", name="projects/super-t")
        self.assertEqual(created["name"], "projects/super-t")
        self.assertEqual(Path(str(created["path"])).read_text(), "# super-t\n\n")
        scanned = self.ok("scan")
        self.assertEqual(scanned["lists"], [{
            "path": created["path"], "name": "projects/super-t", "total": 0, "done": 0, "tags": [],
        }])
        read = self.ok("read", path=created["path"])
        self.assertEqual(read["text"], created["text"])

        relative = self.call("scan", dir="relative")
        self.assertEqual(relative["code"], "invalid_directory")
        blank = self.call("create", dir="", name="work")
        self.assertEqual(blank["error"], "No todo directory configured")
        config_file = self.base / "not-a-directory"
        config_file.write_text("x")
        invalid = self.call("scan", dir=str(config_file))
        self.assertEqual(invalid["code"], "invalid_directory")

    def test_write_conflict_move_and_undo_preserve_raw_task(self) -> None:
        source = self.create("source", "# Source\r\n  * [X] Keep **metadata** #tag\r\n  - [ ] child stays\r\n")
        target = self.create("target", "# Target\r\n")
        original_source = self.read_exact(source)
        original_target = self.read_exact(target)
        read = self.ok("read", path=str(source))
        changed = original_source.replace("[X]", "[ ]", 1)
        saved = self.ok("write", path=str(source), expected=read["text"], text=changed,
                        completion={"line": 1, "checked": False}, identity={"kind": "toggle", "line": 1})
        self.assertIn("undoToken", saved)
        undone = self.ok("undo", token=saved["undoToken"])
        self.assertEqual(undone["restored"], [{"path": str(source), "text": original_source}])

        moved = self.ok("move", path=str(source), expected=original_source, line=1, target=str(target))
        self.assertEqual(self.read_exact(source), "# Source\r\n  - [ ] child stays\r\n")
        self.assertIn("\r\n* [X] Keep **metadata** #tag\r\n", self.read_exact(target))
        self.ok("undo", token=moved["undoToken"])
        self.assertEqual(self.read_exact(source), original_source)
        self.assertEqual(self.read_exact(target), original_target)

        source.write_text("external\n", encoding="utf-8")
        conflict = self.call("write", path=str(source), expected=original_source, text=changed)
        self.assertEqual(conflict["code"], "conflict")
        self.assertEqual(source.read_text(), "external\n")

    def test_tags_preserve_frontmatter_and_reject_complex_yaml(self) -> None:
        list_path = self.create("work", "---\ntitle: Keep\ntags:\n  # retain this\n  - old\n\nother: yes\n---\n# Work\n")
        current = list_path.read_text()
        tagged = self.ok("tags", path=str(list_path), expected=current, tags=["work", "projects/super-t"])
        updated = str(tagged["text"])
        self.assertIn("title: Keep\n", updated)
        self.assertIn("  # retain this\n", updated)
        self.assertIn("other: yes\n", updated)
        self.assertNotIn("  - old\n", updated)
        self.assertIn('tags: ["work", "projects/super-t"]\n', updated)
        self.assertEqual(tagged["tags"], ["work", "projects/super-t"])

        complex_path = self.create("complex", "---\ntags: &anchor [old]\n---\n# Complex\n")
        original = complex_path.read_text()
        rejected = self.call("tags", path=str(complex_path), expected=original, tags=["new"])
        self.assertEqual(rejected["code"], "unsupported_tags")
        self.assertEqual(complex_path.read_text(), original)

    def test_move_subtask_promotes_root_and_keeps_children_and_notes(self) -> None:
        before = "# Source\r\n- [ ] parent\r\n  * [X] child #tag\r\n    note\r\n    + [ ] grandchild\r\n  - [ ] sibling\r\n"
        destination = "# Target\n- [ ] existing\n  existing note\n"
        source = self.create("nested", before)
        target = self.create("destination", destination)
        moved = self.ok("move", path=str(source), expected=before, line=2, target=str(target))
        self.assertEqual(self.read_exact(source), "# Source\r\n- [ ] parent\r\n  - [ ] sibling\r\n")
        self.assertEqual(self.read_exact(target), destination + "* [X] child #tag\n  note\n  + [ ] grandchild\n")
        self.ok("undo", token=moved["undoToken"])
        self.assertEqual(self.read_exact(source), before)
        self.assertEqual(self.read_exact(target), destination)

    def test_selection_toggle_edit_and_undo_keep_duplicate_history(self) -> None:
        before = "- [ ] same\n- [ ] same\n- [x] preexisting\n"
        path = self.create("bulk", before)
        toggled = self.ok("batch", path=str(path), expected=before, lines=[2, 0, 1], action="toggle")
        self.assertEqual(toggled["text"], "- [x] same\n- [x] same\n- [x] preexisting\n")
        self.assertEqual(self.ok("summary")["closedToday"], 2)
        edited = self.ok("batch", path=str(path), expected=toggled["text"], lines=[0, 1],
                         action="edit", bodies=["first", "second"])
        self.assertEqual(edited["text"], "- [x] first\n- [x] second\n- [x] preexisting\n")
        reopened = self.ok("batch", path=str(path), expected=edited["text"], lines=[0, 1], action="toggle")
        self.assertEqual(self.ok("summary")["closedToday"], 0)
        self.ok("undo", token=reopened["undoToken"])
        self.assertEqual(self.ok("summary")["closedToday"], 2)
        self.ok("undo", token=edited["undoToken"])
        self.ok("undo", token=toggled["undoToken"])
        self.assertEqual(self.read_exact(path), before)
        self.assertEqual(self.ok("summary")["closedToday"], 0)

    def test_selection_indent_promote_delete_is_one_undo_each(self) -> None:
        before = "# Work\r\n- [ ] parent\r\n* [ ] a\r\n  + [x] child\r\n- [ ] b\r\n"
        path = self.create("indent", before)
        nested = self.ok("batch", path=str(path), expected=before, lines=[2, 3, 4], action="indent")
        self.assertEqual(nested["text"], "# Work\r\n- [ ] parent\r\n  * [ ] a\r\n    + [x] child\r\n  - [ ] b\r\n")
        promoted = self.ok("batch", path=str(path), expected=nested["text"], lines=[2, 4], action="outdent")
        self.assertEqual(promoted["text"], before)
        deleted = self.ok("batch", path=str(path), expected=before, lines=[2, 3, 4], action="delete")
        self.assertEqual(deleted["text"], "# Work\r\n- [ ] parent\r\n")
        self.ok("undo", token=deleted["undoToken"])
        self.assertEqual(self.read_exact(path), before)
        self.ok("undo", token=promoted["undoToken"])
        self.assertEqual(self.read_exact(path), nested["text"])
        self.ok("undo", token=nested["undoToken"])
        self.assertEqual(self.read_exact(path), before)

    def test_reorder_keeps_subtrees_formatting_cursor_mapping_and_undo(self) -> None:
        before = ("---\r\ntags: [work]\r\n---\r\n# Tasks\r\n"
                  "- [ ] parent\r\n  * [X] child #tag\r\n    note\r\n\r\n+ [ ] tail")
        after = ("---\r\ntags: [work]\r\n---\r\n# Tasks\r\n"
                 "+ [ ] tail\r\n\r\n- [ ] parent\r\n  * [X] child #tag\r\n    note")
        path = self.create("reorder", before)
        moved = self.ok("batch", path=str(path), expected=before, lines=[4], action="down")
        self.assertEqual(self.read_exact(path), after)
        self.assertEqual(moved["lineMapping"], {"4": 6, "5": 7, "8": 4})
        back = self.ok("batch", path=str(path), expected=after, lines=[6], action="up")
        self.assertEqual(back["text"], before)
        self.ok("undo", token=back["undoToken"])
        self.assertEqual(self.read_exact(path), after)
        self.ok("undo", token=moved["undoToken"])
        self.assertEqual(self.read_exact(path), before)

    def test_reorder_selection_moves_each_root_once_in_document_order(self) -> None:
        before = "- [ ] first\n- [ ] parent\n  - [ ] child\n- [ ] hidden\n- [ ] last\n"
        path = self.create("selection", before)
        moved = self.ok("batch", path=str(path), expected=before, lines=[1, 2, 4], action="up")
        self.assertEqual(moved["text"], "- [ ] parent\n  - [ ] child\n- [ ] first\n- [ ] last\n- [ ] hidden\n")
        back = self.ok("batch", path=str(path), expected=moved["text"], lines=[0, 1, 3], action="down")
        self.assertEqual(back["text"], before)
        adjacent = self.ok("batch", path=str(path), expected=before, lines=[1, 3], action="up")
        self.assertEqual(adjacent["text"], "- [ ] parent\n  - [ ] child\n- [ ] hidden\n- [ ] first\n- [ ] last\n")

    def test_reorder_stops_at_parent_section_and_document_edges(self) -> None:
        before = "# First\n- [ ] parent\n  - [ ] child\n  - [ ] sibling\n\n# Second\n- [ ] tail\n"
        path = self.create("edges", before)
        for lines, action in (([1], "up"), ([1], "down"), ([2], "up"), ([3], "down"),
                              ([6], "down"), ([6], "up"), ([1, 2, 3, 6], "up")):
            with self.subTest(lines=lines, action=action):
                moved = self.ok("batch", path=str(path), expected=before, lines=lines, action=action)
                self.assertEqual(moved["text"], before)
                self.assertIsNone(moved["undoToken"])
        moved = self.ok("batch", path=str(path), expected=before, lines=[3], action="up")
        self.assertEqual(moved["text"], before.replace("  - [ ] child\n  - [ ] sibling", "  - [ ] sibling\n  - [ ] child"))
        conflict = self.call("batch", path=str(path), expected=before, lines=[3], action="up")
        self.assertEqual(conflict["code"], "conflict")
        self.assertEqual(self.read_exact(path), moved["text"])

    def test_reorder_identical_tasks_keeps_completion_history_and_undo(self) -> None:
        before = "- [ ] same\n- [x] same\n"
        path = self.create("duplicates", before)
        checked = self.ok("batch", path=str(path), expected=before, lines=[0], action="toggle")
        moved = self.ok("batch", path=str(path), expected=checked["text"], lines=[0], action="down")
        self.assertEqual(moved["text"], checked["text"])
        self.assertEqual(moved["lineMapping"], {"0": 1, "1": 0})
        self.assertIsNotNone(moved["undoToken"])
        reopened = self.ok("batch", path=str(path), expected=moved["text"], lines=[1], action="toggle")
        self.assertEqual(self.ok("summary")["closedToday"], 0)
        self.ok("undo", token=reopened["undoToken"])
        self.ok("undo", token=moved["undoToken"])
        self.ok("batch", path=str(path), expected=checked["text"], lines=[0], action="toggle")
        self.assertEqual(self.ok("summary")["closedToday"], 0)

    def test_bulk_move_deduplicates_children_and_preserves_completion_identity(self) -> None:
        before = "- [ ] parent\n  - [ ] same\n  - [ ] same\n- [ ] tail\n"
        path = self.create("source", before)
        target = self.create("target", "- [ ] same\n")
        checked = self.ok("batch", path=str(path), expected=before, lines=[1, 2, 3], action="toggle")
        moved = self.ok("move", path=str(path), expected=checked["text"], lines=[0, 1, 3], target=str(target))
        self.assertEqual(moved["sourceText"], "")
        self.assertEqual(moved["text"], "- [ ] same\n- [ ] parent\n  - [x] same\n  - [x] same\n- [x] tail\n")
        reopened = self.ok("batch", path=str(target), expected=moved["text"], lines=[2, 3, 4], action="toggle")
        self.assertEqual(self.ok("summary")["closedToday"], 0)
        self.ok("undo", token=reopened["undoToken"])
        self.ok("undo", token=moved["undoToken"])
        self.assertEqual(self.read_exact(path), checked["text"])
        self.assertEqual(self.read_exact(target), "- [ ] same\n")
        self.ok("batch", path=str(path), expected=checked["text"], lines=[1, 2, 3], action="toggle")
        self.assertEqual(self.ok("summary")["closedToday"], 0)

    def test_batch_rejects_invalid_selection_and_conflicts_without_writing(self) -> None:
        before = "# Tasks\n- [ ] one\n- [ ] two\n"
        path = self.create("source", before)
        target = self.create("target", "---\nunclosed: true\n")
        for lines in ([], [0], [True], [-1], [99], ["1"]):
            rejected = self.call("batch", path=str(path), expected=before, lines=lines, action="delete")
            self.assertFalse(rejected["ok"], rejected)
            self.assertEqual(self.read_exact(path), before)
        invalid = self.call("batch", path=str(path), expected=before, lines=[1, 2], action="edit", bodies=["one"])
        self.assertFalse(invalid["ok"])
        conflict = self.call("batch", path=str(path), expected="old", lines=[1], action="delete")
        self.assertEqual(conflict["code"], "conflict")
        refused = self.call("move", path=str(path), expected=before, lines=[1, 2], target=str(target))
        self.assertFalse(refused["ok"])
        self.assertEqual(self.read_exact(path), before)
        self.assertEqual(self.read_exact(target), "---\nunclosed: true\n")

    def test_transfer_preserves_markdown_and_refuses_split_fences(self) -> None:
        before = "- [ ] parent\n  ```\nunindented content\n  ```\n- [ ] other\n"
        path = self.create("source", before)
        target = self.create("target", "# Destination\n")
        for op, extra in (("batch", {"action": "delete"}), ("move", {"target": str(target)})):
            rejected = self.call(op, path=str(path), expected=before, lines=[0], **extra)
            self.assertFalse(rejected["ok"])
            self.assertEqual(self.read_exact(path), before)
            self.assertEqual(self.read_exact(target), "# Destination\n")

    def test_scan_reads_common_obsidian_tag_forms(self) -> None:
        scalar = self.create("scalar", "---\ntags: home\n---\n- [ ] one\n")
        flow = self.create("flow", "---\ntags: [work, projects/super-t]\n---\n- [ ] two\n")
        block = self.create("block", "---\ntags:\n  - one\n  - two\n---\n- [ ] three\n")
        scanned = self.ok("scan")["lists"]
        tags = {Path(str(item["path"])).name: item["tags"] for item in scanned}
        self.assertEqual(tags[scalar.name], ["home"])
        self.assertEqual(tags[flow.name], ["work", "projects/super-t"])
        self.assertEqual(tags[block.name], ["one", "two"])

    def test_completion_history_survives_edit_move_and_duplicate_delete(self) -> None:
        source = self.create("source", "- [ ] same\n- [ ] same\n")
        target = self.create("target", "# Target\n")
        before = source.read_text()
        checked = before.replace("[ ]", "[x]", 1)
        first = self.ok("write", path=str(source), expected=before, text=checked,
                        completion={"line": 0, "checked": True}, identity={"kind": "toggle", "line": 0})
        self.assertEqual(self.ok("summary")["closedToday"], 1)

        edited = checked.replace("same", "renamed", 1)
        self.ok("write", path=str(source), expected=checked, text=edited,
                identity={"kind": "edit", "line": 0})
        reopened = edited.replace("[x]", "[ ]", 1)
        self.ok("write", path=str(source), expected=edited, text=reopened,
                completion={"line": 0, "checked": False}, identity={"kind": "toggle", "line": 0})
        self.assertEqual(self.ok("summary")["closedToday"], 0)

        rechecked = reopened.replace("[ ]", "[x]", 1)
        self.ok("write", path=str(source), expected=reopened, text=rechecked,
                completion={"line": 0, "checked": True}, identity={"kind": "toggle", "line": 0})
        moved = self.ok("move", path=str(source), expected=rechecked, line=0, target=str(target))
        target_checked = str(moved["text"])
        target_reopened = target_checked.replace("[x]", "[ ]", 1)
        self.ok("write", path=str(target), expected=target_checked, text=target_reopened,
                completion={"line": moved["line"], "checked": False},
                identity={"kind": "toggle", "line": moved["line"]})
        self.assertEqual(self.ok("summary")["closedToday"], 0)

        duplicate = self.create("duplicate", "- [ ] duplicate\n- [ ] duplicate\n")
        initial = duplicate.read_text()
        first_done = initial.replace("[ ]", "[x]", 1)
        self.ok("write", path=str(duplicate), expected=initial, text=first_done,
                completion={"line": 0, "checked": True}, identity={"kind": "toggle", "line": 0})
        removed = first_done.split("\n", 1)[1]
        self.ok("write", path=str(duplicate), expected=first_done, text=removed,
                identity={"kind": "delete", "line": 0})
        remaining_done = removed.replace("[ ]", "[x]", 1)
        self.ok("write", path=str(duplicate), expected=removed, text=remaining_done,
                completion={"line": 0, "checked": True}, identity={"kind": "toggle", "line": 0})
        reopened_remaining = remaining_done.replace("[x]", "[ ]", 1)
        self.ok("write", path=str(duplicate), expected=remaining_done, text=reopened_remaining,
                completion={"line": 0, "checked": False}, identity={"kind": "toggle", "line": 0})

        self.assertEqual(self.ok("summary")["closedToday"], 1)


if __name__ == "__main__":
    unittest.main()

import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from todo_tasks import parse_tasks, set_checked, set_task_text, remove_task, append_task

fixtures = json.load(sys.stdin)
for index, fixture in enumerate(fixtures):
    text = fixture['text']
    tasks = parse_tasks(text)
    line = tasks[0].line if tasks else -1
    added = append_task(text, 'new task')
    result = dict(tasks=[dict(line=t.line, indent=t.indent, checked=t.checked, text=t.text) for t in tasks],
        checked=set_checked(text, line, True), edited=set_task_text(text, line, 'edited'),
        removed=remove_task(text, line), added=dict(text=added[0], line=added[1]) if added else None)
    assert result == fixture['result'], (index, result, fixture['result'])
print(f'UI/scanner parity: {len(fixtures)} markdown fixtures passed')

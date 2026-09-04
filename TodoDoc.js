.pragma library

// Markdown task parsing and *surgical* write-back.
//
// The contract with the user's files is that this plugin only ever rewrites
// the bytes it owns: the checkbox character and the task text on a task line.
// Prose, headings, code fences, front matter, indentation, bullet style and
// trailing whitespace are all passed through untouched, because every edit
// below rebuilds a single line out of that line's own captured groups.
//
// Groups: 1 indent, 2 bullet, 3 gap, 4 mark, 5 gap, 6 text
var TASK_RE = /^([ \t]*)([-*+])([ \t]+)\[([ xX])\]([ \t]?)(.*)$/;

function splitLines(text) {
  return String(text === null || text === undefined ? "" : text).split("\n");
}

// Task lines inside a fenced code block are examples, not todos.
function fenceDepthBefore(lines, upTo) {
  var inFence = false;
  for (var i = 0; i < upTo && i < lines.length; i++) {
    if (/^[ \t]*(```|~~~)/.test(lines[i])) inFence = !inFence;
  }
  return inFence;
}

function parse(text) {
  var lines = splitLines(text);
  var tasks = [];
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    if (/^[ \t]*(```|~~~)/.test(lines[i])) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    var m = lines[i].match(TASK_RE);
    if (!m) continue;
    tasks.push({
      line: i,
      indent: m[1].length,
      checked: m[4] !== " ",
      text: m[6]
    });
  }
  return tasks;
}

function counts(text) {
  var tasks = parse(text);
  var done = 0;
  for (var i = 0; i < tasks.length; i++) if (tasks[i].checked) done++;
  return { total: tasks.length, done: done };
}

function rebuild(m, mark, body) {
  return m[1] + m[2] + m[3] + "[" + mark + "]" + (m[5] || " ") + body;
}

// Each mutator returns the new full document text, or null if lineIndex did
// not point at a task line (the caller then leaves the file alone).
function setChecked(text, lineIndex, checked) {
  var lines = splitLines(text);
  var m = lines[lineIndex] === undefined ? null : lines[lineIndex].match(TASK_RE);
  if (!m) return null;
  lines[lineIndex] = rebuild(m, checked ? "x" : " ", m[6]);
  return lines.join("\n");
}

function setTaskText(text, lineIndex, body) {
  var lines = splitLines(text);
  var m = lines[lineIndex] === undefined ? null : lines[lineIndex].match(TASK_RE);
  if (!m) return null;
  var next = String(body).replace(/[\r\n]+/g, " ").trim();
  if (!next) return null;
  lines[lineIndex] = rebuild(m, m[4], next);
  return lines.join("\n");
}

function removeTask(text, lineIndex) {
  var lines = splitLines(text);
  if (lineIndex < 0 || lineIndex >= lines.length) return null;
  if (!lines[lineIndex].match(TASK_RE)) return null;
  lines.splice(lineIndex, 1);
  return lines.join("\n");
}

// New tasks land directly after the last existing task, inheriting its
// indentation and bullet style. In a file with no tasks yet they go at the end
// of the content, before any trailing blank lines, so the file's final newline
// survives exactly as it was.
function appendTask(text, body) {
  var next = String(body).replace(/[\r\n]+/g, " ").trim();
  if (!next) return null;

  var lines = splitLines(text);
  var tasks = parse(text);
  var insertAt;
  var line;

  if (tasks.length > 0) {
    var last = tasks[tasks.length - 1];
    var m = lines[last.line].match(TASK_RE);
    insertAt = last.line + 1;
    line = rebuild(m, " ", next);
  } else {
    insertAt = lines.length;
    while (insertAt > 0 && lines[insertAt - 1].trim() === "") insertAt--;
    line = "- [ ] " + next;
  }

  lines.splice(insertAt, 0, line);
  return { text: lines.join("\n"), line: insertAt };
}

function matches(task, filter) {
  var needle = String(filter || "").trim().toLowerCase();
  if (!needle) return true;
  return String(task.text).toLowerCase().indexOf(needle) !== -1;
}

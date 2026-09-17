.pragma library
var TASK_RE = /^([ \t]*)([-*+])([ \t]+)\[([ xX])\]([ \t]?)([^\r\n]*)$/;

function parts(text) {
  var input = String(text === null || text === undefined ? "" : text);
  var out = [], start = 0, match;
  var endings = /\r\n|\n|\r/g;
  while ((match = endings.exec(input)) !== null) {
    out.push({ raw: input.slice(start, match.index), ending: match[0] });
    start = endings.lastIndex;
  }
  if (start < input.length) out.push({ raw: input.slice(start), ending: "" });
  return out;
}

function join(lines) {
  return lines.map(function(line) { return line.raw + line.ending; }).join("");
}

function parse(text) {
  var lines = parts(text), tasks = [], fence = "", fenceLength = 0;
  var frontmatter = lines.length && lines[0].raw.replace(/^\uFEFF/, "").trim() === "---";
  for (var i = 0; i < lines.length; i++) {
    var raw = lines[i].raw;
    if (frontmatter) {
      if (i > 0 && (raw.trim() === "---" || raw.trim() === "...")) frontmatter = false;
      continue;
    }
    var marker = raw.match(/^[ \t]*(`{3,}|~{3,})(.*)$/);
    if (fence) {
      if (marker && marker[1].charAt(0) === fence && marker[1].length >= fenceLength
          && /^[ \t]*$/.test(marker[2])) fence = "";
      continue;
    }
    if (marker && !(marker[1].charAt(0) === "`" && marker[2].indexOf("`") !== -1)) {
      fence = marker[1].charAt(0);
      fenceLength = marker[1].length;
      continue;
    }
    var m = raw.match(TASK_RE);
    if (m) tasks.push({ line: i, indent: m[1].length, checked: m[4] !== " ", text: m[6] });
  }
  return tasks;
}

function counts(text) {
  var tasks = parse(text), done = 0;
  for (var i = 0; i < tasks.length; i++) if (tasks[i].checked) done++;
  return { total: tasks.length, done: done };
}

function validTask(text, lineIndex) {
  var tasks = parse(text);
  for (var i = 0; i < tasks.length; i++) if (tasks[i].line === lineIndex) return true;
  return false;
}

function rebuild(m, mark, body) {
  return m[1] + m[2] + m[3] + "[" + mark + "]" + m[5] + body;
}

function setChecked(text, lineIndex, checked) {
  if (!validTask(text, lineIndex)) return null;
  var lines = parts(text), m = lines[lineIndex].raw.match(TASK_RE);
  lines[lineIndex].raw = rebuild(m, checked ? "x" : " ", m[6]);
  return join(lines);
}

function setTaskText(text, lineIndex, body) {
  if (!validTask(text, lineIndex)) return null;
  var next = String(body).replace(/[\r\n]+/g, " ").trim();
  if (!next) return null;
  var lines = parts(text), m = lines[lineIndex].raw.match(TASK_RE);
  lines[lineIndex].raw = rebuild(m, m[4], next);
  return join(lines);
}

function removeTask(text, lineIndex) {
  if (!validTask(text, lineIndex)) return null;
  var lines = parts(text);
  lines.splice(lineIndex, 1);
  return join(lines);
}

function makeSubtask(text, lineIndex) {
  var tasks = parse(text), taskAt = -1;
  for (var i = 0; i < tasks.length; i++) {
    if (tasks[i].line === lineIndex) {
      taskAt = i;
      break;
    }
  }
  if (taskAt <= 0) return null;

  var lines = parts(text);
  var parent = lines[tasks[taskAt - 1].line].raw.match(TASK_RE);
  var child = lines[lineIndex].raw.match(TASK_RE);
  if (!parent || !child) return null;
  var indent = parent[1] + "  ";
  lines[lineIndex].raw = indent + lines[lineIndex].raw.slice(child[1].length);
  return join(lines);
}

function appendTask(text, body) {
  var next = String(body).replace(/[\r\n]+/g, " ").trim();
  if (!next) return null;
  var lines = parts(text), tasks = parse(text), insertAt = lines.length;
  var ending = "\n", raw = "- [ ] " + next;
  var hadFinalEnding = lines.length && !!lines[lines.length - 1].ending;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].ending) { ending = lines[i].ending; break; }
  }
  if (tasks.length) {
    var last = tasks[tasks.length - 1];
    var m = lines[last.line].raw.match(TASK_RE);
    insertAt = last.line + 1;
    raw = rebuild(m, " ", next);
  } else {
    while (insertAt > 0 && !lines[insertAt - 1].raw.trim()) insertAt--;
  }
  if (insertAt > 0 && !lines[insertAt - 1].ending) lines[insertAt - 1].ending = ending;
  var terminator = insertAt < lines.length || hadFinalEnding || !lines.length ? ending : "";
  lines.splice(insertAt, 0, { raw: raw, ending: terminator });
  var result = join(lines);
  if (!validTask(result, insertAt)) return null;
  return { text: result, line: insertAt };
}

function matches(task, filter) {
  var needle = String(filter || "").trim().toLowerCase();
  return !needle || String(task.text).toLowerCase().indexOf(needle) !== -1;
}

.pragma library
.import "TodoDoc.js" as TodoDoc

function toggleTaskAt(controller, sourceIndex) {
  controller.focusPane("tasks");
  controller.setTaskIndex(sourceIndex);
  if (!controller.selecting) toggleSelected(controller);
}

function toggleSelected(controller) {
  if (controller.selecting) {
    batch(controller, "toggle", "Updated selection");
    return;
  }
  var task = controller.selectedTask();
  if (!task || controller.mutationBusy) return;
  var next = TodoDoc.setChecked(controller.docText, task.line, !task.checked);
  if (next === null) return;
  startMutation(controller, "write", {
    path: controller.currentPath,
    expected: controller.docText,
    text: next,
    completion: { line: task.line, checked: !task.checked },
    identity: { kind: "edit", line: task.line }
  }, { path: controller.currentPath, input: false, message: task.checked ? "Reopened" : "Completed" });
}

function batch(controller, action, message) {
  var rows = controller.selectedRows();
  if (!rows.length || controller.mutationBusy) return;
  startMutation(controller, "batch", {
    path: controller.currentPath, expected: controller.docText,
    lines: rows.map(function(task) { return task.line; }), action: action
  }, { path: controller.currentPath, input: false, message: message });
}

function deleteSelected(controller) { batch(controller, "delete", "Deleted"); }
function promoteSelected(controller) { batch(controller, "outdent", "Promoted"); }

function reorderSelected(controller, delta) {
  var rows = controller.selectedRows();
  var task = controller.selectedTask();
  if (!task || !rows.length || controller.mutationBusy) return;
  startMutation(controller, "batch", {
    path: controller.currentPath, expected: controller.docText,
    lines: rows.map(function(row) { return row.line; }),
    action: delta < 0 ? "up" : "down"
  }, {
    path: controller.currentPath, input: false,
    reorderLine: task.line, message: delta < 0 ? "Moved up" : "Moved down"
  });
}

function makeSelectedSubtask(controller) {
  var rows = controller.selectedRows();
  if (!rows.length || controller.mutationBusy) return;
  if (rows[0].line === controller.allTasks[0].line) {
    controller.flash("A task needs another task above it");
    return;
  }
  batch(controller, "indent", "Made subtask");
}

function beginInput(controller, purpose) {
  if (controller.mutationBusy) return;
  clearInput(controller);
  controller.inputPurpose = purpose;
  if (purpose === "list") {
    controller.mode = "input";
    controller.requestInputFocus();
    return;
  }
  if (!controller.dataReady || !controller.currentPath) {
    controller.flash("Choose a list first");
    clearInput(controller);
    return;
  }
  controller.inputPath = controller.currentPath;
  controller.inputExpected = controller.docText;
  if (purpose === "edit") {
    var task = controller.selectedTask();
    if (!task) {
      clearInput(controller);
      return;
    }
    var rows = controller.selectedRows();
    controller.inputLines = rows.map(function(row) { return row.line; });
    controller.inputLine = task.line;
    controller.inputText = rows.map(function(row) { return row.text; }).join("\n");
  } else if (purpose === "tags") {
    controller.inputText = controller.documentTags.join(", ");
  }
  controller.mode = "input";
  controller.requestInputFocus();
}

function clearInput(controller) {
  controller.inputPurpose = "";
  controller.inputText = "";
  controller.inputError = "";
  controller.inputPath = "";
  controller.inputExpected = "";
  controller.inputLine = -1;
  controller.inputLines = [];
}

function cancelInput(controller) {
  controller.mode = "normal";
  clearInput(controller);
  controller.requestKeyboardFocus();
}

function commitInput(controller) {
  var value = String(controller.inputText || "");
  if (!value.trim() && controller.inputPurpose !== "tags") {
    controller.inputError = controller.inputPurpose === "list" ? "A list name is required" : "A task is required";
    return;
  }
  if (controller.mutationBusy) return;
  if (controller.inputPurpose === "list") {
    startMutation(controller, "create", { name: value }, { input: true, kind: "create", message: "Created" });
  } else if (controller.inputPurpose === "add") {
    var added = TodoDoc.appendTask(controller.inputExpected, value);
    if (!added) {
      controller.inputError = "Cannot add task inside unfinished Markdown block";
      return;
    }
    startMutation(controller, "write", {
      path: controller.inputPath,
      expected: controller.inputExpected,
      text: added.text,
      identity: { kind: "add", line: added.line }
    }, { path: controller.inputPath, input: true, message: "Added", selectLine: added.line });
  } else if (controller.inputPurpose === "edit" && controller.inputLines.length > 1) {
    var bodies = value.split(/\r\n|\r|\n/);
    if (bodies.length !== controller.inputLines.length || bodies.some(function(body) { return !body.trim(); })) {
      controller.inputError = "Keep one non-empty line per selected task (" + controller.inputLines.length + " lines)";
      return;
    }
    startMutation(controller, "batch", {
      path: controller.inputPath, expected: controller.inputExpected,
      lines: controller.inputLines, action: "edit", bodies: bodies
    }, { path: controller.inputPath, input: true, message: "Saved selection" });
  } else if (controller.inputPurpose === "edit") {
    var edited = TodoDoc.setTaskText(controller.inputExpected, controller.inputLine, value);
    if (edited === null) {
      controller.inputError = "That task changed; reload and try again";
      return;
    }
    startMutation(controller, "write", {
      path: controller.inputPath,
      expected: controller.inputExpected,
      text: edited,
      identity: { kind: "edit", line: controller.inputLine }
    }, { path: controller.inputPath, input: true, message: "Saved" });
  } else if (controller.inputPurpose === "tags") {
    startMutation(controller, "tags", {
      path: controller.inputPath,
      expected: controller.inputExpected,
      tags: parseTags(controller.inputText)
    }, { path: controller.inputPath, input: true, message: "Tags saved" });
  }
}

function parseTags(text) {
  var values = String(text || "").split(/[\s,]+/);
  var tags = [];
  for (var i = 0; i < values.length; i++) {
    var tag = values[i].trim().replace(/^#+/, "");
    var key = tag.toLowerCase();
    var duplicate = false;
    for (var j = 0; j < tags.length; j++) {
      if (tags[j].toLowerCase() === key) {
        duplicate = true;
        break;
      }
    }
    if (tag && !duplicate) tags.push(tag);
  }
  return tags;
}

function beginMove(controller) {
  var task = controller.selectedTask();
  if (!task || controller.mutationBusy) return;
  var targets = [];
  for (var i = 0; i < controller.lists.length; i++) {
    if (String(controller.lists[i].path) !== controller.currentPath) targets.push(controller.lists[i]);
  }
  if (!targets.length) {
    controller.flash("Create another list before moving a task");
    return;
  }
  controller.moveTaskSnapshot = {
    path: controller.currentPath,
    expected: controller.docText,
    line: task.line,
    lines: controller.selectedRows().map(function(row) { return row.line; }),
    sourceIndex: controller.taskIndex
  };
  controller.moveTargets = targets;
  controller.moveTargetIndex = 0;
  controller.requestMoveTargetReveal(0);
  controller.mode = "move";
  controller.requestKeyboardFocus();
}

function moveMoveTarget(controller, delta) {
  if (!controller.moveTargets.length) return;
  controller.moveTargetIndex = Math.max(0, Math.min(
    controller.moveTargetIndex + delta, controller.moveTargets.length - 1));
  controller.requestMoveTargetReveal(controller.moveTargetIndex);
}

function selectMoveTarget(controller, index) {
  if (index >= 0 && index < controller.moveTargets.length) {
    controller.moveTargetIndex = index;
    controller.requestMoveTargetReveal(index);
  }
}

function cancelMove(controller) {
  controller.mode = "normal";
  controller.moveTaskSnapshot = null;
  controller.moveTargets = [];
  controller.requestKeyboardFocus();
}

function confirmMove(controller) {
  if (!controller.moveTaskSnapshot || !controller.selectedMoveTarget || controller.mutationBusy) return;
  startMutation(controller, "move", {
    path: controller.moveTaskSnapshot.path,
    expected: controller.moveTaskSnapshot.expected,
    line: controller.moveTaskSnapshot.line,
    lines: controller.moveTaskSnapshot.lines,
    target: String(controller.selectedMoveTarget.path)
  }, { path: controller.moveTaskSnapshot.path, input: false, kind: "move", message: "Moved" });
}

function startMutation(controller, op, payload, context) {
  if (controller.mutationBusy) {
    controller.flash("Saving the previous change");
    return false;
  }
  var pending = { op: op, requestId: -1, generation: controller.directoryGeneration, context: context || {} };
  controller.pendingMutation = pending;
  controller.mutationBusy = true;
  var id = controller.invoke(op, payload);
  if (controller.pendingMutation === pending) pending.requestId = id;
  if (id < 0 && controller.pendingMutation === pending) {
    controller.pendingMutation = null;
    controller.mutationBusy = false;
  }
  return id >= 0;
}

function undo(controller) {
  if (controller.mutationBusy) return;
  if (!controller.undoTokens.length) {
    controller.flash("Nothing to undo");
    return;
  }
  startMutation(controller, "undo", { token: controller.undoTokens[controller.undoTokens.length - 1] },
    { kind: "undo", message: "Undone" });
}

function applyMutationSuccess(controller, data) {
  var pending = controller.pendingMutation;
  controller.pendingMutation = null;
  controller.mutationBusy = false;
  if (!pending) return;
  controller.clearSelection();

  if (pending.op === "undo") {
    controller.undoTokens = controller.undoTokens.slice(0, -1);
    var restored = Array.isArray(data.restored) ? data.restored : [];
    for (var i = 0; i < restored.length; i++) applyServerText(controller, restored[i].path, restored[i].text, undefined);
    if (controller.currentPath) controller.requestRead(controller.currentPath);
  } else {
    if (data.undoToken) controller.undoTokens = controller.undoTokens.concat([data.undoToken]).slice(-40);
    if (pending.op === "move") {
      applyServerText(controller, data.sourcePath, data.sourceText, undefined);
      applyServerText(controller, data.path, data.text, undefined);
      cancelMove(controller);
    } else if (pending.op === "create") {
      controller.pendingSelectPath = String(data.path);
      insertCreatedList(controller, data);
      clearInput(controller);
      controller.mode = "normal";
      controller.selectList(controller.indexForPath(data.path));
      applyServerText(controller, data.path, data.text, []);
    } else {
      applyServerText(controller, data.path, data.text, data.tags);
      if (pending.context.reorderLine !== undefined && data.path === controller.currentPath
          && data.lineMapping) {
        selectTaskAtLine(controller, data.lineMapping[pending.context.reorderLine]);
      }
      if (pending.context.input) {
        var line = pending.context.selectLine;
        clearInput(controller);
        controller.mode = "normal";
        if (line !== undefined) selectTaskAtLine(controller, line);
        controller.requestKeyboardFocus();
      }
    }
  }
  controller.refreshLists();
  controller.barRefreshRequested();
  controller.flash(pending.context.message || "Saved");
}

function applyServerText(controller, path, text, tags) {
  if (String(path || "") !== controller.currentPath) return;
  controller.loadedPath = controller.currentPath;
  controller.docText = String(text === undefined || text === null ? "" : text);
  if (tags !== undefined) controller.documentTags = Array.isArray(tags) ? tags : [];
  controller.dataReady = true;
  controller.rebuildTasks();
  if (controller.sessionSavePending) controller.queueSessionSave();
}

function insertCreatedList(controller, data) {
  var path = String(data.path);
  if (controller.indexForPath(path) >= 0) return;
  var copy = controller.lists.slice();
  var at = 0;
  while (at < copy.length && String(copy[at].path) < path) at++;
  copy.splice(at, 0, { path: path, name: String(data.name), total: 0, done: 0, tags: [] });
  controller.lists = copy;
}

function selectTaskAtLine(controller, line) {
  for (var i = 0; i < controller.allTasks.length; i++) {
    if (controller.allTasks[i].line === line) {
      controller.setTaskIndex(i);
      return;
    }
  }
}

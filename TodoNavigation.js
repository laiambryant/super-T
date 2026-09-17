.pragma library
.import "TodoDoc.js" as TodoDoc

function resetForDirectory(controller) {
  controller.mode = "normal";
  controller.activePane = "tasks";
  controller.moveTaskSnapshot = null;
  controller.moveTargets = [];
  controller.directoryGeneration++;
  controller.scanRequestId = -1;
  controller.readRequestId = -1;
  controller.sessionRequestId = -1;
  controller.summaryRequestId = -1;
  controller.saveRequestId = -1;
  controller.scanInFlight = false;
  controller.scanAgain = false;
  controller.pendingMutation = null;
  controller.mutationBusy = false;
  controller.undoTokens = [];
  controller.sessionSavePending = false;
  controller.stopSessionSaveTimer();
  controller.initialScanReady = false;
  controller.initialReadReady = false;
  controller.sessionLoaded = false;
  controller.restoreApplied = false;
  controller.savedPosition = null;
  controller.pendingSelectPath = "";
  controller.summaryLoading = false;
  controller.clearInput();
  clearDocument(controller);
  controller.lists = [];
  controller.listIndex = -1;
}

function applyScan(controller, data) {
  var previousPath = controller.currentPath;
  var previousIndex = controller.listIndex;
  controller.lists = data && Array.isArray(data.lists) ? data.lists : [];
  controller.scanOk = true;
  controller.initialScanReady = true;

  var wantedPath = controller.pendingSelectPath;
  if (!wantedPath && !controller.restoreApplied && controller.savedPosition && controller.savedPosition.path)
    wantedPath = String(controller.savedPosition.path);
  if (!wantedPath) wantedPath = previousPath;
  var nextIndex = indexForPath(controller, wantedPath);
  if (nextIndex < 0 && controller.lists.length)
    nextIndex = Math.max(0, Math.min(previousIndex, controller.lists.length - 1));

  if (nextIndex < 0) {
    controller.listIndex = -1;
    clearDocument(controller);
    controller.initialReadReady = true;
    controller.tryRestore();
    return;
  }

  controller.pendingSelectPath = "";
  var changedPath = String(controller.lists[nextIndex].path) !== previousPath;
  controller.listIndex = nextIndex;
  controller.requestListReveal(nextIndex);
  if (changedPath || !controller.dataReady || controller.loadedPath !== controller.currentPath
      || !controller.initialReadReady) {
    clearDocument(controller);
    controller.requestRead(controller.currentPath);
  } else {
    controller.tryRestore();
  }
}

function applyRead(controller, data, requestedPath) {
  var path = String(data && data.path ? data.path : requestedPath || "");
  if (!path || path !== controller.currentPath) return;
  if (String(data && data.text !== undefined ? data.text : "") !== controller.docText)
    controller.clearSelection();
  controller.loadedPath = path;
  controller.docText = String(data && data.text !== undefined ? data.text : "");
  controller.documentTags = data && Array.isArray(data.tags) ? data.tags : [];
  controller.documentError = "";
  controller.dataReady = true;
  controller.initialReadReady = true;
  rebuildTasks(controller);
  controller.tryRestore();
  if (controller.sessionSavePending) controller.queueSessionSave();
}

function clearDocument(controller) {
  controller.clearSelection();
  controller.dataReady = false;
  controller.loadedPath = "";
  controller.docText = "";
  controller.documentTags = [];
  controller.allTasks = [];
  controller.tasks = [];
  controller.taskIndex = 0;
  controller.documentError = "";
}

function indexForPath(controller, path) {
  for (var i = 0; i < controller.lists.length; i++) {
    if (String(controller.lists[i].path) === String(path || "")) return i;
  }
  return -1;
}

function selectList(controller, index) {
  if (index < 0 || index >= controller.lists.length) return;
  var previousPath = controller.currentPath;
  controller.listIndex = index;
  controller.requestListReveal(index);
  if (controller.currentPath !== previousPath) {
    controller.filterText = "";
    clearDocument(controller);
    controller.requestRead(controller.currentPath);
  }
  controller.queueSessionSave();
}

function moveList(controller, delta) {
  if (!controller.lists.length) return;
  selectList(controller, ((controller.listIndex + delta) % controller.lists.length + controller.lists.length) % controller.lists.length);
}

function rebuildTasks(controller) {
  var parsed = TodoDoc.parse(controller.docText);
  var visible = [];
  for (var i = 0; i < parsed.length; i++) {
    var row = parsed[i];
    row.sourceIndex = i;
    if (TodoDoc.matches(row, controller.filterText)) visible.push(row);
  }
  controller.allTasks = parsed;
  controller.tasks = visible;
  if (!controller.allTasks.length) controller.taskIndex = 0;
  else if (controller.taskIndex < 0 || controller.taskIndex >= controller.allTasks.length)
    controller.taskIndex = Math.max(0, Math.min(controller.taskIndex, controller.allTasks.length - 1));
  if (visible.length && visibleIndexForSource(controller, controller.taskIndex, visible) < 0)
    controller.taskIndex = visible[0].sourceIndex;
  revealSelectedTask(controller);
}

function visibleIndexForSource(controller, sourceIndex, rows) {
  var values = rows === undefined ? controller.tasks : rows;
  for (var i = 0; i < values.length; i++) if (values[i].sourceIndex === sourceIndex) return i;
  return -1;
}

function revealSelectedTask(controller) {
  var visible = controller.selectedVisibleIndex;
  if (visible >= 0) controller.requestTaskReveal(visible);
}

function setTaskIndex(controller, sourceIndex) {
  if (!controller.allTasks.length) {
    controller.taskIndex = 0;
    return;
  }
  controller.taskIndex = Math.max(0, Math.min(Number(sourceIndex), controller.allTasks.length - 1));
  revealSelectedTask(controller);
}

function setTaskVisibleIndex(controller, index) {
  if (!controller.tasks.length) return;
  var visible = Math.max(0, Math.min(Number(index), controller.tasks.length - 1));
  setTaskIndex(controller, controller.tasks[visible].sourceIndex);
}

function moveTask(controller, delta) {
  if (!controller.tasks.length) return;
  var visible = controller.selectedVisibleIndex;
  if (visible < 0) visible = 0;
  setTaskVisibleIndex(controller, Math.max(0, Math.min(visible + delta, controller.tasks.length - 1)));
}

function selectedTask(controller) {
  if (!controller.dataReady || controller.loadedPath !== controller.currentPath
      || controller.taskIndex < 0 || controller.taskIndex >= controller.allTasks.length) return null;
  return controller.allTasks[controller.taskIndex];
}

function beginFilter(controller) {
  controller.clearSelection();
  controller.activePane = "tasks";
  controller.mode = "filter";
  controller.requestKeyboardFocus();
}

function appendFilterCharacter(controller, character) { controller.filterText += character; }
function removeFilterCharacter(controller) { controller.filterText = controller.filterText.slice(0, -1); }
function clearFilter(controller) { controller.filterText = ""; controller.mode = "normal"; }
function finishFilter(controller) { controller.mode = "normal"; }

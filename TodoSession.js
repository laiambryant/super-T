.pragma library

function tryRestore(controller) {
  if (!controller.opened || controller.restoreApplied || !controller.initialScanReady
      || !controller.sessionLoaded) return;
  if (!controller.lists.length) {
    controller.restoreApplied = true;
    return;
  }

  var saved = controller.savedPosition || ({});
  var targetIndex = saved.path ? controller.indexForPath(saved.path) : -1;
  if (targetIndex >= 0 && targetIndex !== controller.listIndex) {
    controller.selectList(targetIndex);
    return;
  }
  if (!controller.dataReady || controller.loadedPath !== controller.currentPath) {
    if (controller.initialReadReady) controller.restoreApplied = true;
    return;
  }

  controller.filterText = "";
  var source = -1;
  if (saved.line !== undefined) {
    for (var i = 0; i < controller.allTasks.length; i++) {
      if (controller.allTasks[i].line === Number(saved.line)
          && (saved.text === undefined || controller.allTasks[i].text === String(saved.text))) {
        source = i;
        break;
      }
    }
  }
  if (source < 0 && saved.text !== undefined) {
    for (var j = 0; j < controller.allTasks.length; j++) {
      if (controller.allTasks[j].text === String(saved.text)) {
        source = j;
        break;
      }
    }
  }
  if (source < 0 && saved.taskIndex !== undefined) source = Number(saved.taskIndex);
  if (controller.allTasks.length)
    controller.setTaskIndex(Math.max(0, Math.min(source < 0 ? 0 : source, controller.allTasks.length - 1)));
  controller.restoreApplied = true;
  queueSessionSave(controller);
}

function positionSnapshot(controller) {
  if (!controller.currentPath) return null;
  var task = controller.selectedTask();
  var position = { path: controller.currentPath, taskIndex: controller.taskIndex };
  if (task) {
    position.line = task.line;
    position.text = task.text;
  }
  return position;
}

function queueSessionSave(controller) {
  if (!controller.restoreApplied) return;
  controller.sessionSavePending = true;
  if (controller.dataReady && controller.loadedPath === controller.currentPath)
    controller.armSessionSaveTimer();
}

function saveSessionNow(controller) {
  var position = positionSnapshot(controller);
  if (!position || !controller.directory || !controller.restoreApplied || !controller.dataReady
      || controller.loadedPath !== controller.currentPath) return;
  controller.saveRequestId = controller.invoke("save_session", { position: position });
  if (controller.saveRequestId >= 0) controller.sessionSavePending = false;
}

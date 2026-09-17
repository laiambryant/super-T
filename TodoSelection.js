.pragma library

function clear(controller) { controller.selectionAnchor = -1; }

function toggle(controller) {
  if (controller.selectionAnchor >= 0) clear(controller);
  else if (controller.selectedTask() && !controller.mutationBusy) {
    controller.activePane = "tasks";
    controller.selectionAnchor = controller.taskIndex;
  }
}

function indices(controller) {
  var cursor = controller.selectedVisibleIndex;
  if (cursor < 0) return [];
  if (controller.selectionAnchor < 0) return [controller.taskIndex];
  var anchor = controller.visibleIndexForSource(controller.selectionAnchor);
  if (anchor < 0) return [controller.taskIndex];
  return controller.tasks.slice(Math.min(anchor, cursor), Math.max(anchor, cursor) + 1)
    .map(function(task) { return task.sourceIndex; });
}

function rows(controller) {
  if (!controller.dataReady || controller.loadedPath !== controller.currentPath) return [];
  return indices(controller).map(function(index) { return controller.allTasks[index]; });
}

function focusPane(controller, pane) {
  if (controller.activePane !== pane) clear(controller);
  controller.activePane = pane;
  controller.requestKeyboardFocus();
}

function move(controller, delta) {
  if (controller.activePane === "lists") controller.moveList(delta);
  else controller.moveTask(delta);
}

function edge(controller, last) {
  if (controller.activePane === "lists") controller.selectList(last ? controller.lists.length - 1 : 0);
  else controller.setTaskVisibleIndex(last ? controller.tasks.length - 1 : 0);
}

function toggleHelp(controller) {
  if (controller.mode === "help") controller.mode = controller.helpReturnMode;
  else {
    controller.helpReturnMode = controller.mode;
    controller.mode = "help";
    controller.helpScroll(0, true);
  }
  controller.requestKeyboardFocus();
}

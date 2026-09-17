.pragma library

function accept(event) {
  event.accepted = true;
}

function handleInput(controller, event) {
  if (event.key === Qt.Key_Escape) {
    controller.cancelInput();
    accept(event);
  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
    if (controller.multilineInput && !(event.modifiers & Qt.ControlModifier)) return;
    controller.commitInput();
    accept(event);
  }
}

function handleMovePicker(controller, event) {
  if (event.key === Qt.Key_Escape) {
    controller.cancelMove();
  } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
    controller.moveMoveTarget(-1);
  } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
    controller.moveMoveTarget(1);
  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
    controller.confirmMove();
  } else {
    return;
  }
  accept(event);
}

function handleFilter(controller, event) {
  if (event.key === Qt.Key_Escape) {
    controller.clearFilter();
  } else if (event.key === Qt.Key_Backspace) {
    controller.removeFilterCharacter();
  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
    controller.finishFilter();
  } else if (event.key === Qt.Key_Up) {
    controller.moveTask(-1);
  } else if (event.key === Qt.Key_Down) {
    controller.moveTask(1);
  } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
      && event.text.charCodeAt(0) !== 127) {
    controller.appendFilterCharacter(event.text);
  } else {
    return;
  }
  accept(event);
}

function handle(controller, event) {
  if (controller.mode === "input") return;
  if (controller.mode === "help") {
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Question || event.text === "?")
      controller.toggleHelp();
    else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) controller.helpScroll(1, false);
    else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) controller.helpScroll(-1, false);
    else if (event.key === Qt.Key_PageDown) controller.helpScroll(8, false);
    else if (event.key === Qt.Key_PageUp) controller.helpScroll(-8, false);
    else if (event.key === Qt.Key_Home) controller.helpScroll(0, true);
    else if (event.key === Qt.Key_End) controller.helpScroll(1, true);
    accept(event);
    return;
  }
  if (controller.mode === "filter") {
    handleFilter(controller, event);
    return;
  }
  if (event.key === Qt.Key_Question || event.text === "?") {
    controller.toggleHelp();
    accept(event);
    return;
  }
  if (controller.mode === "move") {
    handleMovePicker(controller, event);
    return;
  }
  if (controller.mode === "summary") {
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_S) {
      controller.toggleSummary();
      accept(event);
    } else if (event.key === Qt.Key_R) {
      controller.refreshSummary();
      accept(event);
    }
    return;
  }

  var shift = (event.modifiers & Qt.ShiftModifier) !== 0;
  switch (event.key) {
  case Qt.Key_Escape:
    if (controller.selecting) controller.clearSelection();
    else if (controller.filterText) controller.clearFilter();
    else controller.dismiss();
    break;
  case Qt.Key_Down:
  case Qt.Key_J:
    if (shift && controller.activePane === "tasks") controller.reorderSelected(1);
    else controller.moveCurrent(1);
    break;
  case Qt.Key_Up:
  case Qt.Key_K:
    if (shift && controller.activePane === "tasks") controller.reorderSelected(-1);
    else controller.moveCurrent(-1);
    break;
  case Qt.Key_Left:
  case Qt.Key_H: controller.focusPane("lists"); break;
  case Qt.Key_Right:
  case Qt.Key_L: controller.focusPane("tasks"); break;
  case Qt.Key_Tab: if (controller.activePane === "tasks") controller.makeSelectedSubtask(); break;
  case Qt.Key_Backtab: controller.moveList(-1); break;
  case Qt.Key_PageDown: controller.moveCurrent(10); break;
  case Qt.Key_PageUp: controller.moveCurrent(-10); break;
  case Qt.Key_Home: controller.currentEdge(false); break;
  case Qt.Key_End: controller.currentEdge(true); break;
  case Qt.Key_G: controller.currentEdge(shift); break;
  case Qt.Key_V: if (controller.activePane === "tasks") controller.toggleSelection(); break;
  case Qt.Key_Less: if (controller.activePane === "tasks") controller.promoteSelected(); break;
  case Qt.Key_Greater: if (controller.activePane === "tasks") controller.makeSelectedSubtask(); break;
  case Qt.Key_Space:
  case Qt.Key_X: if (controller.activePane === "tasks") controller.toggleSelected(); break;
  case Qt.Key_Return:
  case Qt.Key_Enter:
  case Qt.Key_E:
    if (controller.activePane === "lists") controller.focusPane("tasks");
    else controller.beginInput("edit");
    break;
  case Qt.Key_N: if (shift) controller.beginInput("list"); else controller.beginInput("add"); break;
  case Qt.Key_D: if (controller.activePane === "tasks") controller.deleteSelected(); break;
  case Qt.Key_U: controller.undo(); break;
  case Qt.Key_M: if (controller.activePane === "tasks") controller.beginMove(); break;
  case Qt.Key_T: controller.beginInput("tags"); break;
  case Qt.Key_S: controller.toggleSummary(); break;
  case Qt.Key_R: controller.refresh(); break;
  case Qt.Key_Slash: controller.beginFilter(); break;
  default: return;
  }
  accept(event);
}

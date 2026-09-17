.pragma library

function invoke(controller, op, payload) {
  if (!controller.backend || typeof controller.backend.request !== "function") {
    controller.flash("Todo service is unavailable");
    return -1;
  }
  return controller.backend.request(op, payload || {});
}

function open(controller) {
  controller.clearSelection();
  controller.activePane = "tasks";
  controller.opened = true;
  controller.mode = "normal";
  controller.filterText = "";
  if (controller.configurationError) controller.flash(controller.configurationError);
  else if (controller.autoStartBackend) startOpenLoad(controller);
  controller.requestKeyboardFocus();
}

function close(controller) {
  controller.clearSelection();
  controller.queueSessionSave();
  controller.stopSessionSaveTimer();
  controller.saveSessionNow();
  controller.opened = false;
  controller.mode = "normal";
  controller.clearInput();
  controller.moveTaskSnapshot = null;
  controller.moveTargets = [];
  controller.barRefreshRequested();
}

function dismiss(controller) {
  close(controller);
  controller.dismissed();
}

function toggle(controller) {
  if (controller.opened) dismiss(controller);
  else open(controller);
}

function startOpenLoad(controller) {
  if (!controller.directory) {
    controller.flash("Choose a valid todo directory");
    return;
  }
  controller.initialScanReady = false;
  controller.initialReadReady = false;
  controller.sessionLoaded = false;
  controller.restoreApplied = false;
  controller.savedPosition = null;
  refreshLists(controller);
  controller.sessionRequestId = invoke(controller, "session", {});
}

function refresh(controller) {
  refreshLists(controller);
  reloadCurrentFromDisk(controller);
  controller.flash("Reloading");
}

function refreshLists(controller) {
  if (!controller.directory || controller.configurationError) return;
  if (controller.scanInFlight) {
    controller.scanAgain = true;
    return;
  }
  controller.scanInFlight = true;
  controller.scanRequestId = invoke(controller, "scan", {});
  if (controller.scanRequestId < 0) controller.scanInFlight = false;
}

function reloadCurrentFromDisk(controller) {
  if (!controller.currentPath || !controller.opened) return;
  requestRead(controller, controller.currentPath);
}

function requestRead(controller, path) {
  if (!path || controller.configurationError) return;
  controller.readRequestId = invoke(controller, "read", { path: path });
}

function toggleSummary(controller) {
  if (controller.mode === "summary") {
    controller.mode = "normal";
    controller.requestKeyboardFocus();
  } else {
    controller.mode = "summary";
    refreshSummary(controller);
    controller.requestKeyboardFocus();
  }
}

function refreshSummary(controller) {
  controller.summaryLoading = true;
  controller.summaryRequestId = invoke(controller, "summary", {});
  if (controller.summaryRequestId < 0) controller.summaryLoading = false;
}

function handleSuccess(controller, op, requestId, data) {
  if (op === "scan" && requestId === controller.scanRequestId) {
    controller.scanInFlight = false;
    controller.applyScan(data);
    if (controller.scanAgain) {
      controller.scanAgain = false;
      refreshLists(controller);
    }
    return;
  }
  if (op === "read" && requestId === controller.readRequestId) {
    controller.applyRead(data, data.path);
    return;
  }
  if (op === "session" && requestId === controller.sessionRequestId) {
    controller.savedPosition = data.position || null;
    controller.sessionLoaded = true;
    controller.tryRestore();
    return;
  }
  if (op === "summary" && requestId === controller.summaryRequestId) {
    controller.summary = data;
    controller.summaryLoading = false;
    return;
  }
  if (op === "save_session" && requestId === controller.saveRequestId) return;
  if (!controller.pendingMutation || controller.pendingMutation.generation !== controller.directoryGeneration
      || controller.pendingMutation.op !== op
      || (controller.pendingMutation.requestId >= 0 && requestId !== controller.pendingMutation.requestId)) return;
  controller.applyMutationSuccess(data);
}

function handleFailure(controller, op, requestId, error) {
  var message = String(error || "Todo service request failed");
  if (op === "scan" && requestId === controller.scanRequestId) {
    controller.scanInFlight = false;
    controller.scanOk = false;
    controller.flash(message);
    if (controller.scanAgain) {
      controller.scanAgain = false;
      refreshLists(controller);
    }
    return;
  }
  if (op === "read" && requestId === controller.readRequestId) {
    controller.clearDocument();
    controller.documentError = message;
    controller.initialReadReady = true;
    controller.tryRestore();
    controller.flash(message);
    return;
  }
  if (op === "session" && requestId === controller.sessionRequestId) {
    controller.savedPosition = null;
    controller.sessionLoaded = true;
    controller.tryRestore();
    controller.flash("Could not restore saved position: " + message);
    return;
  }
  if (op === "summary" && requestId === controller.summaryRequestId) {
    controller.summaryLoading = false;
    controller.flash(message);
    return;
  }
  if (op === "save_session" && requestId === controller.saveRequestId) {
    controller.sessionSavePending = true;
    controller.flash("Could not save position: " + message);
    return;
  }
  if (!controller.pendingMutation || controller.pendingMutation.generation !== controller.directoryGeneration
      || controller.pendingMutation.op !== op
      || (controller.pendingMutation.requestId >= 0 && requestId !== controller.pendingMutation.requestId)) return;
  var pending = controller.pendingMutation;
  controller.pendingMutation = null;
  controller.mutationBusy = false;
  if (pending.context.input) controller.inputError = message;
  else controller.flash(message);
  if (/conflict|changed/i.test(message) && pending.context.path) requestRead(controller, pending.context.path);
}

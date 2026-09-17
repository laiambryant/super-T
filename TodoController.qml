import QtQuick
import "TodoKeymap.js" as TodoKeymap
import "TodoNavigation.js" as Navigation
import "TodoSession.js" as Session
import "TodoMutations.js" as Mutations
import "TodoRequests.js" as Requests
import "TodoSelection.js" as Selection

Item {
  id: root
  visible: false
  width: 0
  height: 0

  property string directory: ""
  property string configurationError: ""
  property bool autoStartBackend: true
  property var backend: null

  property bool opened: false
  property bool scanOk: true
  property bool dataReady: false
  property var lists: []
  property int listIndex: -1
  readonly property var currentList: listIndex >= 0 && listIndex < lists.length ? lists[listIndex] : null
  readonly property string currentPath: currentList ? String(currentList.path) : ""

  property string loadedPath: ""
  property string docText: ""
  property var documentTags: []
  property var allTasks: []
  property var tasks: []
  property int taskIndex: 0
  readonly property int selectedVisibleIndex: visibleIndexForSource(taskIndex, tasks)
  property string filterText: ""
  property string documentError: ""
  property string activePane: "tasks"
  property int selectionAnchor: -1
  readonly property bool selecting: selectionAnchor >= 0
  readonly property var selectedIndices: Selection.indices(root)
  property string helpReturnMode: "normal"

  property string mode: "normal"
  property string inputPurpose: ""
  property string inputText: ""
  property string inputError: ""
  property string inputPath: ""
  property string inputExpected: ""
  property int inputLine: -1
  property var inputLines: []
  readonly property bool multilineInput: inputPurpose === "edit" && inputLines.length > 1
  property var moveTaskSnapshot: null
  property var moveTargets: []
  property int moveTargetIndex: 0
  readonly property var selectedMoveTarget: moveTargetIndex >= 0 && moveTargetIndex < moveTargets.length
    ? moveTargets[moveTargetIndex] : null

  property var summary: ({ total: 0, done: 0, percent: 0, closedToday: 0, streak: 0 })
  property bool summaryLoading: false
  property string statusText: ""
  property bool mutationBusy: false
  property var pendingMutation: null
  property var undoTokens: []

  property int scanRequestId: -1
  property bool scanInFlight: false
  property bool scanAgain: false
  property int readRequestId: -1
  property int sessionRequestId: -1
  property int summaryRequestId: -1
  property int saveRequestId: -1
  property int directoryGeneration: 0
  property bool initialScanReady: false
  property bool initialReadReady: false
  property bool sessionLoaded: false
  property bool restoreApplied: false
  property var savedPosition: null
  property string pendingSelectPath: ""
  property bool sessionSavePending: false

  signal requestKeyboardFocus()
  signal requestInputFocus()
  signal requestTaskReveal(int visibleIndex)
  signal requestListReveal(int index)
  signal requestMoveTargetReveal(int index)
  signal barRefreshRequested()
  signal dismissed()
  signal helpScroll(int delta, bool edge)

  onFilterTextChanged: rebuildTasks()
  onTaskIndexChanged: {
    revealSelectedTask()
    queueSessionSave()
  }
  onDirectoryChanged: {
    Navigation.resetForDirectory(root)
    if (opened && !configurationError && autoStartBackend) startOpenLoad()
  }

  Connections {
    target: root.backend
    function onSucceeded(op, requestId, data) { root.handleSuccess(op, requestId, data) }
    function onFailed(op, requestId, error) { root.handleFailure(op, requestId, error) }
  }

  Timer {
    id: statusTimer
    interval: 2800
    onTriggered: root.statusText = ""
  }

  Timer {
    id: sessionSaveTimer
    interval: 350
    repeat: false
    onTriggered: root.saveSessionNow()
  }

  function flash(message) {
    statusText = String(message || "")
    statusTimer.restart()
  }

  function armSessionSaveTimer() { sessionSaveTimer.restart() }
  function stopSessionSaveTimer() { sessionSaveTimer.stop() }

  function invoke(op, payload) { return Requests.invoke(root, op, payload) }
  function open() { Requests.open(root) }
  function close() { Requests.close(root) }
  function dismiss() { Requests.dismiss(root) }
  function toggle() { Requests.toggle(root) }
  function startOpenLoad() { Requests.startOpenLoad(root) }
  function refresh() { Requests.refresh(root) }
  function refreshLists() { Requests.refreshLists(root) }
  function reloadCurrentFromDisk() { Requests.reloadCurrentFromDisk(root) }
  function requestRead(path) { Requests.requestRead(root, path) }
  function toggleSummary() { Requests.toggleSummary(root) }
  function refreshSummary() { Requests.refreshSummary(root) }
  function handleSuccess(op, requestId, data) { Requests.handleSuccess(root, op, requestId, data) }
  function handleFailure(op, requestId, error) { Requests.handleFailure(root, op, requestId, error) }

  function applyScan(data) { Navigation.applyScan(root, data) }
  function applyRead(data, requestedPath) { Navigation.applyRead(root, data, requestedPath) }
  function clearDocument() { Navigation.clearDocument(root) }
  function indexForPath(path) { return Navigation.indexForPath(root, path) }
  function selectList(index) { Navigation.selectList(root, index) }
  function moveList(delta) { Navigation.moveList(root, delta) }
  function rebuildTasks() { Navigation.rebuildTasks(root) }
  function visibleIndexForSource(sourceIndex, rows) {
    return Navigation.visibleIndexForSource(root, sourceIndex, rows)
  }
  function revealSelectedTask() { Navigation.revealSelectedTask(root) }
  function setTaskIndex(sourceIndex) { Navigation.setTaskIndex(root, sourceIndex) }
  function setTaskVisibleIndex(index) { Navigation.setTaskVisibleIndex(root, index) }
  function moveTask(delta) { Navigation.moveTask(root, delta) }
  function selectedTask() { return Navigation.selectedTask(root) }
  function beginFilter() { Navigation.beginFilter(root) }
  function appendFilterCharacter(character) { Navigation.appendFilterCharacter(root, character) }
  function removeFilterCharacter() { Navigation.removeFilterCharacter(root) }
  function clearFilter() { Navigation.clearFilter(root) }
  function finishFilter() { Navigation.finishFilter(root) }

  function tryRestore() { Session.tryRestore(root) }
  function positionSnapshot() { return Session.positionSnapshot(root) }
  function scheduleSessionSave() { Session.queueSessionSave(root) }
  function queueSessionSave() { Session.queueSessionSave(root) }
  function saveSessionNow() { Session.saveSessionNow(root) }

  function toggleTaskAt(sourceIndex) { Mutations.toggleTaskAt(root, sourceIndex) }
  function toggleSelected() { Mutations.toggleSelected(root) }
  function deleteSelected() { Mutations.deleteSelected(root) }
  function reorderSelected(delta) { Mutations.reorderSelected(root, delta) }
  function makeSelectedSubtask() { Mutations.makeSelectedSubtask(root) }
  function beginInput(purpose) { Mutations.beginInput(root, purpose) }
  function clearInput() { Mutations.clearInput(root) }
  function cancelInput() { Mutations.cancelInput(root) }
  function commitInput() { Mutations.commitInput(root) }
  function parseTags(text) { return Mutations.parseTags(text) }
  function beginMove() { Mutations.beginMove(root) }
  function moveMoveTarget(delta) { Mutations.moveMoveTarget(root, delta) }
  function selectMoveTarget(index) { Mutations.selectMoveTarget(root, index) }
  function cancelMove() { Mutations.cancelMove(root) }
  function confirmMove() { Mutations.confirmMove(root) }
  function beginMutation(op, payload, context) { return Mutations.startMutation(root, op, payload, context) }
  function undo() { Mutations.undo(root) }
  function applyMutationSuccess(data) { Mutations.applyMutationSuccess(root, data) }
  function applyServerText(path, text, tags) { Mutations.applyServerText(root, path, text, tags) }
  function insertCreatedList(data) { Mutations.insertCreatedList(root, data) }
  function selectTaskAtLine(line) { Mutations.selectTaskAtLine(root, line) }

  function dispatchKey(event) { TodoKeymap.handle(root, event) }
  function dispatchInputKey(event) { TodoKeymap.handleInput(root, event) }
  function clearSelection() { Selection.clear(root) }
  function toggleSelection() { Selection.toggle(root) }
  function selectedRows() { return Selection.rows(root) }
  function focusPane(pane) { Selection.focusPane(root, pane) }
  function moveCurrent(delta) { Selection.move(root, delta) }
  function currentEdge(last) { Selection.edge(root, last) }
  function toggleHelp() { Selection.toggleHelp(root) }
  function promoteSelected() { Mutations.promoteSelected(root) }
}

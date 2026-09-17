import QtQuick
import Quickshell
ShellRoot {
  id: root

  readonly property string todoDirectory: String(Quickshell.env("SUPER_T_SMOKE_DIR") || "")
  readonly property string servicePath: String(Quickshell.env("SUPER_T_SERVICE_PATH") || "")
  property int phase: 0
  property bool finished: false

  function key(keyCode, modifiers) {
    return { key: keyCode, modifiers: modifiers || Qt.NoModifier, text: "", accepted: false }
  }

  function listIndex(name) {
    var ending = "/" + name + ".md"
    for (var i = 0; i < controller.lists.length; ++i) {
      if (String(controller.lists[i].path).slice(-ending.length) === ending) return i
    }
    return -1
  }

  function hasTag(tag) {
    for (var i = 0; i < controller.documentTags.length; ++i) {
      if (controller.documentTags[i] === tag) return true
    }
    return false
  }

  function fail(message) {
    if (finished) return
    finished = true
    console.error("Controller/service smoke failed at phase " + phase + ": " + message)
  }

  function pass() {
    if (finished) return
    finished = true
    console.log("Controller/service smoke passed: key, reorder, create, move, tags, and error UI")
  }

  function advance() {
    if (finished) return
    if (phase === 0) {
      if (!controller.restoreApplied || !controller.dataReady) return
      if (controller.lists.length !== 3 || listIndex("alpha") < 0 || listIndex("beta") < 0
          || listIndex("complex") < 0) {
        fail("initial scan did not load the temporary lists")
        return
      }
      if (String(controller.currentPath).slice(-9) !== "/alpha.md" || controller.allTasks.length !== 2) {
        fail("initial read did not select alpha.md")
        return
      }
      controller.dispatchKey(key(Qt.Key_End))
      if (controller.taskIndex !== 1) {
        fail("End did not select the final task")
        return
      }
      controller.dispatchKey(key(Qt.Key_Space))
      phase = 1
      return
    }

    if (phase === 1) {
      if (controller.mutationBusy) return
      if (controller.docText.indexOf("- [x] second") < 0) {
        fail("Space did not persist the checkbox toggle: " + controller.statusText)
        return
      }
      controller.beginInput("add")
      controller.inputText = "added through service"
      controller.commitInput()
      phase = 2
      return
    }

    if (phase === 2) {
      if (controller.mutationBusy) return
      if (controller.docText.indexOf("added through service") < 0 || controller.allTasks.length !== 3) {
        fail("add input did not persist")
        return
      }
      controller.dispatchKey(key(Qt.Key_Up, Qt.ShiftModifier))
      phase = 20
      return
    }

    if (phase === 20) {
      if (controller.mutationBusy) return
      if (controller.taskIndex !== 1 || controller.allTasks[1].text !== "added through service") {
        fail("Shift+Up did not reorder and follow the task: " + controller.statusText)
        return
      }
      controller.dispatchKey(key(Qt.Key_J, Qt.ShiftModifier))
      phase = 21
      return
    }

    if (phase === 21) {
      if (controller.mutationBusy) return
      if (controller.taskIndex !== 2 || controller.allTasks[2].text !== "added through service") {
        fail("Shift+J did not reorder and follow the task: " + controller.statusText)
        return
      }
      controller.beginMove()
      var target = -1
      for (var i = 0; i < controller.moveTargets.length; ++i) {
        if (String(controller.moveTargets[i].path).slice(-8) === "/beta.md") target = i
      }
      if (target < 0) {
        fail("beta was not offered as a move target")
        return
      }
      controller.selectMoveTarget(target)
      controller.confirmMove()
      phase = 3
      return
    }

    if (phase === 3) {
      if (controller.mutationBusy) return
      if (controller.mode !== "normal" || controller.docText.indexOf("added through service") >= 0) {
        fail("move did not remove the selected task from alpha")
        return
      }
      controller.selectList(listIndex("beta"))
      phase = 4
      return
    }

    if (phase === 4) {
      if (!controller.dataReady || String(controller.currentPath).slice(-8) !== "/beta.md") return
      if (controller.docText.indexOf("added through service") < 0) {
        fail("move did not persist the selected task in beta")
        return
      }
      controller.beginInput("tags")
      controller.inputText = "work, urgent"
      controller.commitInput()
      phase = 5
      return
    }

    if (phase === 5) {
      if (controller.mutationBusy) return
      if (!hasTag("work") || !hasTag("urgent")) {
        fail("tags did not persist through the service")
        return
      }
      controller.selectList(listIndex("complex"))
      phase = 6
      return
    }

    if (phase === 6) {
      if (!controller.dataReady || String(controller.currentPath).slice(-11) !== "/complex.md") return
      controller.beginInput("tags")
      controller.inputText = "new"
      controller.commitInput()
      phase = 7
      return
    }

    if (phase === 7) {
      if (controller.mutationBusy) return
      if (controller.mode !== "input" || controller.inputText !== "new" || controller.inputError === "") {
        fail("unsupported tags did not remain actionable in the input UI")
        return
      }
      controller.cancelInput()
      controller.beginInput("list")
      controller.inputText = "created"
      controller.commitInput()
      phase = 8
      return
    }

    if (phase === 8) {
      if (controller.mutationBusy) return
      if (listIndex("created") < 0 || String(controller.currentPath).slice(-11) !== "/created.md") {
        fail("new list did not become selected")
        return
      }
      pass()
    }
  }

  BackendBridge {
    id: bridge
    directory: root.todoDirectory
    servicePath: root.servicePath
  }

  TodoController {
    id: controller
    directory: root.todoDirectory
    backend: bridge
  }

  Component.onCompleted: {
    if (!todoDirectory || !servicePath) {
      fail("SUPER_T_SMOKE_DIR or SUPER_T_SERVICE_PATH is not set")
      return
    }
    controller.open()
  }

  Timer {
    interval: 20
    repeat: true
    running: !root.finished
    onTriggered: root.advance()
  }

  Timer {
    interval: 10000
    running: !root.finished
    onTriggered: root.fail("timed out waiting for the controller/service flow")
  }
}

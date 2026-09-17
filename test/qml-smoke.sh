#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
qt_bin=${QT_BIN:-/usr/lib/qt6/bin}
qmllint=${QMLLINT:-$qt_bin/qmllint}
qmltestrunner=${QMLTESTRUNNER:-$qt_bin/qmltestrunner}
quickshell_bin=${QUICKSHELL:-quickshell}
omarchy_shell=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}

[[ -x $qmllint ]] || { echo "qmllint not found: $qmllint" >&2; exit 1; }
[[ -x $qmltestrunner ]] || { echo "qmltestrunner not found: $qmltestrunner" >&2; exit 1; }
command -v "$quickshell_bin" >/dev/null || { echo "quickshell not found: $quickshell_bin" >&2; exit 1; }
[[ -f $omarchy_shell/Commons/qmldir && -f $omarchy_shell/Ui/qmldir ]] || {
  echo "Omarchy QML modules not found under: $omarchy_shell" >&2
  exit 1
}
[[ -f $root/Todo.qml && -f $root/BarWidget.qml && -f $root/BackendBridge.qml && -f $root/service.py \
  && -f $root/TodoController.qml && -f $root/test/qml/tst_controller.qml \
  && -f $root/TodoDoc.js && -f $root/TodoKeymap.js && -f $root/TodoNavigation.js \
  && -f $root/TodoSession.js && -f $root/TodoMutations.js && -f $root/TodoRequests.js \
  && -f $root/test/qml/ShellImportSmoke.qml && -f $root/test/qml/BackendBridgeSmoke.qml \
  && -f $root/test/qml/ControllerServiceSmoke.qml ]] || {
  echo "QML smoke fixtures are incomplete" >&2
  exit 1
}

tmp=$(mktemp -d)
qs_pid=""
bridge_pid=""
controller_pid=""
wayland_pid=""
cleanup() {
  if [[ -n $qs_pid ]]; then
    kill "$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  if [[ -n $bridge_pid ]]; then
    kill "$bridge_pid" 2>/dev/null || true
    wait "$bridge_pid" 2>/dev/null || true
  fi
  if [[ -n $controller_pid ]]; then
    kill "$controller_pid" 2>/dev/null || true
    wait "$controller_pid" 2>/dev/null || true
  fi
  if [[ -n $wayland_pid ]]; then
    kill "$wayland_pid" 2>/dev/null || true
    wait "$wayland_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -m 700 "$tmp/runtime"
mkdir -p "$tmp/home" "$tmp/config" "$tmp/data" "$tmp/cache" "$tmp/state" "$tmp/imports/qs" \
  "$tmp/todos" "$tmp/bridge-qml" "$tmp/controller-qml"
printf '%s\n' '- [ ] bridge smoke' '- [x] done' > "$tmp/todos/alpha.md"
printf '%s\n' '- [ ] beta' > "$tmp/todos/beta.md"
cp "$root/BackendBridge.qml" "$tmp/bridge-qml/BackendBridge.qml"
cp "$root/test/qml/BackendBridgeSmoke.qml" "$tmp/bridge-qml/BackendBridgeSmoke.qml"

ln -s "$omarchy_shell/Commons" "$tmp/imports/qs/Commons"
ln -s "$omarchy_shell/Ui" "$tmp/imports/qs/Ui"

common_env=(
  env -i
  PATH="/usr/lib/qt6/bin:/usr/bin:/bin"
  HOME="$tmp/home"
  XDG_CONFIG_HOME="$tmp/config"
  XDG_DATA_HOME="$tmp/data"
  XDG_CACHE_HOME="$tmp/cache"
  XDG_STATE_HOME="$tmp/state"
  XDG_RUNTIME_DIR="$tmp/runtime"
  QT_QPA_PLATFORM=minimal
  QT_QUICK_BACKEND=software
  QSG_RHI_BACKEND=software
  QML2_IMPORT_PATH="$tmp/imports:$root"
)

"$qmllint" -I "$tmp/imports" "$root/test/qml/ShellImportSmoke.qml"
"$qmllint" -I "$root" "$root/TodoController.qml" "$root/TodoPanel.qml" "$root/TodoButton.qml" \
  "$root/TodoSidebar.qml" "$root/TodoTaskList.qml" "$root/TodoInputBar.qml" \
  "$root/TodoSummary.qml" "$root/TodoMovePicker.qml" "$root/TodoHelp.qml" \
  "$root/test/qml/tst_controller.qml" "$root/test/qml/tst_panel.qml"
"$qmllint" -I "$tmp/imports" -I "$root" "$root/Todo.qml" "$root/BarWidget.qml"

"${common_env[@]}" "$qmltestrunner" \
  -input "$root/test/qml" \
  -import "$root"

"${common_env[@]}" "$quickshell_bin" --no-duplicate --path "$root/test/qml/ShellImportSmoke.qml" >"$tmp/quickshell.log" 2>&1 &
qs_pid=$!

loaded=0
for _ in $(seq 1 40); do
  if grep -Fq "Configuration Loaded" "$tmp/quickshell.log"; then
    loaded=1
    break
  fi
  if ! kill -0 "$qs_pid" 2>/dev/null; then
    cat "$tmp/quickshell.log" >&2
    exit 1
  fi
  sleep 0.1
done

if [[ $loaded -ne 1 ]] || ! kill -0 "$qs_pid" 2>/dev/null; then
  cat "$tmp/quickshell.log" >&2
  echo "Quickshell smoke configuration did not remain loaded" >&2
  exit 1
fi

kill "$qs_pid" 2>/dev/null || true
wait "$qs_pid" 2>/dev/null || true
qs_pid=""

"${common_env[@]}" \
  QML2_IMPORT_PATH="$tmp/imports" \
  SUPER_T_SMOKE_DIR="$tmp/todos" \
  SUPER_T_SERVICE_PATH="$root/service.py" \
  "$quickshell_bin" --no-duplicate --path "$tmp/bridge-qml/BackendBridgeSmoke.qml" >"$tmp/bridge.log" 2>&1 &
bridge_pid=$!
bridge_ok=0
for _ in $(seq 1 60); do
  if grep -Fq "BackendBridge smoke passed" "$tmp/bridge.log"; then
    bridge_ok=1
    break
  fi
  if grep -Fq "BackendBridge smoke failed" "$tmp/bridge.log" || ! kill -0 "$bridge_pid" 2>/dev/null; then
    cat "$tmp/bridge.log" >&2
    exit 1
  fi
  sleep 0.1
done
if [[ $bridge_ok -ne 1 ]]; then
  cat "$tmp/bridge.log" >&2
  echo "BackendBridge smoke did not complete" >&2
  exit 1
fi

kill "$bridge_pid" 2>/dev/null || true
wait "$bridge_pid" 2>/dev/null || true
bridge_pid=""

printf '%s\n' '- [ ] first' '- [ ] second' > "$tmp/todos/alpha.md"
printf '%s\n' '---' 'tags: &anchor [old]' '---' '# Complex' > "$tmp/todos/complex.md"
for source in BackendBridge.qml TodoController.qml TodoDoc.js TodoKeymap.js TodoNavigation.js \
  TodoSession.js TodoMutations.js TodoRequests.js TodoSelection.js; do
  cp "$root/$source" "$tmp/controller-qml/$source"
done
cp "$root/test/qml/ControllerServiceSmoke.qml" "$tmp/controller-qml/ControllerServiceSmoke.qml"
"${common_env[@]}" \
  QML2_IMPORT_PATH="$tmp/imports" \
  SUPER_T_SMOKE_DIR="$tmp/todos" \
  SUPER_T_SERVICE_PATH="$root/service.py" \
  "$quickshell_bin" --no-duplicate --path "$tmp/controller-qml/ControllerServiceSmoke.qml" >"$tmp/controller.log" 2>&1 &
controller_pid=$!
controller_ok=0
for _ in $(seq 1 120); do
  if grep -Fq "Controller/service smoke passed" "$tmp/controller.log"; then
    controller_ok=1
    break
  fi
  if grep -Fq "Controller/service smoke failed" "$tmp/controller.log" || ! kill -0 "$controller_pid" 2>/dev/null; then
    cat "$tmp/controller.log" >&2
    exit 1
  fi
  sleep 0.1
done
if [[ $controller_ok -ne 1 ]]; then
  cat "$tmp/controller.log" >&2
  echo "Controller/service smoke did not complete" >&2
  exit 1
fi

kill "$controller_pid" 2>/dev/null || true
wait "$controller_pid" 2>/dev/null || true
controller_pid=""

if [[ ${WAYLAND_SMOKE:-0} == 1 ]]; then
  mkdir -p "$tmp/wayland-home/.config/omarchy" "$tmp/wayland-data" "$tmp/wayland-cache" \
    "$tmp/wayland-state" "$tmp/wayland-todos"
  printf '%s\n' '- [ ] hidden panel smoke' > "$tmp/wayland-todos/inbox.md"
  printf '{"plugins":[{"id":"liambryant.todo","dir":"%s"}]}\n' "$tmp/wayland-todos" \
    > "$tmp/wayland-home/.config/omarchy/shell.json"
  wayland_env=(
    env -i
    PATH="/usr/lib/qt6/bin:/usr/bin:/bin"
    HOME="$tmp/wayland-home"
    XDG_CONFIG_HOME="$tmp/wayland-home/.config"
    XDG_DATA_HOME="$tmp/wayland-data"
    XDG_CACHE_HOME="$tmp/wayland-cache"
    XDG_STATE_HOME="$tmp/wayland-state"
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
    LC_ALL=C.UTF-8
    QT_QPA_PLATFORM=wayland
    QT_QUICK_BACKEND=software
    QSG_RHI_BACKEND=software
    QML2_IMPORT_PATH="$tmp/imports:$root"
  )
  "${wayland_env[@]}" python3 -B "$root/test/wayland_preflight.py"
  "${wayland_env[@]}" "$quickshell_bin" --no-duplicate --path "$root/Todo.qml" >"$tmp/wayland.log" 2>&1 &
  wayland_pid=$!
  wayland_loaded=0
  for _ in $(seq 1 50); do
    if grep -Fq "Configuration Loaded" "$tmp/wayland.log"; then
      wayland_loaded=1
      break
    fi
    if ! kill -0 "$wayland_pid" 2>/dev/null; then
      cat "$tmp/wayland.log" >&2
      exit 1
    fi
    sleep 0.1
  done
  if [[ $wayland_loaded -ne 1 ]] || ! kill -0 "$wayland_pid" 2>/dev/null; then
    cat "$tmp/wayland.log" >&2
    echo "Hidden Todo.qml configuration did not remain loaded" >&2
    exit 1
  fi
  kill "$wayland_pid" 2>/dev/null || true
  wait "$wayland_pid" 2>/dev/null || true
  wayland_pid=""
  echo "Hidden Todo.qml Wayland load passed"
fi

echo "QML controller, Quickshell imports, BackendBridge, and service flow passed"

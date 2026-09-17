import contextlib
import errno
import io
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import wayland_preflight


ROOT = Path(__file__).resolve().parent.parent


class PreflightCase(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.runtime = Path(temporary.name)
        environment = patch.dict(os.environ, {
            "WAYLAND_DISPLAY": "wayland-test",
            "XDG_RUNTIME_DIR": str(self.runtime),
        }, clear=True)
        environment.start()
        self.addCleanup(environment.stop)

    def probe(self):
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            status = wayland_preflight.main()
        return status, output.getvalue()

    def assert_failure(self, detail):
        status, output = self.probe()
        self.assertEqual(status, 1)
        self.assertIn("WAYLAND_SMOKE=1 preflight failed", output)
        self.assertIn(detail, output)
        self.assertIn("permitted desktop", output)
        self.assertIn("make test-qml without WAYLAND_SMOKE=1", output)
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_missing_session_variables(self):
        for name in ("WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"):
            with self.subTest(name=name), patch.dict(os.environ, {name: ""}), \
                    patch.object(socket, "socket") as create_socket:
                self.assert_failure("both variables must be set")
                create_socket.assert_not_called()

    def test_relative_and_absolute_display_paths_and_cleanup(self):
        for display in ("wayland-test", "/another/runtime/wayland-test"):
            with self.subTest(display=display), patch.dict(os.environ, {"WAYLAND_DISPLAY": display}), \
                    patch.object(socket, "socket") as create_socket:
                self.assertEqual(self.probe(), (0, ""))
                create_socket.assert_called_once_with(socket.AF_UNIX, socket.SOCK_STREAM)
                connection = create_socket.return_value.__enter__.return_value
                connection.settimeout.assert_called_once_with(2)
                connection.connect.assert_called_once_with(os.path.join(self.runtime, display))
                create_socket.return_value.__exit__.assert_called_once()
                self.assertEqual(list(self.runtime.iterdir()), [])

    def test_socket_creation_denied(self):
        with patch.object(socket, "socket", side_effect=PermissionError(errno.EPERM, "Operation not permitted")):
            self.assert_failure("Operation not permitted")

    def test_connection_failures(self):
        errors = [
            PermissionError(errno.EPERM, "Operation not permitted"),
            PermissionError(errno.EACCES, "Permission denied"),
            FileNotFoundError(errno.ENOENT, "No such file or directory"),
            ConnectionRefusedError(errno.ECONNREFUSED, "Connection refused"),
            TimeoutError("timed out"),
        ]
        for error in errors:
            with self.subTest(error=error), patch.object(socket, "socket") as create_socket:
                connection = create_socket.return_value.__enter__.return_value
                connection.connect.side_effect = error
                self.assert_failure(str(error))
                create_socket.return_value.__exit__.assert_called_once()

    def test_runtime_directory_creation_denied_after_connection(self):
        with patch.object(socket, "socket") as create_socket, \
                patch.object(tempfile, "TemporaryDirectory", side_effect=PermissionError(errno.EACCES, "Permission denied")):
            self.assert_failure("create a temporary directory in XDG_RUNTIME_DIR")
            create_socket.return_value.__enter__.return_value.connect.assert_called_once()


class SmokeScriptCase(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.root = self.base / "project"
        self.test = self.root / "test"
        self.test.mkdir(parents=True)
        for pattern in ("*.qml", "*.js", "*.py"):
            for source in ROOT.glob(pattern):
                (self.root / source.name).symlink_to(source)
        (self.test / "qml").symlink_to(ROOT / "test/qml", target_is_directory=True)
        shutil.copy2(ROOT / "test/qml-smoke.sh", self.test / "qml-smoke.sh")
        shutil.copy2(ROOT / "test/wayland_preflight.py", self.test / "wayland_preflight.py")
        for module in ("Commons", "Ui"):
            directory = self.base / "modules" / module
            directory.mkdir(parents=True)
            (directory / "qmldir").touch()
        self.temporary_runs = self.base / "runs"
        self.temporary_runs.mkdir()
        self.report = self.base / "gui.json"
        self.fake_qs = self.base / "quickshell"
        self.fake_qs.write_text(f"""#!{sys.executable}
import json, os, pathlib, sys, time
fixture = pathlib.Path(sys.argv[-1]).name
if fixture == 'Todo.qml':
    pathlib.Path({str(self.report)!r}).write_text(json.dumps(dict(os.environ)))
    if pathlib.Path({str(self.base / 'fail-gui')!r}).exists():
        print('Application load failed: regression sentinel', flush=True)
        sys.exit(17)
messages = {{
    'ShellImportSmoke.qml': 'Configuration Loaded',
    'BackendBridgeSmoke.qml': 'BackendBridge smoke passed',
    'ControllerServiceSmoke.qml': 'Controller/service smoke passed',
    'Todo.qml': 'Configuration Loaded',
}}
print(messages[fixture], flush=True)
time.sleep(30)
""")
        self.fake_qs.chmod(0o755)
        self.environment = {
            **os.environ,
            "TMPDIR": str(self.temporary_runs),
            "QMLLINT": shutil.which("true"),
            "QMLTESTRUNNER": shutil.which("true"),
            "QUICKSHELL": str(self.fake_qs),
            "OMARCHY_SHELL_DIR": str(self.base / "modules"),

            "WAYLAND_DISPLAY": "wayland-test",
            "XDG_RUNTIME_DIR": str(self.base / "runtime"),
        }

    def run_smoke(self, wayland):
        result = subprocess.run(
            ["bash", str(self.test / "qml-smoke.sh")],
            env={**self.environment, "WAYLAND_SMOKE": str(wayland)},
            text=True, capture_output=True, timeout=15,
        )
        self.assertEqual(list(self.temporary_runs.iterdir()), [], result.stderr)
        return result

    def allow_probe(self):
        (self.test / "wayland_preflight.py").write_text(f"""
import json, os, pathlib
pathlib.Path({str(self.base / 'probe.json')!r}).write_text(json.dumps(dict(os.environ)))
""")

    def test_headless_does_not_probe_or_launch_gui(self):
        (self.test / "wayland_preflight.py").write_text("raise RuntimeError('probe must not run')\n")
        result = self.run_smoke(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.report.exists())

    def test_denied_connection_stops_before_gui_and_cleans_up(self):
        (self.test / "wayland_preflight.py").write_text(f"""
import errno, runpy, socket
from unittest.mock import patch
with patch.object(socket, 'socket', side_effect=PermissionError(errno.EPERM, 'Operation not permitted')):
    runpy.run_path({str(ROOT / 'test/wayland_preflight.py')!r}, run_name='__main__')
""")
        result = self.run_smoke(1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Operation not permitted", result.stderr)
        self.assertIn("permitted desktop", result.stderr)
        self.assertFalse(self.report.exists())
        self.assertNotIn("Wayland load passed", result.stdout)

    def test_missing_environment_stops_before_gui(self):
        self.environment.pop("WAYLAND_DISPLAY")
        result = self.run_smoke(1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("both variables must be set", result.stderr)
        self.assertFalse(self.report.exists())

    def test_success_preserves_wayland_environment_and_isolation(self):
        self.allow_probe()
        result = self.run_smoke(1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Hidden Todo.qml Wayland load passed", result.stdout)
        environment = json.loads(self.report.read_text())
        self.assertEqual(environment, json.loads((self.base / "probe.json").read_text()))
        self.assertEqual(environment["QT_QPA_PLATFORM"], "wayland")
        for name in ("WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"):
            self.assertEqual(environment[name], self.environment[name])
        for name in ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
            directory = Path(environment[name])
            self.assertTrue(directory.is_relative_to(self.temporary_runs))
            self.assertFalse(directory.exists())

    def test_application_failure_after_probe_is_reported(self):
        self.allow_probe()
        (self.base / "fail-gui").touch()
        result = self.run_smoke(1)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.report.exists())
        self.assertIn("Application load failed: regression sentinel", result.stderr)
        self.assertNotIn("Wayland load passed", result.stdout)


if __name__ == "__main__":
    unittest.main()

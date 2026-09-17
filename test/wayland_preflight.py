import os
import socket
import sys
import tempfile


def main():
    display = os.environ.get("WAYLAND_DISPLAY")
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    operation = "read WAYLAND_DISPLAY and XDG_RUNTIME_DIR"
    try:
        if not display or not runtime:
            raise ValueError("both variables must be set for the desktop session")

        address = os.path.join(runtime, display)
        operation = f"connect to Wayland display {address!r}"
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(2)
            connection.connect(address)

        operation = f"create a temporary directory in XDG_RUNTIME_DIR {runtime!r}"
        with tempfile.TemporaryDirectory(prefix="super-t-wayland-preflight-", dir=runtime):
            pass
    except (OSError, ValueError) as error:
        print(f"WAYLAND_SMOKE=1 preflight failed: cannot {operation}: {error}", file=sys.stderr)
        print(
            "Run WAYLAND_SMOKE=1 make test-qml from a permitted desktop terminal "
            "with the session's WAYLAND_DISPLAY and XDG_RUNTIME_DIR, or grant "
            "the test explicitly permitted desktop access. "
            "Use make test-qml without WAYLAND_SMOKE=1 for headless coverage.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
node "$root/test/parser-parity.js" | python3 -B "$root/test/parser_parity.py"

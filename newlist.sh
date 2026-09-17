#!/usr/bin/env bash
set -uo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
jq -nc --arg dir "${1:-}" --arg name "${2:-}" '{op:"create",dir:$dir,name:$name}' |
  python3 -B "$script_dir/service.py"

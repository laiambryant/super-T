#!/bin/bash
# Scan a directory tree of markdown files and emit one JSON summary of every
# list found. Counts are computed here so the bar widget never has to read or
# parse file bodies just to show a number.
#
#   scan.sh <dir>  ->  {"dir":"…","ok":true,"lists":[{"path","name","total","done"}]}
#
# The task-line and code-fence rules below must stay in lockstep with
# TASK_RE and parse() in TodoDoc.js, or the sidebar counts will disagree with
# the tasks the overlay actually shows.

set -uo pipefail

dir=${1:-}
dir=${dir/#\~/$HOME}
dir=${dir%/}

if [[ -z $dir || ! -d $dir ]]; then
  jq -nc --arg dir "$dir" '{dir: $dir, ok: false, lists: []}'
  exit 0
fi

count_tasks() {
  awk '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^[ \t]*[-*+][ \t]+\[[xX]\]/ { total++; done++; next }
    /^[ \t]*[-*+][ \t]+\[ \]/    { total++; next }
    END { printf "%d %d\n", total + 0, done + 0 }
  ' "$1" 2>/dev/null
}

while IFS= read -r -d '' file; do
  rel=${file#"$dir"/}
  name=${rel%.[mM][dD]}
  read -r total done_count < <(count_tasks "$file")
  jq -nc \
    --arg path "$file" \
    --arg name "$name" \
    --argjson total "${total:-0}" \
    --argjson done "${done_count:-0}" \
    '{path: $path, name: $name, total: $total, done: $done}'
done < <(find -L "$dir" -type f -iname '*.md' -print0 2>/dev/null | sort -z) |
  jq -sc --arg dir "$dir" '{dir: $dir, ok: true, lists: .}'

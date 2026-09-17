#!/usr/bin/env bash
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
test_state=$(mktemp -d)
export XDG_STATE_HOME=$test_state
trap 'rm -rf "$tmp" "$test_state"' EXIT

pass=0
fail=0
check() {
  local name=$1 got=$2 want=$3
  if [[ $got == "$want" ]]; then
    pass=$((pass + 1))
    echo "  ok   $name"
  else
    fail=$((fail + 1))
    echo "  FAIL $name"
    echo "    got  $got"
    echo "    want $want"
  fi
}

refused() {
  local name=$1 arg=$2 want=$3 out
  out=$("$root/newlist.sh" "$tmp/lists" "$arg")
  check "$name (refused)" "$(jq -r '.ok' <<<"$out")" "false"
  check "$name (reason)" "$(jq -r '.error' <<<"$out")" "$want"
}

dir=$tmp/lists

out=$("$root/newlist.sh" "$dir" "work")
check "reports ok" "$(jq -r '.ok' <<<"$out")" "true"
check "path is inside the todo directory" "$(jq -r '.path' <<<"$out")" "$dir/work.md"
check "name is the path without the extension" "$(jq -r '.name' <<<"$out")" "work"
check "creates the directory if it is missing" "$(test -f "$dir/work.md" && echo yes)" "yes"
check "seeded with a heading" "$(head -1 "$dir/work.md")" "# work"
check "seeded with a blank line after it" "$(wc -l <"$dir/work.md")" "2"
check "seeded file has no tasks yet" \
  "$("$root/scan.sh" "$dir" | jq -r '.lists[] | select(.name == "work") | "\(.total)/\(.done)"')" \
  "0/0"

out=$("$root/newlist.sh" "$dir" "projects/omarchy")
check "nested name creates the parent directory" "$(jq -r '.path' <<<"$out")" "$dir/projects/omarchy.md"
check "nested heading is the last segment" "$(head -1 "$dir/projects/omarchy.md")" "# omarchy"
check "scan.sh finds it under its relative name" \
  "$("$root/scan.sh" "$dir" | jq -r '[.lists[].name] | join(",")')" \
  "projects/omarchy,work"

out=$("$root/newlist.sh" "$dir" "  spaced.MD  ")
check "trims whitespace and an existing .md" "$(jq -r '.name' <<<"$out")" "spaced"
check "extension is not doubled" "$(test -f "$dir/spaced.md" && echo yes)" "yes"

refused "duplicate" "work" "work already exists"
refused "empty name" "   " "Name is empty"
refused "absolute path" "/etc/passwd" "Name must be relative to the todo directory"
printf -v literal_tilde '\176'
refused "home-relative path" "$literal_tilde/notes" "Name must be relative to the todo directory"
refused "trailing slash" "a/" "Name must be relative to the todo directory"
refused "doubled slash" "a//b" "Name must be relative to the todo directory"
refused "parent segment" "../escape" "Name must not contain . or .. segments"
refused "parent segment in the middle" "a/../../escape" "Name must not contain . or .. segments"
refused "current segment" "a/./b" "Name must not contain . or .. segments"

check "nothing escaped the todo directory" "$(find "$tmp" -mindepth 1 -maxdepth 1 | wc -l)" "1"

missing=$("$root/newlist.sh" "" "work")
check "no directory reports ok:false" "$(jq -r '.ok' <<<"$missing")" "false"
check "no directory says so" "$(jq -r '.error' <<<"$missing")" "No todo directory configured"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]

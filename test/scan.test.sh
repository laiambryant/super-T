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

mkdir -p "$tmp/lists/projects"

cat >"$tmp/lists/work.md" <<'MD'
# Work

- [ ] Fix the deploy script
- [x] Renew domain
  - [ ] Nested subtask
* [X] Upper-case done marker

```sh
- [ ] fenced, not a task
```

- not a task, no checkbox
MD

printf '* [ ] Buy milk\n* [X] Buy bread\n' >"$tmp/lists/groceries.md"
printf 'Just prose.\n' >"$tmp/lists/projects/notes.md"
printf '%s\n' '- [ ] ignored, not markdown' >"$tmp/lists/notes.txt"

out=$("$root/scan.sh" "$tmp/lists")

check "reports ok" "$(jq -r '.ok' <<<"$out")" "true"
check "only .md files" "$(jq -r '.lists | length' <<<"$out")" "3"
check "names are relative and extension-free" \
  "$(jq -r '[.lists[].name] | join(",")' <<<"$out")" \
  "groceries,projects/notes,work"
check "fenced task is not counted" \
  "$(jq -r '.lists[] | select(.name == "work") | "\(.total)/\(.done)"' <<<"$out")" "4/2"
check "alternate bullets and upper-case X" \
  "$(jq -r '.lists[] | select(.name == "groceries") | "\(.total)/\(.done)"' <<<"$out")" "2/1"
check "file with no tasks still listed" \
  "$(jq -r '.lists[] | select(.name == "projects/notes") | "\(.total)/\(.done)"' <<<"$out")" "0/0"

missing=$("$root/scan.sh" "$tmp/does-not-exist")
check "missing directory reports ok:false" "$(jq -r '.ok' <<<"$missing")" "false"
check "missing directory has no lists" "$(jq -r '.lists | length' <<<"$missing")" "0"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]

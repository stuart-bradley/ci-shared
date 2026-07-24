#!/usr/bin/env bash
#
# Self-check for play-release-notes.sh. Each case builds a throwaway app dir and
# asserts on the file the script does (or doesn't) write. Run it directly:
#   .github/actions/play-release-notes/play-release-notes.test.sh
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/play-release-notes.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# Build an app dir: $1 = pubspec version, $2 = CHANGELOG.md body ("-" = no file).
app() {
  local dir="$tmp/case$RANDOM$RANDOM"
  mkdir -p "$dir"
  printf 'name: demo\nversion: %s\n' "$1" >"$dir/pubspec.yaml"
  [[ $2 == "-" ]] || printf '%s\n' "$2" >"$dir/CHANGELOG.md"
  echo "$dir"
}

check() { # name, expected, actual
  if [[ $2 == "$3" ]]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1"
    echo "       expected: $(printf '%q' "$2")"
    echo "       actual:   $(printf '%q' "$3")"
    fails=$((fails + 1))
  fi
}

notes="android/fastlane/metadata/android/en-GB/changelogs"

CHANGELOG='# Changelog

## Unreleased

- Unreleased line.

## 1.2.0+7

- Version line one.
- Version line two.

## 1.1.0+6

- Older line.
'

# The version heading wins over Unreleased, and stops at the next `## `.
dir=$(app "1.2.0+7" "$CHANGELOG")
(cd "$dir" && "$script" >/dev/null)
check "version section" "- Version line one.
- Version line two." "$(cat "$dir/$notes/7.txt")"

# No matching version section: fall back to Unreleased.
dir=$(app "1.3.0+8" "$CHANGELOG")
(cd "$dir" && "$script" >/dev/null)
check "unreleased fallback" "- Unreleased line." "$(cat "$dir/$notes/8.txt")"

# A hand-written file is never overwritten.
dir=$(app "1.2.0+7" "$CHANGELOG")
mkdir -p "$dir/$notes"
echo "Hand-written." >"$dir/$notes/7.txt"
(cd "$dir" && "$script" >/dev/null)
check "hand-written wins" "Hand-written." "$(cat "$dir/$notes/7.txt")"

# Over Play's 500-char limit: fail, and write nothing.
long=$(printf '%s\n' "## Unreleased" "$(printf -- '- padding padding padding padding%.0s' {1..20})")
dir=$(app "1.0.0+1" "$long")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "oversize exits 1" "1" "$rc"
check "oversize writes nothing" "absent" "$([[ -f "$dir/$notes/1.txt" ]] && echo present || echo absent)"

# No section at all: succeed quietly so fastlane falls back to default.txt.
dir=$(app "1.0.0+1" "# Changelog")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "no section exits 0" "0" "$rc"
check "no section writes nothing" "absent" "$([[ -f "$dir/$notes/1.txt" ]] && echo present || echo absent)"

# No CHANGELOG.md, and no +buildNumber: skip, don't fail the release.
dir=$(app "1.0.0+1" "-")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "missing changelog exits 0" "0" "$rc"

dir=$(app "1.0.0" "$CHANGELOG")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "no build number exits 0" "0" "$rc"

echo
if ((fails)); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"

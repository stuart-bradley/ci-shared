#!/usr/bin/env bash
#
# Self-check for play-release-notes.sh. Each case builds a throwaway app dir and
# asserts on the file the script does (or doesn't) write. Run it directly:
#   .github/actions/play-release-notes/play-release-notes.test.sh
#
# Every assertion here has been shown to fail against a mutant of the script.
# When adding behaviour, add the case that goes red without it — a skip path
# asserted only by exit code passes for the wrong reason, since the script exits
# 0 on almost everything.
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/play-release-notes.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# Build an app dir: $1 = value of the pubspec `version:` line,
# $2 = CHANGELOG.md body ("-" = no file).
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

# Nothing written anywhere. Asserts on the whole tree rather than one filename,
# so output written under a WRONG name is caught too.
wrote_nothing() { [[ -d "$1/android" ]] && echo present || echo absent; }

notes="android/fastlane/metadata/android/en-GB/changelogs"

# The 1.2.0+7 heading carries trailing whitespace on purpose: the script
# normalises it, and without that the "version section" case goes red.
CHANGELOG='# Changelog

## Unreleased

- Unreleased line.

## 1.2.0+7   

### Added

- Version line one.
- Version line two.

## 1.1.0+6

- Older line.
'

# The version heading wins over Unreleased, stops at the next `## `, and drops
# the `###` subheading instead of printing literal markdown into the listing.
dir=$(app "1.2.0+7" "$CHANGELOG")
(cd "$dir" && "$script" >/dev/null)
check "version section" "- Version line one.
- Version line two." "$(cat "$dir/$notes/7.txt")"

# No matching version section: fall back to Unreleased.
dir=$(app "1.3.0+8" "$CHANGELOG")
(cd "$dir" && "$script" >/dev/null)
check "unreleased fallback" "- Unreleased line." "$(cat "$dir/$notes/8.txt")"

# Both arguments are positional — locale first, changelog path second. Nothing
# else exercises them, so swapping the two in the script is otherwise silent.
dir=$(app "1.2.0+7" "-")
mkdir -p "$dir/docs"
printf '%s\n' "$CHANGELOG" >"$dir/docs/CHANGES.md"
(cd "$dir" && "$script" de-DE docs/CHANGES.md >/dev/null)
check "explicit locale + changelog args" "- Version line one.
- Version line two." "$(cat "$dir/android/fastlane/metadata/android/de-DE/changelogs/7.txt" 2>/dev/null)"

# `version: "1.2.0+7"` is legal YAML. Unstripped, the quote lands in the
# FILENAME (7".txt) and the heading stops matching — a green run that silently
# ships default.txt.
dir=$(app '"1.2.0+7"' "$CHANGELOG")
(cd "$dir" && "$script" >/dev/null)
check "quoted pubspec version" "- Version line one.
- Version line two." "$(cat "$dir/$notes/7.txt" 2>/dev/null)"

# A hand-written file is never overwritten...
dir=$(app "1.2.0+7" "$CHANGELOG")
mkdir -p "$dir/$notes"
echo "Hand-written." >"$dir/$notes/7.txt"
(cd "$dir" && "$script" >/dev/null)
check "hand-written wins" "Hand-written." "$(cat "$dir/$notes/7.txt")"

# ...but is still length-checked. It is the case most likely to be over-long,
# since no generator constrained it.
dir=$(app "1.2.0+7" "$CHANGELOG")
mkdir -p "$dir/$notes"
printf -- '- padding padding padding padding%.0s' {1..20} >"$dir/$notes/7.txt"
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "oversize hand-written exits 1" "1" "$rc"

# Over Play's 500-char limit: fail, and write nothing.
long=$(printf '%s\n' "## Unreleased" "$(printf -- '- padding padding padding padding%.0s' {1..20})")
dir=$(app "1.0.0+1" "$long")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "oversize exits 1" "1" "$rc"
check "oversize writes nothing" "absent" "$(wrote_nothing "$dir")"

# No section at all: succeed quietly so fastlane falls back to default.txt.
dir=$(app "1.0.0+1" "# Changelog")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "no section exits 0" "0" "$rc"
check "no section writes nothing" "absent" "$(wrote_nothing "$dir")"

# Skip paths: exit 0 AND write nothing. Asserting the exit code alone passes
# even when the script writes a garbage filename on its way out.
dir=$(app "1.0.0+1" "-")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "missing changelog exits 0" "0" "$rc"
check "missing changelog writes nothing" "absent" "$(wrote_nothing "$dir")"

dir=$(app "1.0.0" "$CHANGELOG")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "no build number exits 0" "0" "$rc"
check "no build number writes nothing" "absent" "$(wrote_nothing "$dir")"

dir=$(app "1.0.0+beta" "$CHANGELOG")
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "non-numeric build number exits 0" "0" "$rc"
check "non-numeric build number writes nothing" "absent" "$(wrote_nothing "$dir")"

# Not a Flutter app at all.
dir=$(app "1.0.0+1" "$CHANGELOG")
rm "$dir/pubspec.yaml"
rc=0
(cd "$dir" && "$script" >/dev/null 2>&1) || rc=$?
check "no pubspec exits 0" "0" "$rc"
check "no pubspec writes nothing" "absent" "$(wrote_nothing "$dir")"

echo
if ((fails)); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"

#!/usr/bin/env bash
#
# Turn the app's CHANGELOG.md into the Play Store "What's new" text.
#
# Why this exists
# ---------------
# fastlane `supply` reads release notes from
# `android/fastlane/metadata/android/<locale>/changelogs/<versionCode>.txt`,
# falling back to `default.txt`. Nothing generated those files, so uploads either
# shipped stale notes or the generic blurb. The versionCode is just the `+N` in
# `pubspec.yaml`, so the note can be written in the PR that ships the change and
# assembled here at release time.
#
# Contract: a `## <version>` section in CHANGELOG.md whose heading matches
# `pubspec.yaml`'s `version:` exactly (e.g. `## 0.11.0+17`), else `## Unreleased`.
# Nothing is committed back — the file only has to exist in the runner workspace
# for the fastlane step that follows.
set -euo pipefail

locale=${1:-en-GB}
changelog=${2:-CHANGELOG.md}

# Play's per-locale limit for release notes. Truncating instead of failing would
# ship a half-sentence to users, so this is a hard stop.
readonly MAX_CHARS=500

if [[ ! -f pubspec.yaml ]]; then
  echo "No pubspec.yaml — not a Flutter app. Skipping."
  exit 0
fi
if [[ ! -f $changelog ]]; then
  echo "No $changelog — nothing to generate. Fastlane will fall back to default.txt."
  exit 0
fi

full=$(awk '/^version:/ { print $2; exit }' pubspec.yaml)
if [[ $full != *+* ]]; then
  echo "pubspec version '$full' has no +buildNumber — can't name the changelog file. Skipping."
  exit 0
fi
code=${full##*+}

out="android/fastlane/metadata/android/$locale/changelogs/$code.txt"
if [[ -f $out ]]; then
  echo "$out is hand-written — leaving it alone."
  exit 0
fi

# Lines between `## <heading>` and the next `## `. Blank lines are dropped: the
# section is a bullet list, and Play renders the blanks as dead space.
section() {
  awk -v want="## $1" '
    { line = $0; sub(/[[:space:]]+$/, "", line) }
    line == want { inside = 1; next }
    inside && /^## / { exit }
    inside && NF { print line }
  ' "$changelog"
}

body=$(section "$full")
[[ -n $body ]] || body=$(section "Unreleased")

if [[ -z $body ]]; then
  echo "::warning::No '## $full' or '## Unreleased' section in $changelog — Play will show default.txt."
  exit 0
fi

if (( ${#body} > MAX_CHARS )); then
  echo "::error::Release notes for $full are ${#body} chars; Play allows $MAX_CHARS."
  echo "Trim the '## $full' (or '## Unreleased') section in $changelog:"
  echo "$body"
  exit 1
fi

mkdir -p "$(dirname "$out")"
printf '%s\n' "$body" >"$out"

echo "Wrote $out (${#body}/$MAX_CHARS chars):"
echo "$body"

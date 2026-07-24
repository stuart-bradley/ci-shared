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
#
# Every skip path exits 0 on purpose: a missing note is not worth failing a
# release over, because fastlane falls back to default.txt. The ONE hard failure
# is notes Play would reject — see MAX_CHARS.
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

# `version: "1.2.0+7"` is legal YAML, and a CRLF checkout leaves a trailing \r.
# Either one silently poisons the filename (`7".txt`), which fastlane then never
# reads — a green run that ships default.txt, the exact failure this replaces.
full=$(awk '/^version:/ { print $2; exit }' pubspec.yaml)
full=${full%$'\r'}
full=${full#[\"\']}
full=${full%[\"\']}
code=${full##*+}

if [[ $full != *+* || ! $code =~ ^[0-9]+$ ]]; then
  echo "::warning::pubspec version '$full' has no numeric +buildNumber — can't name the changelog file. Skipping."
  exit 0
fi

out="android/fastlane/metadata/android/$locale/changelogs/$code.txt"

# Lines under `## <heading>`, up to the next heading. `###` subheadings (the
# Keep-a-Changelog "### Added" style) are dropped rather than printed: Play
# renders them as literal `###` in the store listing. Blank lines go too — the
# section is a bullet list and Play shows the gaps as dead space.
section() {
  awk -v want="## $1" '
    { line = $0; sub(/[[:space:]]+$/, "", line) }
    line == want { inside = 1; next }
    inside && (/^# / || /^## /) { exit }
    inside && /^#/ { next }
    inside && NF { print line }
  ' "$changelog"
}

# A hand-written file wins, but it is still length-checked below: it is the case
# MOST likely to be over-long, since no generator constrained it.
if [[ -f $out ]]; then
  body=$(<"$out")
  handwritten=yes
else
  handwritten=no
  body=$(section "$full")
  [[ -n $body ]] || body=$(section "Unreleased")
  if [[ -z $body ]]; then
    echo "::warning::No '## $full' or '## Unreleased' section in $changelog — Play will show default.txt."
    exit 0
  fi
fi

if (( ${#body} > MAX_CHARS )); then
  echo "::error::Release notes for $full are ${#body} chars; Play allows $MAX_CHARS."
  if [[ $handwritten == yes ]]; then
    echo "Trim $out:"
  else
    echo "Trim the '## $full' (or '## Unreleased') section in $changelog:"
  fi
  echo "$body"
  exit 1
fi

if [[ $handwritten == yes ]]; then
  echo "$out is hand-written (${#body}/$MAX_CHARS chars) — leaving it alone:"
  echo "$body"
  exit 0
fi

mkdir -p "$(dirname "$out")"
printf '%s\n' "$body" >"$out"

echo "Wrote $out (${#body}/$MAX_CHARS chars):"
echo "$body"

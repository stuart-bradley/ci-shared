# ci-shared

Shared GitHub Actions CI for the Flutter apps (cog-scroll, tasks-on-time,
well-quill, watch-nook). Composite actions + four reusable workflows so an
optimisation made here reaches every app.

## Consuming

Apps pin the **moving `@v1` tag**. A shared change is committed to `main`, then
`v1` is force-moved to it — one tag move, not three SHA bumps. Because `uses:`
can't take an expression, test changes via a **caller PR after moving `v1`**,
not by running a `ci-shared` branch (a branch run still resolves `@v1`).

```yaml
# .github/workflows/ci.yml
jobs:
  check:
    uses: stuart-bradley/ci-shared/.github/workflows/flutter-ci.yml@v1
    with:
      smoke-build: false        # true to add a debug-APK compile check

# .github/workflows/e2e.yml
jobs:
  e2e:
    uses: stuart-bradley/ci-shared/.github/workflows/flutter-e2e.yml@v1
    with:
      api-level: 31             # 33 for runtime-notification tests
      disk-size: "2G"           # "4G" for heavier (Patrol) builds
      install-patrol: false     # true for Patrol apps
      # Patrol apps only. Must match the caller's `patrol` dep -- patrol_cli
      # refuses a package version it doesn't support.
      patrol-cli-version: "3.11.0"
      # Patrol apps build INSIDE the emulator step (install-patrol skips the
      # warm build), so they must pass 35. Keep it under `timeout-minutes`.
      emulator-timeout-minutes: 12
      timeout-minutes: 20

# .github/workflows/release.yml — Play Store deploy (AAB)
jobs:
  deploy:
    uses: stuart-bradley/ci-shared/.github/workflows/flutter-release.yml@v1
    with:
      track: ${{ inputs.track || 'internal' }}
      release-status: ${{ inputs.release_status || 'completed' }}
    secrets: inherit            # passes the app's 5 signing/Play secrets

# ...or GitHub-Releases APK instead of Play (tag vX.Y.Z -> signed APK on the Release)
jobs:
  release-apk:
    permissions:
      contents: write           # create the Release + upload the APK
    uses: stuart-bradley/ci-shared/.github/workflows/flutter-release-apk.yml@v1
    with:
      flutter-version: "3.44.0"
    secrets: inherit            # 4 signing + 2 TMDB secrets
```

Each consuming app must expose the `just` recipes its chosen workflows call:
`lint-scripts`, `check`, `codegen`, `build-debug`, `e2e`, plus `release-ci`
(Play deploy) or `release-apk-ci` (GitHub-Releases APK).

## Contract

| workflow | inputs | secrets |
|----------|--------|---------|
| `flutter-ci` | `smoke-build` (bool, false) | — |
| `flutter-e2e` | `api-level` (31), `disk-size` ("2G"), `install-patrol` (false), `patrol-cli-version` ("3.11.0"), `emulator-timeout-minutes` (12), `timeout-minutes` (30), `flutter-version` ("") | — |
| `flutter-release` | `track` ("internal"), `release-status` ("completed"), `flutter-version` (""), `release-notes-locale` ("en-GB") | `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`, `PLAY_STORE_JSON_KEY` |
| `flutter-release-apk` | `flutter-version` ("") | `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`, `TMDB_API_KEY`, `TMDB_READ_TOKEN` (caller grants `contents: write`) |

Private cross-repo access is enabled on this repo
(`actions/permissions/access` = `user`) so same-owner apps can reference it.

## Pinning

Actions are pinned to full-length SHAs, apps commit `pubspec.lock`, Gradle has
its wrapper, and two more pieces are pinned here:

| What | Pinned to | Where |
|---|---|---|
| Flutter SDK | `3.44.6` | `setup-flutter/action.yml` — the fallback in the `subosito` step |
| Runner image | `ubuntu-24.04` | `runs-on:` in every workflow |

**The Flutter pin is one constant for every app and every workflow.** It sits at
the point of use, not in each workflow's input default, because the workflows
pass their own (empty) `flutter-version` straight through and an explicit `""`
would beat an input default. Callers override it per-repo with
`flutter-version:`; pass `""` and you are back on floating stable.

Both pins are scar tissue. An unpinned SDK auto-updates on the runner, so a
build breaks with no commit to blame: first the `compileFlutterBuildDebug not
found` Gradle regression, then 3.44.8's built-in Kotlin, which stops
`home_widget 0.9.1` compiling and took out tasks-on-time's e2e *and* its next
release. `ubuntu-latest` rolls to a new image on its own schedule, which is how
the free-disk-space action came to exist.

**Moving a pin is deliberate**: bump it here, watch `ci` + `e2e` go green on
**every** app, then move `v1`. One edit reaches all of them at once — which is
the point, and also the risk.

### What these pins do NOT cover

`runs-on: ubuntu-24.04` pins the distro, **not the image build** — GitHub rolls
`24.04` forward through image versions and there is no way to pin one.

More importantly, neither pin reaches **Gradle's Maven resolution**, and a
third-party Flutter plugin can float its own Android dependencies right past
`pubspec.lock`. `home_widget 0.9.1` asks for `androidx.glance:glance-appwidget:1.+`
while compiling at `jvmTarget 1.8`; on 2026-07-01 `1.3.0-alpha02` shipped built
for Java 11 and every Android build of tasks-on-time started failing with
`Cannot inline bytecode built with JVM target 11 into bytecode built with JVM
target 1.8` (tasks-on-time#207). Note what it took to see it: `main` stayed green
for two weeks, because the Gradle cache key is `hashFiles('**/*.gradle*')` and an
unchanged gradle file restores the **previously resolved** version. Only branches
that touched a gradle file re-resolved and went red.

So: a green run does not prove the build is reproducible — it may be proving the
cache is warm. Constrain a plugin's `+` ranges with a `resolutionStrategy.force`
in the app's `android/build.gradle.kts` when you find one.

## Play release notes (`flutter-release`)

The "What's new" text comes from the app's **`CHANGELOG.md`**, so it is written in
the PR that ships the change and reviewed in the diff. At release time
`play-release-notes` takes the section whose heading matches `pubspec.yaml`'s
`version:` exactly — else `## Unreleased` — and writes it to
`android/fastlane/metadata/android/<locale>/changelogs/<versionCode>.txt`, which
is where fastlane `supply` already looks (`versionCode` is just the `+N`).

```markdown
## Unreleased

- Fixed: reminders now actually appear.

## 0.11.0+17

- Doses remaining now shows on the Medications list.
```

Nothing is committed back — the file only has to exist in the runner workspace.
Rules: a hand-written `<versionCode>.txt` always wins, but is still length-checked;
**over 500 characters fails the release** (Play's limit — truncating would ship a
half-sentence); no section at all is not an error, fastlane falls back to
`default.txt`. Blank lines and `###` subheadings are dropped — Play renders them
as dead space and literal `###`. The locale must be an **active language in Play
Console** or `supply` rejects the changelog; override the default with
`release-notes-locale`.

Everything else skips with exit 0 (no `pubspec.yaml`, no changelog, a version
with no numeric `+N`): a missing note is not worth failing a release over when
`default.txt` covers it.

At version-bump time, rename `## Unreleased` to the new `## x.y.z+N` and open a
fresh `## Unreleased` — that keeps an accurate per-version history in the repo.


## The R8 resource check (`flutter-ci`)

`flutter-ci` runs a static check that every Android resource **named only from a
Dart string** is pinned in `android/app/src/main/res/raw/keep.xml`.

R8 resource shrinking runs on Flutter **release** builds and never on debug. It
keeps a resource only if it can *see* a reference — manifest, XML, Kotlin/Java. A
notification small icon that Dart passes to `flutter_local_notifications` as a
string is resolved at runtime via `Resources.getIdentifier(...)`, which the
shrinker cannot see, so it strips it and the plugin throws
`PlatformException(invalid_icon)` on every call.

**The failure exists only in the shipped artifact.** `just check`, `flutter run`,
the emulator and every widget test are green, because none of them builds a
shrunk APK. This has bitten two apps — well-quill, then cog-scroll, where it
survived three "verified on an emulator" fix attempts and killed the daily
reminder in production.

So: add a Dart-referenced drawable ⇒ add it to `keep.xml` in the same change.
The check is static (no build, seconds) and tells you exactly what to add. A
resource the manifest or an XML already anchors (e.g. `@mipmap/ic_launcher`) needs
no entry — the shrinker can see those on its own.

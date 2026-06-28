# ci-shared

Shared GitHub Actions CI for the Flutter apps (cog-scroll, tasks-on-time,
well-quill). One composite action + three reusable workflows so an optimisation
made here reaches every app.

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
      timeout-minutes: 20

# .github/workflows/release.yml
jobs:
  deploy:
    uses: stuart-bradley/ci-shared/.github/workflows/flutter-release.yml@v1
    with:
      track: ${{ inputs.track || 'internal' }}
      release-status: ${{ inputs.release_status || 'completed' }}
    secrets: inherit            # passes the app's 5 signing/Play secrets
```

Each consuming app must expose these `just` recipes: `lint-scripts`, `check`,
`codegen`, `build-debug`, `e2e`, `release-ci`.

## Contract

| workflow | inputs | secrets |
|----------|--------|---------|
| `flutter-ci` | `smoke-build` (bool, false) | — |
| `flutter-e2e` | `api-level` (31), `disk-size` ("2G"), `install-patrol` (false), `timeout-minutes` (20) | — |
| `flutter-release` | `track` ("internal"), `release-status` ("completed") | `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`, `PLAY_STORE_JSON_KEY` |

Private cross-repo access is enabled on this repo
(`actions/permissions/access` = `user`) so same-owner apps can reference it.

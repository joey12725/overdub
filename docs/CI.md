# Continuous integration

> **Not active yet.** The workflow file is parked at `tools/ci/ci.workflow.yml` because the token used to
> push this branch had no `workflow` scope. To turn CI on: `git mv tools/ci/ci.workflow.yml .github/workflows/ci.yml`
> and push with a token that has that scope (`gh auth refresh -s workflow`).

Workflow: `.github/workflows/ci.yml` (GitHub Actions, repo `joey12725/overdub`). It runs on every
pull request, on pushes to `master`, and by hand (`workflow_dispatch`). A newer push to the same PR
or branch cancels the run it replaces (`concurrency: ci-<pr number | ref>`). The workflow has only
`contents: read` permission and uses no secrets.

## Jobs

Both jobs run on `ubuntu-latest`, in parallel.

### `prototype` (timeout 20 min)

1. `bash tools/ci/check_large_files.sh` checks the size of every tracked file. It fails on any file
   of 95 MB or more (GitHub rejects files over 100 MB) and adds a warning annotation for files of
   20 MB or more. `FAIL_MB` and `WARN_MB` override the thresholds.
2. Node 22 via `actions/setup-node`, with the npm cache keyed on `prototype/package-lock.json`.
3. `npm ci` in `prototype/`. `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` is set because playwright is used
   only by `scripts/smoke.mjs`; vitest runs in `environment: 'node'`.
4. `npx tsc --noEmit`
5. `npx vitest run`

### `godot` (timeout 30 min)

1. `actions/cache` restores `~/.cache/godot-ci/4.4.1-stable`. The cache key contains the version
   and the pinned SHA-512.
2. `bash tools/ci/fetch_godot.sh <dir>` downloads
   `https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip`
   (the official editor build, which supports `--headless`) and the release's `SHA512-SUMS.txt`.
   The zip's SHA-512 must match both the checksum file and the pinned hash (`GODOT_SHA512` in the
   workflow, which is also the script's default for 4.4.1). On a cache hit the zip is hashed again
   and nothing is downloaded. The script prints the binary path, and the workflow exports it as
   `GODOT`.
3. `bash tools/ci/godot_tests.sh` follows the same steps as `bash tools/gd test`:
   - **import pass 1** (`--headless --path . --import`) registers new `class_name`s. On a cold
     cache this pass is expected to log errors, so they are only saved to the log. A timeout still
     fails the job.
   - **import pass 2** fails on a non-zero exit code or on any `SCRIPT ERROR` or `Parse Error`
     line. Those lines, with the `at:` line that follows each, go to the log, an `::error`
     annotation and the job summary. `ERROR: Failed …` lines (for example a resource that failed
     to load) produce a warning only.
   - **tests**: `--headless --path . -s res://tests/run_tests.gd -- [filter]`. This step fails on a
     non-zero exit code **or** when the `[tests] PASSED` line is missing (a crash that exits 0
     still fails). The runner's summary line and every `FAIL …` line go to the job summary.
   - Each Godot call runs under `timeout` (`GODOT_TIMEOUT`, 900 s).
4. If the job fails, the three logs (`import_pass1.log`, `import_pass2.log`, `tests.log`) are
   uploaded as the `godot-logs` artifact and kept for 7 days.

The `.godot/` import cache is **not** cached between runs. Every run imports from cold, so
`.import` and `.uid` drift shows up in CI rather than being hidden. Caching `.godot/imported`
(keyed on a hash of `assets/**` and `*.import`) is the obvious speed-up if imports get slow.

## Running it locally

Prototype (from the repo root, in Git Bash):

```bash
cd prototype && npm ci && npx tsc --noEmit && npx vitest run
bash tools/ci/check_large_files.sh
```

Godot, on the shared Windows checkout:

```bash
GODOT=/c/Users/joeya/.t3/tools/godot/godot_console.exe bash tools/ci/godot_tests.sh [filter]
```

Outside CI (`CI` is not `true`), the script takes the same `.godot-lock` as `tools/gd`, so it
queues behind other Godot users. Day to day, `bash tools/gd test` is still the command to use. The
CI script adds the fail-on-parse-error rule, the `[tests] PASSED` check and kept logs (default
`${TMPDIR:-/tmp}/overdub-godot-ci`; set `CI_LOG_DIR` to change it).

Other options:

| Env | Meaning |
|---|---|
| `GODOT_CI_IMPORT_ONLY=1` | stop after import pass 2 |
| `GODOT_CI_LOCK=0/1` | force the lock off or on (default: on locally, off when `CI=true`) |
| `GODOT_TIMEOUT=<s>` | timeout for each Godot call, 0 = none |

Exit codes: 0 pass, 1 failure, 2 usage or setup error (no `GODOT`, missing binary, not the project
root).

On Linux or macOS, `bash tools/ci/fetch_godot.sh` downloads the same verified Linux binary into
`~/.cache/godot-ci/4.4.1-stable` and prints its path. It only works on x86_64 Linux.

## What CI does not cover

- **Rendering.** The runner has no GPU, and `--headless` uses the dummy renderer. Shaders are
  parsed but not compiled for a real backend, and nothing is drawn. The screenshot scripts
  (`tools/shot_*.gd`, `bash tools/gd shot …`) and any visual golden comparison stay manual.
- **Audio output.** Headless uses the dummy audio driver. Tests that check generated sample data
  (for example `tests/audio/goldens/*`) do run. Nothing about real playback, latency or device
  behaviour is tested.
- **Input devices, window and resolution behaviour, performance.** The `tools/bench_*.gd`
  benchmarks are not run, because timings on shared runners are noise.
- **Exports.** No export templates are installed and no build is produced.
- **Blender / art pipeline.** `art/**` scripts, `.blend` files and GLB regeneration are not run.
  `art/` is `.gdignore`d, so Godot does not import it.
- **Prototype browser smoke** (`prototype/scripts/smoke.mjs`, playwright). Not run, and no
  browsers are installed.
- **Windows-specific behaviour.** CI runs the Linux build. Path-case or CRLF problems that only
  appear on the Windows checkout can slip through. `.gitattributes` forces `eol=lf`, which helps.
- CI only sees what is **committed**. On the shared checkout, uncommitted edits that tracked files
  depend on will pass locally and fail in CI.

## Repository size and large binaries (recommendation, not applied)

Measured 2026-11-16 on `build/overdub-game`:

- No file in the repo or the working tree is 100 MB or larger. The largest working-tree file is
  `art/moxie_b/_dl/mpfb.zip` (45 MB, untracked).
- Commit `ea3c931` ("Checkpoint: story, traps, levels, art…") began tracking about **190 MB of
  third-party downloads and Blender work files**. Tracked files went from about 12 MB to 368 MB. The
  bulk is:
  - `art/moxie_a/src_dl/*.vrm` (6 VRoid sample avatars, 12–17 MB each)
  - `art/moxie_a/work/*.blend` (7 files, about 7–16 MB each)
  - `art/moxie_c/_dl/ual/**` (Universal Animation Library: two 23 MB FBX files, a 16 MB zip, 7 MB
    GLBs)
  - `art/moxie_d/dl/ual/UAL1_Standard.glb`
- `.git` is about 260 MB, mostly loose objects from those files and from `refs/t3/...` checkpoint
  refs. `origin/master` holds only the initial commit, so nothing large has been pushed yet.
- 52 `__pycache__/*.pyc` files are tracked under `art/`.

Recommendation, in order of preference:

1. **Keep downloads and scratch out of git.** Before the branch is first pushed, drop them from the
   commit (it is still local, so rewriting history costs nothing) and add these lines to
   `.gitignore`:

   ```gitignore
   # third-party downloads (re-fetchable; licences vary - VRoid samples, MPFB, UAL)
   art/**/_dl/
   art/**/src_dl/
   art/**/dl/
   art/**/_blender_user/
   # Blender scratch + bytecode
   art/**/work/
   *.blend1
   __pycache__/
   *.pyc
   ```

   Then run `git rm -r --cached art/**/__pycache__` once. Record where each download came from (URL
   and licence) in a small `art/SOURCES.md`, so the pipeline can fetch them again.
2. **Use Git LFS for `.blend` sources that must be versioned** (the hand-authored masters, if any):

   ```gitattributes
   *.blend filter=lfs diff=lfs merge=lfs -text
   *.vrm   filter=lfs diff=lfs merge=lfs -text
   *.fbx   filter=lfs diff=lfs merge=lfs -text
   *.zip   filter=lfs diff=lfs merge=lfs -text
   ```

   Do not put `assets/models/**/*.glb` in LFS. They are small (the largest is 1.9 MB), Godot imports
   them, and keeping them as normal blobs means CI's `actions/checkout` needs no `lfs: true`. If
   `.blend` files do move to LFS, CI can stay as it is, because `art/` is never imported.
   Private-repo LFS storage and bandwidth count against the account's quota.
3. Keep `art/previews/` ignored (already in `.gitignore`; 304 MB on disk).

`tools/ci/check_large_files.sh` runs in the `prototype` job. It fails the build on any tracked file
that gets near the 100 MB limit, and it warns, with a file annotation, about anything 20 MB or
larger.

## Maintenance

- **Bumping Godot:** change `GODOT_VERSION` and `GODOT_SHA512` in `ci.yml`. Take the hash for
  `Godot_v<ver>_linux.x86_64.zip` from that release's `SHA512-SUMS.txt`. Also update `PIN_4_4_1`
  (the default) in `tools/ci/fetch_godot.sh`, or rely on the env var. The cache key changes by
  itself.
- **Action versions:** the workflow pins `actions/checkout@v5`, `actions/setup-node@v5`,
  `actions/cache@v4` and `actions/upload-artifact@v4`. Bump them together when GitHub deprecates a
  runtime.
- **Branch protection:** to block merging, mark the `prototype (tsc + vitest)` and
  `godot (import + tests)` checks as required on `master` in the repository settings.

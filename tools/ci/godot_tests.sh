#!/usr/bin/env bash
# CI entry point for the Godot side: two-pass headless import, then the project's test runner.
# Mirrors `bash tools/gd test [filter]` (tools/gd), but takes the binary from $GODOT, keeps logs,
# and fails loudly instead of only printing.
#
#   GODOT=/path/to/godot bash tools/ci/godot_tests.sh [filter]
#
# Local (Git Bash on the shared Windows checkout):
#   GODOT=/c/Users/joeya/.t3/tools/godot/godot_console.exe bash tools/ci/godot_tests.sh
# Outside CI the script takes the same .godot-lock as tools/gd, so it queues behind (and blocks)
# other Godot users of the checkout exactly like the wrapper does.
#
# Steps / failure conditions (exit 1 on any):
#   1. import pass 1   (registers new class_names; errors here are expected on a cold cache and are
#                       only logged; a timeout still fails)
#   2. import pass 2   fails on a non-zero exit code or any "SCRIPT ERROR" / "Parse Error" line
#                      ("ERROR: Failed ..." lines are reported as warnings)
#   3. tests           godot --headless --path . -s res://tests/run_tests.gd -- [filter]
#                      fails on a non-zero exit code or when the "[tests] PASSED" line is missing
#
# Env:
#   GODOT                 Godot editor binary (required)
#   GODOT_TIMEOUT         seconds per Godot invocation (default 900; needs `timeout`, else none)
#   CI_LOG_DIR            where the three logs go (default ${RUNNER_TEMP:-${TMPDIR:-/tmp}}/overdub-godot-ci)
#   GODOT_CI_IMPORT_ONLY  1 = stop after step 2
#   GODOT_CI_LOCK         1 = take .godot-lock, 0 = don't (default: 1 unless CI=true)
# Exit codes: 0 ok, 1 failure, 2 usage / setup error.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-}"
TIMEOUT_S="${GODOT_TIMEOUT:-900}"
LOG_DIR="${CI_LOG_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/overdub-godot-ci}"
LOCK="$ROOT/.godot-lock"
STALE_SECONDS=900
IN_GHA="${GITHUB_ACTIONS:-false}"

if [ "${CI:-}" = "true" ]; then USE_LOCK="${GODOT_CI_LOCK:-0}"; else USE_LOCK="${GODOT_CI_LOCK:-1}"; fi

log() { echo "[godot-ci] $*" >&2; }
gha_error() { if [ "$IN_GHA" = "true" ]; then echo "::error::$*"; else echo "ERROR: $*" >&2; fi; }
gha_warn() { if [ "$IN_GHA" = "true" ]; then echo "::warning::$*"; else echo "WARNING: $*" >&2; fi; }
summary() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$*" >> "$GITHUB_STEP_SUMMARY"; fi; }

if [ -z "$GODOT" ]; then
  log "set GODOT to the Godot editor binary (e.g. GODOT=/c/Users/joeya/.t3/tools/godot/godot_console.exe)"
  exit 2
fi
if [ ! -f "$GODOT" ]; then
  log "GODOT=$GODOT does not exist"
  exit 2
fi
if [ ! -f "$ROOT/project.godot" ] || [ ! -f "$ROOT/tests/run_tests.gd" ]; then
  log "$ROOT does not look like the OVERDUB project (project.godot / tests/run_tests.gd missing)"
  exit 2
fi
mkdir -p "$LOG_DIR" || { log "cannot create $LOG_DIR"; exit 2; }

# Same lock protocol as tools/gd (mkdir is atomic; a lock older than STALE_SECONDS is broken).
acquire() {
  local waited=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    local age=0
    if [ -d "$LOCK" ]; then
      age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || date +%s) ))
    fi
    if [ "$age" -gt "$STALE_SECONDS" ]; then
      rmdir "$LOCK" 2>/dev/null || rm -rf "$LOCK"
      continue
    fi
    sleep 1
    waited=$((waited + 1))
    if [ $((waited % 30)) -eq 0 ]; then log "waiting for the Godot lock (${waited}s)..."; fi
  done
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
}

run_godot() {
  if command -v timeout >/dev/null 2>&1 && [ "$TIMEOUT_S" -gt 0 ] 2>/dev/null; then
    timeout --kill-after=30 "$TIMEOUT_S" "$GODOT" "$@"
  else
    "$GODOT" "$@"
  fi
}

is_timeout() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ]; }

[ "$USE_LOCK" = "1" ] && acquire

log "godot: $GODOT"
log "$("$GODOT" --version 2>/dev/null | tail -1 || echo 'version unknown')"
log "project: $ROOT"
log "logs: $LOG_DIR"

# --- 1. import pass 1 -----------------------------------------------------------------------------
IMPORT1="$LOG_DIR/import_pass1.log"
log "import pass 1 (class_name registration)..."
run_godot --headless --path "$ROOT" --import > "$IMPORT1" 2>&1
rc=$?
if is_timeout "$rc"; then
  gha_error "Godot import pass 1 timed out after ${TIMEOUT_S}s"
  tail -40 "$IMPORT1" >&2
  exit 1
fi
[ "$rc" -ne 0 ] && gha_warn "Godot import pass 1 exited $rc (tolerated; pass 2 decides)"

# --- 2. import pass 2 -----------------------------------------------------------------------------
IMPORT2="$LOG_DIR/import_pass2.log"
log "import pass 2 (script resolution)..."
run_godot --headless --path "$ROOT" --import > "$IMPORT2" 2>&1
rc=$?
fail=0
if is_timeout "$rc"; then
  gha_error "Godot import pass 2 timed out after ${TIMEOUT_S}s"
  fail=1
elif [ "$rc" -ne 0 ]; then
  gha_error "Godot import pass 2 exited $rc"
  fail=1
fi
script_errors="$(grep -nE "SCRIPT ERROR|Parse Error" "$IMPORT2" || true)"
if [ -n "$script_errors" ]; then
  n="$(printf '%s\n' "$script_errors" | wc -l | tr -d ' ')"
  gha_error "Godot import pass 2 logged $n SCRIPT ERROR / Parse Error line(s)"
  # Each error line is usually followed by an "at: (res://file.gd:N)" line; show both.
  grep -nE -A1 "SCRIPT ERROR|Parse Error" "$IMPORT2" | head -80 >&2
  summary "### Godot import: $n script/parse error line(s)"
  summary '```'
  summary "$(grep -E -A1 "SCRIPT ERROR|Parse Error" "$IMPORT2" | head -40)"
  summary '```'
  fail=1
fi
other_errors="$(grep -E "ERROR: Failed" "$IMPORT2" | grep -vE "SCRIPT ERROR|Parse Error" || true)"
if [ -n "$other_errors" ]; then
  gha_warn "Godot import pass 2 logged $(printf '%s\n' "$other_errors" | wc -l | tr -d ' ') 'ERROR: Failed' line(s) (not fatal)"
  printf '%s\n' "$other_errors" | head -20 >&2
fi
if [ "$fail" -ne 0 ]; then
  tail -20 "$IMPORT2" >&2
  exit 1
fi
log "import clean"
[ "${GODOT_CI_IMPORT_ONLY:-0}" = "1" ] && { summary "Godot import: clean"; exit 0; }

# --- 3. tests -------------------------------------------------------------------------------------
TESTS="$LOG_DIR/tests.log"
if [ "$#" -gt 0 ]; then log "tests (filter '$1')..."; else log "tests..."; fi
run_godot --headless --path "$ROOT" -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$TESTS"
rc=${PIPESTATUS[0]}
result_line="$(grep -E '^\[tests\] [0-9]+ suite\(s\), ' "$TESTS" | tail -1)"
if is_timeout "$rc"; then
  gha_error "Godot tests timed out after ${TIMEOUT_S}s"
  exit 1
fi
if [ "$rc" -ne 0 ] || ! grep -qE '^\[tests\] PASSED' "$TESTS"; then
  gha_error "Godot tests failed (exit $rc). ${result_line:-no summary line printed}"
  summary "### Godot tests FAILED (exit $rc)"
  summary "${result_line:-no summary line printed}"
  summary '```'
  summary "$(grep -E '^FAIL ' "$TESTS" | head -60)"
  summary '```'
  exit 1
fi
summary "### Godot tests passed"
summary "$result_line"
log "tests passed"
exit 0

#!/usr/bin/env bash
# Guard against committing files GitHub will reject (>100 MB hard limit, >50 MB warning).
#
#   bash tools/ci/check_large_files.sh            checks every tracked file (git ls-files)
#
# Fails (exit 1) on any tracked file >= FAIL_MB (default 95); warns at >= WARN_MB (default 20).
# Read-only: it never changes the index or the working tree. Runs in CI and locally (Git Bash).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WARN_MB="${WARN_MB:-20}"
FAIL_MB="${FAIL_MB:-95}"
cd "$ROOT"

warn_b=$((WARN_MB * 1024 * 1024))
fail_b=$((FAIL_MB * 1024 * 1024))
status=0
total=0
count=0
# One stat per batch of files (a per-file subprocess is very slow under Git Bash). Files deleted in
# the working tree make stat complain; those are skipped.
while IFS=$'\t' read -r s f; do
  [ -n "$f" ] || continue
  total=$((total + s)); count=$((count + 1))
  if [ "$s" -ge "$fail_b" ]; then
    echo "::error file=$f::$f is $((s / 1048576)) MB (GitHub rejects files over 100 MB; use Git LFS or ignore it)"
    status=1
  elif [ "$s" -ge "$warn_b" ]; then
    echo "::warning file=$f::$f is $((s / 1048576)) MB (consider Git LFS)"
  fi
done < <(git ls-files -z | xargs -0 stat -c $'%s\t%n' 2>/dev/null)
echo "[large-files] $count tracked file(s), $((total / 1048576)) MB total; fail >= ${FAIL_MB} MB, warn >= ${WARN_MB} MB"
exit $status

#!/usr/bin/env bash
# Download (or reuse) the official Godot Linux x86_64 editor binary and verify it.
#
#   bash tools/ci/fetch_godot.sh [dest_dir]      prints the absolute binary path on stdout
#
# The zip comes from the godotengine/godot GitHub release for GODOT_VERSION (default 4.4.1-stable).
# Its SHA-512 must match BOTH the release's SHA512-SUMS.txt AND the hash pinned below (or in
# GODOT_SHA512), so a swapped release asset and a swapped checksum file are both caught. On a cache
# hit (zip + binary already in dest_dir) the zip is re-hashed against the pin; nothing is downloaded.
#
# Env:
#   GODOT_VERSION    release tag without the "v" (default 4.4.1-stable)
#   GODOT_SHA512     expected SHA-512 of the zip (default: the pin for 4.4.1-stable; required otherwise)
#   GODOT_CACHE_DIR  parent of the default dest_dir ($HOME/.cache/godot-ci)
#
# Needs curl, unzip, sha512sum (all present on ubuntu-latest and in Git Bash). Logs go to stderr.
set -euo pipefail

VERSION="${GODOT_VERSION:-4.4.1-stable}"
ZIP="Godot_v${VERSION}_linux.x86_64.zip"
BIN="Godot_v${VERSION}_linux.x86_64"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}"

# Pinned from https://github.com/godotengine/godot/releases/download/4.4.1-stable/SHA512-SUMS.txt
PIN_4_4_1="ef4e76880a514257175544952c61191106fdef3095b909bafed9fcbeb230c3e5533920a0f3012882dd4bbde83028a67549825794e2d2c3cf76eba7918b71370e"
if [ -n "${GODOT_SHA512:-}" ]; then
  PINNED="$GODOT_SHA512"
elif [ "$VERSION" = "4.4.1-stable" ]; then
  PINNED="$PIN_4_4_1"
else
  echo "[fetch_godot] GODOT_VERSION=$VERSION has no pinned hash; set GODOT_SHA512" >&2
  exit 2
fi

DEST="${1:-${GODOT_CACHE_DIR:-$HOME/.cache/godot-ci}/$VERSION}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

sha_of() { sha512sum "$1" | cut -d' ' -f1; }

if [ -f "$DEST/$ZIP" ] && [ -f "$DEST/$BIN" ]; then
  if [ "$(sha_of "$DEST/$ZIP")" = "$PINNED" ]; then
    chmod +x "$DEST/$BIN"
    echo "[fetch_godot] cached $BIN verified" >&2
    echo "$DEST/$BIN"
    exit 0
  fi
  echo "[fetch_godot] cached zip does not match the pin; downloading again" >&2
  rm -f "$DEST/$ZIP" "$DEST/$BIN"
fi

echo "[fetch_godot] downloading $BASE_URL/$ZIP" >&2
curl -fsSL --retry 3 --retry-delay 5 -o "$DEST/$ZIP.part" "$BASE_URL/$ZIP"
curl -fsSL --retry 3 --retry-delay 5 -o "$DEST/SHA512-SUMS.txt" "$BASE_URL/SHA512-SUMS.txt"

listed="$(awk -v f="$ZIP" '$2 == f || $2 == "*" f { print $1 }' "$DEST/SHA512-SUMS.txt")"
actual="$(sha_of "$DEST/$ZIP.part")"
if [ -z "$listed" ]; then
  echo "[fetch_godot] $ZIP is not listed in SHA512-SUMS.txt" >&2
  exit 1
fi
if [ "$actual" != "$listed" ]; then
  echo "[fetch_godot] SHA-512 mismatch against SHA512-SUMS.txt: got $actual, listed $listed" >&2
  exit 1
fi
if [ "$actual" != "$PINNED" ]; then
  echo "[fetch_godot] SHA-512 mismatch against the pinned hash: got $actual, pinned $PINNED" >&2
  exit 1
fi
mv "$DEST/$ZIP.part" "$DEST/$ZIP"
echo "[fetch_godot] SHA-512 verified (release checksum file + pin)" >&2

unzip -o -q "$DEST/$ZIP" "$BIN" -d "$DEST"
chmod +x "$DEST/$BIN"
echo "$DEST/$BIN"

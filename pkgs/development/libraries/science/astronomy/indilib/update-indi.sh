#!/usr/bin/env bash
#
# update-indi.sh — bump indilib + indi-3rdparty to the latest upstream release
# and build/test them inside the official `nixos/nix` Docker image.
#
# Why Docker: the host /nix store stays untouched; the build runs in a throwaway
# container using the official image's Nix.
#
# Usage:
#   ./update-indi.sh                 # detect latest release for both repos
#   ./update-indi.sh --version 2.3.0 # pin a specific version for both repos
#   ./update-indi.sh --no-build      # only rewrite version+hash, skip build/test
#
# Requirements: docker, curl, sed, grep (GNU).

set -euo pipefail

# --- config ---------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# nixpkgs repo root = 6 levels up from pkgs/development/libraries/science/astronomy/indilib
REPO="$(cd -- "$SCRIPT_DIR/../../../../../.." &>/dev/null && pwd)"
IMAGE="nixos/nix"
DEFAULT_NIX="$SCRIPT_DIR/default.nix"
TP_NIX="$SCRIPT_DIR/indi-3rdparty.nix"

PIN_VERSION=""
DO_BUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) PIN_VERSION="${2:?--version needs an argument}"; shift 2 ;;
    --no-build) DO_BUILD=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\s\?//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for tool in docker curl sed grep; do
  command -v "$tool" >/dev/null || { echo "error: '$tool' is required" >&2; exit 1; }
done

# --- helpers --------------------------------------------------------------

# Run Nix inside the official image, mounting the repo at /nixpkgs.
# NOTE: we must NOT bind-mount over /nix — that would hide the image's own Nix.
# The container store is therefore ephemeral (sources are re-fetched each run).
docker_nix() {
  docker run --rm -v "$REPO":/nixpkgs -w /nixpkgs "$IMAGE" "$@"
}

# Latest release tag (without leading "v") for indilib/<repo>.
latest_release() {
  curl -sSf "https://api.github.com/repos/indilib/$1/releases/latest" \
    | grep -oP '"tag_name":\s*"v?\K[^"]+'
}

# Build an attribute with a deliberately wrong hash and extract the real one
# from Nix's "got: sha256-..." mismatch message. Empty output => hash already ok.
real_hash() {
  docker_nix nix-build --no-out-link -A "$1" 2>&1 \
    | grep -oP 'got:\s+\K(sha256-\S+|[a-z0-9]{52})' | head -n1 || true
}

# --- 1. resolve target versions ------------------------------------------
if [[ -n "$PIN_VERSION" ]]; then
  INDI_VER="$PIN_VERSION"
  TP_VER="$PIN_VERSION"
else
  echo ">> Querying latest releases from GitHub..."
  INDI_VER="$(latest_release indi)"
  TP_VER="$(latest_release indi-3rdparty)"
fi
echo ">> indi           -> $INDI_VER"
echo ">> indi-3rdparty  -> $TP_VER"

# --- 2. rewrite version strings ------------------------------------------
echo ">> Rewriting version strings..."
sed -i -E "s|(version = )\"[^\"]*\";|\1\"$INDI_VER\";|" "$DEFAULT_NIX"
sed -i -E "s|(thirdparty_version = )\"[^\"]*\";|\1\"$TP_VER\";|" "$TP_NIX"

# --- 3. recompute hashes via the fake-hash technique ---------------------
FAKE='sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='

echo ">> Recomputing indilib source hash..."
sed -i -E "s|(hash = )\"sha256-[^\"]*\";|\1\"$FAKE\";|" "$DEFAULT_NIX"
INDI_HASH="$(real_hash indilib)"
[[ -n "$INDI_HASH" ]] || { echo "error: could not derive indilib hash" >&2; exit 1; }
sed -i -E "s|(hash = )\"$FAKE\";|\1\"$INDI_HASH\";|" "$DEFAULT_NIX"
echo "   indilib hash = $INDI_HASH"

echo ">> Recomputing indi-3rdparty source hash..."
# src-3rdparty hash lives in the `let` block; blank it, then any driver
# fetches the shared tarball and reveals the real hash.
sed -i -E "s|(hash = )\"(sha256-[^\"]*)?\";|\1\"$FAKE\";|" "$TP_NIX"
TP_HASH="$(real_hash indi-3rdparty.indi-eqmod)"
[[ -n "$TP_HASH" ]] || { echo "error: could not derive indi-3rdparty hash" >&2; exit 1; }
sed -i -E "s|(hash = )\"$FAKE\";|\1\"$TP_HASH\";|" "$TP_NIX"
echo "   indi-3rdparty hash = $TP_HASH"

# --- 4. build + test ------------------------------------------------------
if [[ "$DO_BUILD" -eq 1 ]]; then
  echo ">> Building and testing (indilib, indi-full, passthru test) in Docker..."
  docker_nix nix-build --no-out-link \
    -A indilib -A indi-full -A indilib.tests.indi-full
  echo ">> Build + tests passed."
else
  echo ">> Skipping build (--no-build)."
fi

echo ">> Done. Review with: git -C \"$REPO\" diff -- ${SCRIPT_DIR#"$REPO"/}"

#!/usr/bin/env bash
#
# refresh-codex-dmg.sh — re-pin the Codex.dmg hash + version in
# nix/codex-desktop.nix.
#
# OpenAI serves the *latest* Codex.dmg from a version-less URL
# (https://persistent.oaistatic.com/codex-app-prod/Codex.dmg). Whenever they
# republish, the pinned sha256 in nix/codex-desktop.nix goes stale and the
# build breaks. This script fetches the current DMG, computes its SRI hash,
# extracts CFBundleShortVersionString from the embedded Info.plist, and — only
# if the hash differs from what is pinned — rewrites the hash and version lines.
#
# It is meant to be run both locally (for testing) and from CI. When run under
# GitHub Actions it writes machine-readable outputs to $GITHUB_OUTPUT:
#   changed     = true|false
#   old_hash    / new_hash
#   old_version / new_version
#
# Requirements: nix (with nix-command + flakes enabled). No other tools needed;
# 7-Zip is pulled on demand via `nix run nixpkgs#_7zz`.
#
# Usage:
#   ci/refresh-codex-dmg.sh            # refresh in place
#   ci/refresh-codex-dmg.sh --check    # report only, never modify the file
#
# Exit status: 0 on success (whether or not anything changed). Non-zero only on
# an actual error (fetch failure, parse failure, etc.).

set -euo pipefail

DMG_URL="https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"

# Resolve the repo root from this script's location so it works regardless of
# the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NIX_FILE="$REPO_ROOT/nix/codex-desktop.nix"

CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
elif [[ -n "${1:-}" ]]; then
  echo "error: unknown argument '$1' (expected --check or nothing)" >&2
  exit 2
fi

log() { echo ">> $*" >&2; }

if [[ ! -f "$NIX_FILE" ]]; then
  echo "error: $NIX_FILE not found" >&2
  exit 1
fi

# --- Read the currently pinned values ------------------------------------
# The pinned hash lives inside the `codex-dmg = fetchurl { ... }` block as a
# line like:   hash = "sha256-....=";
# The version is a top-level line:   version = "26.519.81530";
old_hash="$(grep -oE 'hash = "sha256-[^"]+"' "$NIX_FILE" | head -1 | sed -E 's/^hash = "//; s/"$//')"
old_version="$(grep -oE 'version = "[^"]+"' "$NIX_FILE" | head -1 | sed -E 's/^version = "//; s/"$//')"

if [[ -z "$old_hash" ]]; then
  echo "error: could not find pinned 'hash = \"sha256-...\"' in $NIX_FILE" >&2
  exit 1
fi
if [[ -z "$old_version" ]]; then
  echo "error: could not find pinned 'version = \"...\"' in $NIX_FILE" >&2
  exit 1
fi

log "Pinned hash:    $old_hash"
log "Pinned version: $old_version"

# --- Fetch the current DMG and compute its hash + store path -------------
log "Prefetching $DMG_URL ..."
prefetch_json="$(nix store prefetch-file --json --name Codex.dmg "$DMG_URL")"

new_hash="$(printf '%s' "$prefetch_json" | nix run nixpkgs#jq -- -r '.hash')"
store_path="$(printf '%s' "$prefetch_json" | nix run nixpkgs#jq -- -r '.storePath')"

if [[ -z "$new_hash" || "$new_hash" == "null" ]]; then
  echo "error: prefetch did not return a hash; raw: $prefetch_json" >&2
  exit 1
fi
if [[ -z "$store_path" || "$store_path" == "null" || ! -e "$store_path" ]]; then
  echo "error: prefetch did not return a usable storePath; raw: $prefetch_json" >&2
  exit 1
fi

log "Fetched hash:   $new_hash"
log "Store path:     $store_path"

# --- Extract the version from the DMG ------------------------------------
# The DMG is a disk image; the old p7zip cannot read inside it, so we use
# modern 7-Zip (_7zz).
#
# Do NOT hardcode the bundle path. This step used to extract exactly
# "Codex.app/Contents/Info.plist" and broke on 2026-08-26 when OpenAI
# restructured the image: the app is now shipped as ChatGPT.app nested inside a
# volume directory, i.e.
#
#     ChatGPT Installer/ChatGPT.app/Contents/Info.plist
#
# so a top-level Codex.app never matched and every run failed with
# "Info.plist not found". Two things changed at once -- the bundle NAME and its
# DEPTH -- so we now discover the plist instead of assuming where it lives.
#
# Note the on-disk path after extraction is not the same as the listed path:
# 7-Zip materialises the volume by its display name ("ChatGPT Installer"),
# while the archive listing shows it as "Installer". Hence extract-then-find
# rather than predicting the path.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

log "Extracting Info.plist with 7-Zip ..."
# Pull only plists, not the whole 1.5 GiB image. 7-Zip exits non-zero on the
# image's unsupported symlinks/extended attrs even when the files we asked for
# came out fine, so tolerate the status and judge by what actually landed.
( cd "$work_dir" && nix run nixpkgs#_7zz -- x -y -r "$store_path" "*Contents/Info.plist" >/dev/null 2>&1 ) || true

# Picking the right plist is the whole problem. Measured on the 2026-08-27
# image: 41 Info.plist files ship inside it, and 14 of them are legitimately
# <X>.app/Contents/Info.plist -- Sparkle's Updater.app, four "Codex Framework"
# helper apps (Renderer/GPU/Alerts/Service), and several nested
# "Codex Computer Use.app" bundles. Any of them would yield a plausible but
# WRONG version, silently.
#
# So two rules, and both are load-bearing:
#   1. the ".app" must be the DIRECT grandparent -- <X>.app/Contents/Info.plist.
#      This drops the .docktileplugin plug-in and Sparkle's
#      .../Versions/B/Resources/Info.plist.
#   2. of what survives, take the SHALLOWEST. The outer application bundle is by
#      construction closer to the volume root than anything it embeds. With 14
#      survivors this is doing real filtering, not breaking a tie.
#
# If rule 2 ever finds a tie at minimum depth the image has two top-level apps
# and we must not guess -- fail loudly instead of silently versioning off the
# wrong one.
mapfile -t plist_candidates < <(
  find "$work_dir" -type f -name Info.plist 2>/dev/null \
    | awk -F/ 'NF>=3 && $(NF-2) ~ /\.app$/ && $(NF-1)=="Contents" { print NF"\t"$0 }' \
    | sort -n
)

if [[ ${#plist_candidates[@]} -eq 0 ]]; then
  echo "error: no <bundle>.app/Contents/Info.plist found in DMG after extraction" >&2
  echo "       (image layout changed again; inspect with:" >&2
  echo "          nix run nixpkgs#_7zz -- l -ba '$store_path' | head -40 )" >&2
  echo "       plists that WERE extracted, for reference:" >&2
  find "$work_dir" -type f -name Info.plist 2>/dev/null | sed 's|^|         |' >&2
  exit 1
fi

min_depth="${plist_candidates[0]%%$'\t'*}"
shallowest=()
for entry in "${plist_candidates[@]}"; do
  [[ "${entry%%$'\t'*}" == "$min_depth" ]] && shallowest+=( "${entry#*$'\t'}" )
done

if [[ ${#shallowest[@]} -ne 1 ]]; then
  echo "error: ambiguous application bundle -- ${#shallowest[@]} candidates at the same depth:" >&2
  printf '         %s\n' "${shallowest[@]#$work_dir/}" >&2
  echo "       refusing to guess which one carries the product version" >&2
  exit 1
fi

plist="${shallowest[0]}"
log "Using bundle plist: ${plist#$work_dir/} (${#plist_candidates[@]} .app plists in image)"

# XML plist: find <key>CFBundleShortVersionString</key> then the following
# <string>...</string>. grep -A1 gives us the key line plus the next line.
new_version="$(grep -A1 '<key>CFBundleShortVersionString</key>' "$plist" \
  | grep -oE '<string>[^<]+</string>' \
  | head -1 \
  | sed -E 's#</?string>##g')"

if [[ -z "$new_version" ]]; then
  echo "error: could not extract CFBundleShortVersionString from Info.plist" >&2
  exit 1
fi

log "Fetched version: $new_version"

# --- Emit GitHub Actions outputs (if running in CI) ----------------------
emit_outputs() {
  local changed="$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "changed=$changed"
      echo "old_hash=$old_hash"
      echo "new_hash=$new_hash"
      echo "old_version=$old_version"
      echo "new_version=$new_version"
    } >> "$GITHUB_OUTPUT"
  fi
}

# --- Compare and (optionally) rewrite ------------------------------------
if [[ "$new_hash" == "$old_hash" ]]; then
  log "Hash unchanged — nothing to do."
  if [[ "$new_version" != "$old_version" ]]; then
    # Same bytes but a different version string would be very surprising; warn
    # loudly but do not rewrite, since the build artifact is identical.
    log "WARNING: hash matches the pin but version differs ($old_version -> $new_version)."
    log "         Not rewriting because the DMG bytes are unchanged."
  fi
  emit_outputs "false"
  exit 0
fi

log "Hash CHANGED: $old_hash -> $new_hash"
log "Version:      $old_version -> $new_version"

if [[ "$CHECK_ONLY" == "1" ]]; then
  log "--check given; not modifying $NIX_FILE."
  emit_outputs "true"
  exit 0
fi

# Rewrite the hash line and the version line. Use a Python one-liner for an
# exact, anchored, single-replacement substitution (avoids sed escaping of the
# base64 hash, which contains / and +).
NIX_FILE="$NIX_FILE" \
OLD_HASH="$old_hash" NEW_HASH="$new_hash" \
OLD_VERSION="$old_version" NEW_VERSION="$new_version" \
python3 - <<'PY'
import os

path = os.environ["NIX_FILE"]
old_hash = os.environ["OLD_HASH"]
new_hash = os.environ["NEW_HASH"]
old_version = os.environ["OLD_VERSION"]
new_version = os.environ["NEW_VERSION"]

with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()

hash_token = f'hash = "{old_hash}"'
new_hash_token = f'hash = "{new_hash}"'
if text.count(hash_token) != 1:
    raise SystemExit(
        f"expected exactly one occurrence of {hash_token!r}, "
        f"found {text.count(hash_token)}"
    )
text = text.replace(hash_token, new_hash_token, 1)

version_token = f'version = "{old_version}"'
new_version_token = f'version = "{new_version}"'
if text.count(version_token) != 1:
    raise SystemExit(
        f"expected exactly one occurrence of {version_token!r}, "
        f"found {text.count(version_token)}"
    )
text = text.replace(version_token, new_version_token, 1)

with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY

log "Updated $NIX_FILE."
emit_outputs "true"
exit 0

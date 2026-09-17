#!/usr/bin/env bash
# Re-pin the official Linux package hash and version in nix/codex-desktop.nix.
#
# The historical filename is retained because external automation invokes it.
# Usage: ci/refresh-codex-dmg.sh [--check]

set -euo pipefail

DEB_URL="https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb"
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

old_hash="$(grep -oE 'hash = "sha256-[^"]+"' "$NIX_FILE" | head -1 | sed -E 's/^hash = "//; s/"$//')"
old_version="$(grep -oE 'version = "[^"]+"' "$NIX_FILE" | head -1 | sed -E 's/^version = "//; s/"$//')"

if [[ -z "$old_hash" || -z "$old_version" ]]; then
  echo "error: could not read the pinned hash and version from $NIX_FILE" >&2
  exit 1
fi

log "Prefetching $DEB_URL ..."
prefetch_json="$(nix store prefetch-file --json --name chatgpt_amd64.deb "$DEB_URL")"
new_hash="$(printf '%s' "$prefetch_json" | nix run nixpkgs#jq -- -r '.hash')"
store_path="$(printf '%s' "$prefetch_json" | nix run nixpkgs#jq -- -r '.storePath')"

if [[ -z "$new_hash" || "$new_hash" == "null" || ! -e "$store_path" ]]; then
  echo "error: prefetch did not return a usable hash and store path" >&2
  exit 1
fi

new_version="$(nix shell nixpkgs#dpkg -c dpkg-deb -f "$store_path" Version)"
if [[ -z "$new_version" ]]; then
  echo "error: could not read Version from the Debian package" >&2
  exit 1
fi

log "Pinned:  $old_version $old_hash"
log "Fetched: $new_version $new_hash"

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

if [[ "$new_hash" == "$old_hash" ]]; then
  if [[ "$new_version" != "$old_version" ]]; then
    echo "error: package hash is unchanged but its metadata version differs" >&2
    exit 1
  fi
  log "Package unchanged."
  emit_outputs false
  exit 0
fi

if [[ "$CHECK_ONLY" == 1 ]]; then
  log "Update available; leaving $NIX_FILE unchanged."
  emit_outputs true
  exit 0
fi

NIX_FILE="$NIX_FILE" \
OLD_HASH="$old_hash" NEW_HASH="$new_hash" \
OLD_VERSION="$old_version" NEW_VERSION="$new_version" \
python3 - <<'PY'
import os

path = os.environ["NIX_FILE"]
with open(path, "r", encoding="utf-8") as source:
    text = source.read()

replacements = (
    (f'hash = "{os.environ["OLD_HASH"]}"', f'hash = "{os.environ["NEW_HASH"]}"'),
    (f'version = "{os.environ["OLD_VERSION"]}"', f'version = "{os.environ["NEW_VERSION"]}"'),
)
for old, new in replacements:
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one occurrence of {old!r}")
    text = text.replace(old, new, 1)

with open(path, "w", encoding="utf-8") as destination:
    destination.write(text)
PY

log "Updated $NIX_FILE."
emit_outputs true

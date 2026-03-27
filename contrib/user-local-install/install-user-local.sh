#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

copy_file() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

copy_tree() {
    local root="$1"
    local rel
    while IFS= read -r rel; do
        if [ "$rel" = "./.local/share/applications/codex-desktop.desktop" ]; then
            mkdir -p "${HOME}/.local/share/applications"
            sed "s|@HOME@|${HOME}|g" "${root}/${rel}" > "${HOME}/${rel#./}"
            continue
        fi
        copy_file "${root}/${rel}" "${HOME}/${rel#./}"
    done < <(cd "$root" && find . -type f | sort)
}

copy_tree "$FILES_DIR"

chmod +x \
    "${HOME}/.local/bin/codex-desktop" \
    "${HOME}/.local/bin/codex-desktop-check-update" \
    "${HOME}/.local/bin/codex-desktop-update" \
    "${HOME}/.local/bin/codex-desktop-version" \
    "${HOME}/.local/lib/codex-desktop-linux/common.sh"

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now codex-desktop-update.timer >/dev/null 2>&1 || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
fi

if [ -x "${HOME}/.local/bin/codex-desktop-update" ]; then
    "${HOME}/.local/bin/codex-desktop-update" --record-only >/dev/null 2>&1 || true
fi

echo "Installed user-local Codex desktop integration."

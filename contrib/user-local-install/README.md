# User-Local Desktop Integration

This folder packages a user-local install layout for `codex-desktop-linux`.

It adds:

- a stable install root under `~/.local/opt/codex-desktop-linux`
- launch/check/update/version commands under `~/.local/bin`
- a desktop entry under `~/.local/share/applications`
- an icon extracted from the local `Codex.dmg`
- metadata tracking for the wrapper repo and cached `Codex.dmg`
- a weekly `systemd --user` timer for unattended update checks and rebuilds

## Files

The package is laid out as files relative to `$HOME`:

- `files/.local/bin/codex-desktop`
- `files/.local/bin/codex-desktop-check-update`
- `files/.local/bin/codex-desktop-update`
- `files/.local/bin/codex-desktop-version`
- `files/.local/lib/codex-desktop-linux/common.sh`
- `files/.local/share/applications/codex-desktop.desktop`
- `files/.config/systemd/user/codex-desktop-update.service`
- `files/.config/systemd/user/codex-desktop-update.timer`

## Expected Placement

If installing manually, copy the files to:

- `~/.local/bin/`
- `~/.local/lib/codex-desktop-linux/`
- `~/.local/share/applications/`
- `~/.config/systemd/user/`

The main wrapper repository itself should live at:

- `~/.local/opt/codex-desktop-linux`

That is the path assumed by the helper scripts.

## Install

From the repository root:

```bash
./contrib/user-local-install/install-user-local.sh
```

The installer:

1. copies the helper files into the user-local locations
2. makes the scripts executable
3. reloads the user `systemd` daemon if available
4. enables the weekly timer if the user bus is reachable
5. refreshes desktop metadata if available
6. records local metadata and extracts the icon if `Codex.dmg` already exists

## Commands

After installation:

```bash
codex-desktop
codex-desktop-check-update
codex-desktop-update
codex-desktop-version
```

## Notes

- The icon is not committed as a binary asset here. It is generated locally from `Codex.dmg`.
- The helper scripts track both upstream wrapper changes and upstream `Codex.dmg` headers.
- The weekly timer runs `codex-desktop-update --quiet`.

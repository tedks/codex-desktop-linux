{
  lib,
  stdenvNoCC,
  fetchurl,
  electron,
  p7zip,
  asar,
  nodejs,
  makeDesktopItem,
  python3,
  bash,
  node-pty,
  better-sqlite3,
}:
let
  pname = "codex-desktop";
  version = "26.415.21839";

  codex-dmg = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg";
    hash = "sha256-EiF/f8fnpA3P93/VswqtOK6cu6sftJyoyrOsr+DRPrw=";
  };

  sourceRoot = lib.cleanSourceWith {
    src = ./..;
    filter = path: type:
      let rel = lib.removePrefix (toString ./.. + "/") path;
      in !(lib.hasPrefix "result" rel)
      && !(lib.hasPrefix ".git" rel)
      && !(lib.hasPrefix "codex-app" rel);
  };

  electronUnwrapped = electron.passthru.unwrapped or electron;
  electronDir = "${electronUnwrapped}/libexec/electron";

  desktopItem = makeDesktopItem {
    name = "codex-desktop";
    exec = "codex-desktop %u";
    icon = "codex-desktop";
    type = "Application";
    terminal = false;
    desktopName = "Codex";
    genericName = "Codex Desktop";
    startupWMClass = "codex-desktop";
    categories = [ "Development" "Utility" ];
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = codex-dmg;

  nativeBuildInputs = [
    p7zip nodejs bash python3 asar
  ];

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR

    # --- Extract DMG ---
    echo "Extracting Codex DMG..."
    mkdir -p dmg-extract
    7z x -y -snl "$src" -odmg-extract || true

    # Find the .app bundle
    app_dir=$(find dmg-extract -maxdepth 3 -name "*.app" -type d | head -1)
    if [ -z "$app_dir" ]; then
      echo "ERROR: Could not find .app bundle in DMG"
      find dmg-extract -maxdepth 3 -type d
      exit 1
    fi
    echo "Found app: $app_dir"

    resources_dir="$app_dir/Contents/Resources"
    if [ ! -f "$resources_dir/app.asar" ]; then
      echo "ERROR: app.asar not found in $resources_dir"
      ls -la "$resources_dir" || true
      exit 1
    fi

    # --- Extract asar ---
    echo "Extracting app.asar..."
    asar extract "$resources_dir/app.asar" app-extracted

    # Merge unpacked native modules into extracted tree
    if [ -d "$resources_dir/app.asar.unpacked" ]; then
      cp -r "$resources_dir/app.asar.unpacked/"* app-extracted/ 2>/dev/null || true
    fi

    # Remove macOS-only modules
    rm -rf app-extracted/node_modules/sparkle-darwin 2>/dev/null || true
    find app-extracted -name "sparkle.node" -delete 2>/dev/null || true

    # --- Replace native modules with our Linux builds ---
    echo "Replacing native modules..."

    # node-pty: copy JS lib and native build
    rm -rf app-extracted/node_modules/node-pty/lib
    rm -rf app-extracted/node_modules/node-pty/build
    rm -rf app-extracted/node_modules/node-pty/bin
    rm -rf app-extracted/node_modules/node-pty/prebuilds
    cp -r ${node-pty}/lib/node_modules/node-pty/lib app-extracted/node_modules/node-pty/
    cp -r ${node-pty}/lib/node_modules/node-pty/build app-extracted/node_modules/node-pty/

    # better-sqlite3: copy JS lib and native build
    rm -rf app-extracted/node_modules/better-sqlite3/lib
    rm -rf app-extracted/node_modules/better-sqlite3/build
    cp -r ${better-sqlite3}/lib/node_modules/better-sqlite3/lib app-extracted/node_modules/better-sqlite3/
    cp -r ${better-sqlite3}/lib/node_modules/better-sqlite3/build app-extracted/node_modules/better-sqlite3/

    # --- Extract webview content ---
    echo "Extracting webview content..."
    mkdir -p webview-content
    if [ -d app-extracted/webview ]; then
      cp -r app-extracted/webview/* webview-content/
      # Replace transparent startup background with opaque color for Linux
      if [ -f webview-content/index.html ]; then
        sed -i 's/--startup-background: transparent/--startup-background: #1e1e1e/' webview-content/index.html
      fi
    else
      echo "WARNING: webview directory not found in asar"
    fi

    # --- Apply Linux UI patches ---
    echo "Applying Linux UI patches..."
    node ${sourceRoot}/scripts/patch-linux-window-ui.js app-extracted

    # --- Repack asar ---
    echo "Repacking app.asar..."
    asar pack app-extracted app.asar --unpack "{*.node,*.so,*.dylib}"

    echo "Build phase complete"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # --- Create custom Electron tree ---
    electron_tree=$out/lib/codex-desktop/electron
    mkdir -p $electron_tree/resources

    # Copy the ELF binary (MUST be real copy, not symlink, so
    # /proc/self/exe resolves to our tree and Chromium finds resources)
    cp ${electronDir}/electron $electron_tree/electron

    # Symlink everything else from electron-unwrapped
    for item in ${electronDir}/*; do
      name=$(basename "$item")
      [[ "$name" = "electron" ]] && continue
      [[ "$name" = "resources" ]] && continue
      ln -s "$item" "$electron_tree/$name"
    done

    # Populate resources/ -- start with Electron's own
    for item in ${electronDir}/resources/*; do
      ln -s "$item" "$electron_tree/resources/$(basename "$item")"
    done

    # Install our app.asar and unpacked resources
    cp app.asar $electron_tree/resources/
    if [ -d app.asar.unpacked ]; then
      cp -r app.asar.unpacked $electron_tree/resources/
    fi

    # --- Install webview content ---
    mkdir -p $out/lib/codex-desktop/content/webview
    if [ -d webview-content ] && [ "$(ls -A webview-content)" ]; then
      cp -r webview-content/* $out/lib/codex-desktop/content/webview/
    fi

    # --- Create the electron wrapper ---
    # Derive from stock nixpkgs electron wrapper (sets up GIO, GTK, etc.)
    # but exec our custom binary.
    head -n -1 ${electron}/bin/electron > $electron_tree/electron-wrapper
    echo "exec \"$electron_tree/electron\" \"\$@\"" >> $electron_tree/electron-wrapper
    chmod +x $electron_tree/electron-wrapper

    substituteInPlace $electron_tree/electron-wrapper \
      --replace-quiet "${electron}/libexec/electron/chrome-sandbox" \
        "$electron_tree/chrome-sandbox"

    # Convenience symlink
    ln -s $electron_tree/resources $out/lib/codex-desktop/resources

    # --- Install icon ---
    icon_src=${sourceRoot}/assets/codex.png
    if [ -f "$icon_src" ]; then
      for size in 16 32 48 64 128 256; do
        icon_dir=$out/share/icons/hicolor/"$size"x"$size"/apps
        mkdir -p "$icon_dir"
        cp "$icon_src" "$icon_dir/codex-desktop.png"
      done
    fi

    # --- Install .desktop file ---
    mkdir -p $out/share/applications
    install -Dm644 ${desktopItem}/share/applications/* $out/share/applications/

    # --- Install notification icon bundle ---
    mkdir -p $out/lib/codex-desktop/.codex-linux
    if [ -f "$icon_src" ]; then
      cp "$icon_src" $out/lib/codex-desktop/.codex-linux/codex-desktop.png
    fi

    # --- Create launcher script ---
    mkdir -p $out/bin
    cat > $out/bin/codex-desktop <<'LAUNCHER'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="LIBDIR_PLACEHOLDER"
ELECTRON_WRAPPER="ELECTRON_PLACEHOLDER"
WEBVIEW_DIR="$SCRIPT_DIR/content/webview"
LOG_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/codex-desktop"
LOG_FILE="$LOG_DIR/launcher.log"
APP_STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/codex-desktop"
APP_PID_FILE="$APP_STATE_DIR/app.pid"
APP_NOTIFICATION_ICON_NAME="codex-desktop"
APP_NOTIFICATION_ICON_BUNDLE="$SCRIPT_DIR/.codex-linux/$APP_NOTIFICATION_ICON_NAME.png"

mkdir -p "$LOG_DIR" "$APP_STATE_DIR"

if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: codex-desktop [OPTIONS] [-- ELECTRON_FLAGS...]

Launches the Codex Desktop app.

Options:
  -h, --help                  Show this help message and exit
  --disable-gpu               Completely disable GPU acceleration
  --disable-gpu-compositing   Disable GPU compositing (fixes flickering)
  --ozone-platform=x11        Force X11 instead of Wayland

Logs: ~/.cache/codex-desktop/launcher.log
HELP
    exit 0
fi

exec >>"$LOG_FILE" 2>&1

echo "[$(date -Is)] Starting Codex Desktop launcher (Nix)"

resolve_notification_icon() {
    if [ -f "$APP_NOTIFICATION_ICON_BUNDLE" ]; then
        echo "$APP_NOTIFICATION_ICON_BUNDLE"
    else
        echo "$APP_NOTIFICATION_ICON_NAME"
    fi
}

notify_error() {
    local message="$1"
    local icon
    icon="$(resolve_notification_icon)"
    echo "$message"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send \
            -a "Codex Desktop" \
            -i "$icon" \
            -h "string:desktop-entry:codex-desktop" \
            "Codex Desktop" \
            "$message"
    fi
}

find_codex_cli() {
    if command -v codex >/dev/null 2>&1; then
        command -v codex
        return 0
    fi

    if [ -s "''${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
        export NVM_DIR="''${NVM_DIR:-$HOME/.nvm}"
        # shellcheck disable=SC1090
        . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
        if command -v codex >/dev/null 2>&1; then
            command -v codex
            return 0
        fi
    fi

    local candidate
    for candidate in \
        "$HOME/.nvm/versions/node/current/bin/codex" \
        "$HOME/.local/share/pnpm/codex" \
        "$HOME/.local/bin/codex" \
        "/usr/local/bin/codex" \
        "/usr/bin/codex"
    do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

wait_for_webview_server() {
    echo "Waiting for webview server on :5175"
    local attempt
    for attempt in $(seq 1 50); do
        if python3 -c "import socket; s=socket.socket(); s.settimeout(0.5); s.connect(('127.0.0.1', 5175)); s.close()" 2>/dev/null; then
            echo "Webview server is ready"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

verify_webview_origin() {
    local url="$1"
    python3 - "$url" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
required_markers = ("<title>Codex</title>", "startup-loader")

with urllib.request.urlopen(url, timeout=2) as response:
    body = response.read(8192).decode("utf-8", "ignore")

missing = [marker for marker in required_markers if marker not in body]
if missing:
    raise SystemExit(
        f"Webview origin validation failed for {url}; missing markers: {', '.join(missing)}"
    )
PY
}

clear_stale_pid_file() {
    if [ ! -f "$APP_PID_FILE" ]; then
        return 0
    fi
    local pid=""
    pid="$(cat "$APP_PID_FILE" 2>/dev/null || true)"
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$APP_PID_FILE"
    fi
}

clear_stale_pid_file

# Kill any stale webview server.  Use fuser (port-based) rather than
# pkill (process-name-based) because inside the FHS bubblewrap
# namespace pkill can't see processes started outside the namespace.
fuser -k 5175/tcp 2>/dev/null || true
sleep 0.5

if [ -d "$WEBVIEW_DIR" ] && [ "$(ls -A "$WEBVIEW_DIR" 2>/dev/null)" ]; then
    cd "$WEBVIEW_DIR"
    nohup python3 -m http.server 5175 &
    HTTP_PID=$!
    trap "kill $HTTP_PID 2>/dev/null" EXIT

    echo "Started webview server pid=$HTTP_PID dir=$WEBVIEW_DIR"

    if ! wait_for_webview_server; then
        notify_error "Codex Desktop webview server did not become ready on port 5175."
        exit 1
    fi

    if ! kill -0 "$HTTP_PID" 2>/dev/null; then
        notify_error "Codex Desktop webview server exited before Electron launch."
        exit 1
    fi

    if ! verify_webview_origin "http://127.0.0.1:5175/index.html"; then
        notify_error "Codex Desktop webview origin validation failed."
        exit 1
    fi

    echo "Webview origin verified."
fi

if [ -z "''${CODEX_CLI_PATH:-}" ]; then
    CODEX_CLI_PATH="$(find_codex_cli || true)"
    export CODEX_CLI_PATH
fi
export CHROME_DESKTOP="''${CHROME_DESKTOP:-codex-desktop.desktop}"

if [ -z "$CODEX_CLI_PATH" ]; then
    notify_error "Codex CLI not found. Install with: npm i -g @openai/codex"
    exit 1
fi

echo "Using CODEX_CLI_PATH=$CODEX_CLI_PATH"

# Tell Electron the app is packaged so it uses process.resourcesPath
# (computed from /proc/self/exe) for resource resolution.
export ELECTRON_FORCE_IS_PACKAGED=true

echo "$$" > "$APP_PID_FILE"
exec "$ELECTRON_WRAPPER" \
    --no-sandbox \
    --class=codex-desktop \
    --app-id=codex-desktop \
    --ozone-platform-hint=auto \
    --disable-gpu-sandbox \
    --disable-gpu-compositing \
    --enable-features=WaylandWindowDecorations \
    "$@"
LAUNCHER

    substituteInPlace $out/bin/codex-desktop \
      --replace-fail "LIBDIR_PLACEHOLDER" "$out/lib/codex-desktop" \
      --replace-fail "ELECTRON_PLACEHOLDER" "$electron_tree/electron-wrapper"
    chmod +x $out/bin/codex-desktop

    runHook postInstall
  '';

  meta = with lib; {
    description = "Codex Desktop for Linux";
    homepage = "https://github.com/tedks/codex-desktop-linux";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "codex-desktop";
  };
}

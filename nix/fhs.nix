{
  buildFHSEnv,
  codex-desktop,
  python3,
  glibc,
  stdenv,

  # Graphics
  mesa,
  libGL,
  libdrm,
  vulkan-loader,
  libxkbcommon,

  # X11
  xorg,

  # Wayland
  wayland,

  # GTK / UI
  gtk3,
  pango,
  cairo,
  atk,
  gdk-pixbuf,
  glib,
  at-spi2-atk,
  at-spi2-core,

  # Fonts
  fontconfig,
  freetype,
  dejavu_fonts,
  liberation_ttf,

  # Audio
  alsa-lib,
  pipewire,
  pulseaudio,

  # System
  nss,
  nspr,
  cups,
  dbus,
  expat,
  systemd,
  libgbm,
  psmisc,  # fuser (kill stale webview server by port)
  openssh,  # ssh (remote connections discovery)
  libnotify,
  xdg-utils,
  tpm2-tss,
  libusb1,
  xz,

  # Network
  curl,
  openssl,
}:
buildFHSEnv {
  name = "codex-desktop";

  targetPkgs = pkgs: [
    codex-desktop
    python3
    glibc
    stdenv.cc.cc.lib  # libstdc++.so.6

    # Graphics
    mesa
    libGL
    libdrm
    vulkan-loader
    libxkbcommon

    # X11
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    xorg.libXcursor
    xorg.libXi
    xorg.libXtst
    xorg.libXScrnSaver

    # Wayland
    wayland

    # GTK / UI
    gtk3
    pango
    cairo
    atk
    gdk-pixbuf
    glib
    at-spi2-atk
    at-spi2-core

    # Fonts
    fontconfig
    freetype
    dejavu_fonts
    liberation_ttf

    # Audio
    alsa-lib
    pipewire
    pulseaudio

    # System
    nss
    nspr
    cups
    dbus
    expat
    systemd
    libgbm
    psmisc
    openssh
    libnotify
    xdg-utils
    tpm2-tss
    libusb1
    xz

    # Network
    curl
    openssl
  ];

  runScript = "${codex-desktop}/bin/codex-desktop";

  extraInstallCommands = ''
    # Copy desktop integration from the inner derivation when present.
    for share_dir in applications icons pixmaps metainfo; do
      if [ -d "${codex-desktop}/share/$share_dir" ]; then
        mkdir -p "$out/share/$share_dir"
        cp -r "${codex-desktop}/share/$share_dir/." "$out/share/$share_dir/"
      fi
    done

    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail \
        "Exec=${codex-desktop}/bin/chatgpt %U" \
        "Exec=$out/bin/codex-desktop %U"
  '';

  meta = codex-desktop.meta // {
    description = "Codex Desktop for Linux (FHS environment)";
  };
}

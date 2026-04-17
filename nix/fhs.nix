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

    # Network
    curl
    openssl
  ];

  runScript = "${codex-desktop}/bin/codex-desktop";

  extraInstallCommands = ''
    # Copy desktop file and icons from inner derivation
    mkdir -p $out/share/applications
    cp ${codex-desktop}/share/applications/* $out/share/applications/

    mkdir -p $out/share/icons
    cp -r ${codex-desktop}/share/icons/* $out/share/icons/
  '';

  meta = codex-desktop.meta // {
    description = "Codex Desktop for Linux (FHS environment)";
  };
}

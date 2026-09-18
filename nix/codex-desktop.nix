{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  makeWrapper,
  ...
}:

stdenvNoCC.mkDerivation rec {
  pname = "codex-desktop";
  version = "26.915.31029";

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
    hash = "sha256-kyglt2pB6AZDIEqaqcz9HLJHH/v8vh0xSZQ2D8qv+zU=";
  };

  nativeBuildInputs = [
    dpkg
    makeWrapper
  ];

  # OpenAI's Linux build is a complete Owl application linked for supported
  # host distributions. Rewriting or stripping it would invalidate that build.
  dontPatchELF = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/bin" "$out/share/applications"
    cp -a source/usr/lib/chatgpt "$out/lib/"

    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt"
    ln -s chatgpt "$out/bin/codex-desktop"

    cp source/usr/share/applications/chatgpt.desktop \
      "$out/share/applications/chatgpt.desktop"
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail 'Exec=chatgpt %U' "Exec=$out/bin/chatgpt %U"

    if [ -f source/usr/share/pixmaps/chatgpt.png ]; then
      mkdir -p "$out/share/pixmaps"
      cp source/usr/share/pixmaps/chatgpt.png "$out/share/pixmaps/"
    fi

    if [ -d source/usr/share/metainfo ]; then
      mkdir -p "$out/share/metainfo"
      cp -a source/usr/share/metainfo/. "$out/share/metainfo/"
    fi

    runHook postInstall
  '';

  meta = {
    description = "OpenAI Codex desktop application for Linux";
    homepage = "https://openai.com/codex/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "chatgpt";
  };
}

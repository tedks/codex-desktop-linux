{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  python3,
  node-gyp,
  electron,
}:
let
  electronHeaders = electron.passthru.headers;
in
buildNpmPackage rec {
  pname = "node-pty";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "node-pty";
    rev = "v${version}";
    hash = "sha256-R0QxTw3tNJvW4aEi+GOF0iZhGgI42HTYJih90CdF18I=";
  };

  npmDepsHash = "sha256-HRv/4NO7CHkPs7ld8lx61n2cty0EhmWVrpH/1Vqh+Nk=";

  nativeBuildInputs = [ python3 node-gyp ];

  # chokidar (dev dep) has an optional dep on fsevents (macOS-only).
  # The Nix npm deps fetcher excludes it, so npm ci sees a lock/json
  # mismatch.  Strip the reference from the lock file to fix the sync.
  postPatch = ''
    sed -i '/"fsevents"/d' package-lock.json
  '';

  # Build against Electron's Node headers (ABI 143) rather than
  # standalone Node (ABI 137).  Without this the .node file won't
  # load inside Electron.
  buildPhase = ''
    runHook preBuild
    npm run build
    # npm_config_nodedir forces node-gyp to use Electron headers
    # instead of the system Node.js headers.
    export npm_config_nodedir=${electronHeaders}
    node-gyp rebuild
    runHook postBuild
  '';

  # npmInstallHook doesn't copy the native addon -- do it ourselves.
  postInstall = ''
    cp -r build $out/lib/node_modules/node-pty/
  '';

  meta = with lib; {
    description = "Fork pseudoterminals in Node.JS";
    homepage = "https://github.com/microsoft/node-pty";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}

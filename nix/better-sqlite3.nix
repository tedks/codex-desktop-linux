{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  nodejs,
  node-gyp,
  electron,
}:
let
  electronHeaders = electron.passthru.headers;
in
stdenv.mkDerivation rec {
  pname = "better-sqlite3";
  version = "12.8.0";

  src = fetchFromGitHub {
    owner = "WiseLibs";
    repo = "better-sqlite3";
    rev = "v${version}";
    hash = "sha256-B9SHvlSK9Heqhp3maCPRf08tatXzLi5m2zcnU5o2Y0E=";
  };

  nativeBuildInputs = [ python3 nodejs node-gyp ];

  # No configure step — node-gyp handles everything.
  dontConfigure = true;

  # Build against Electron's Node headers rather than standalone
  # Node.js.  better-sqlite3 bundles its own SQLite source in deps/,
  # so no external SQLite dependency is needed.
  #
  # IMPORTANT: We bypass the nixpkgs node-gyp wrapper because it
  # hardcodes npm_config_nodedir to the system Node.js path, and
  # env vars override CLI --nodedir flags in node-gyp's arg parser.
  # Calling node-gyp.js directly via node avoids this.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export npm_config_nodedir=${electronHeaders}
    node ${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js rebuild --release
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/node_modules/better-sqlite3
    cp -r lib $out/lib/node_modules/better-sqlite3/
    cp -r build $out/lib/node_modules/better-sqlite3/
    cp package.json $out/lib/node_modules/better-sqlite3/
    runHook postInstall
  '';

  meta = with lib; {
    description = "The fastest and simplest library for SQLite in Node.js";
    homepage = "https://github.com/WiseLibs/better-sqlite3";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}

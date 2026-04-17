{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  nodejs,
  node-gyp,
}:
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

  # better-sqlite3 bundles its own SQLite source in deps/, so no
  # external SQLite dependency is needed.  Just run node-gyp directly.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    node-gyp rebuild --release --nodedir=${nodejs}/include/node
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

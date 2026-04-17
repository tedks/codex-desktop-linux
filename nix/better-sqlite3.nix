{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  python3,
  node-gyp,
}:
buildNpmPackage rec {
  pname = "better-sqlite3";
  version = "12.8.0";

  src = fetchFromGitHub {
    owner = "WiseLibs";
    repo = "better-sqlite3";
    rev = "v${version}";
    hash = "sha256-B9SHvlSK9Heqhp3maCPRf08tatXzLi5m2zcnU5o2Y0E=";
  };

  npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  nativeBuildInputs = [ python3 node-gyp ];

  # The install script tries prebuild-install (download prebuilt binary)
  # then falls back to node-gyp.  In Nix we skip the download attempt
  # and build from source directly.  The SQLite source is bundled in deps/.
  dontNpmInstall = true;

  buildPhase = ''
    runHook preBuild
    node-gyp rebuild --release
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

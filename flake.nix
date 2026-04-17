{
  description = "Codex Desktop for Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem = { pkgs, system, ... }: let
        node-pty = pkgs.callPackage ./nix/node-pty.nix { };
        better-sqlite3 = pkgs.callPackage ./nix/better-sqlite3.nix { };
        codex-desktop = pkgs.callPackage ./nix/codex-desktop.nix {
          inherit node-pty better-sqlite3;
        };
        codex-desktop-fhs = pkgs.callPackage ./nix/fhs.nix {
          inherit codex-desktop;
        };
      in {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (inputs.nixpkgs.lib.getName pkg) [
              "codex-desktop"
            ];
        };

        packages = {
          inherit node-pty better-sqlite3 codex-desktop codex-desktop-fhs;
          default = codex-desktop-fhs;
        };
      };

      flake = {
        overlays.default = final: prev: let
          node-pty = final.callPackage ./nix/node-pty.nix { };
          better-sqlite3 = final.callPackage ./nix/better-sqlite3.nix { };
        in {
          codex-desktop = final.callPackage ./nix/codex-desktop.nix {
            inherit node-pty better-sqlite3;
          };
          codex-desktop-fhs = final.callPackage ./nix/fhs.nix {
            codex-desktop = final.codex-desktop;
          };
        };
      };
    };
}

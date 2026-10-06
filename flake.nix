{
  description = "jkpkgs: personal binary packages for AI/LLM tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.herdr = {
    url = "github:herdrdev/herdr?ref=master";
    flake = false;
  };
  inputs.drovr = {
    url = "github:AVGVSTVS96/herdr-drovr?ref=main";
    flake = false;
  };
  inputs.rust-overlay = {
    url = "github:oxalica/rust-overlay";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, herdr, drovr, rust-overlay }:
    let
      # Nixpkgs 26.11 dropped x86_64-darwin; retain its package asset hashes
      # for older consumers but do not evaluate that unsupported system here.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      dshSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      rustPlatformFor =
        pkgs:
        let
          rustPkgs = pkgs.extend rust-overlay.overlays.default;
          rustToolchain = rustPkgs.rust-bin.fromRustupToolchainFile "${herdr}/rust-toolchain.toml";
        in
        pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };
    in
    {
      overlays.default = import ./overlays/default.nix;

      packages = forAllSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          claude-code = pkgs.callPackage ./packages/claude-code/package.nix { };
          opencode = pkgs.callPackage ./packages/opencode/package.nix { };
          opencode2 = pkgs.callPackage ./packages/opencode2/package.nix { };
          codex = pkgs.callPackage ./packages/codex/package.nix { };
          ccstatusline = pkgs.callPackage ./packages/ccstatusline/package.nix { };
          pi = pkgs.callPackage ./packages/pi/package.nix { };
          oh-my-pi = pkgs.callPackage ./packages/oh-my-pi/package.nix { };
          herdr = pkgs.callPackage ./packages/herdr/package.nix {
            herdrSource = herdr;
            rustPlatform = rustPlatformFor pkgs;
          };
          herdr-drovr = pkgs.callPackage ./packages/herdr-drovr/package.nix {
            drovrSource = drovr;
          };
          paseo = pkgs.callPackage ./packages/paseo/package.nix { };
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
          claude-desktop = pkgs.callPackage ./packages/claude-desktop/package.nix { };
          paseo-desktop = pkgs.callPackage ./packages/paseo-desktop/package.nix { };
          orca = pkgs.callPackage ./packages/orca/package.nix { };
        }
        // pkgs.lib.optionalAttrs (pkgs.lib.elem system dshSystems) {
          dsh = pkgs.callPackage ./packages/dsh/package.nix { };
        }
      );

      checks = forAllSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          packages = self.packages.${system};
          # Every runtime test a package declares runs in CI. The bare
          # package name holds its version smoke test (the historical
          # check); any other passthru.tests entry gets a sibling
          # `<package>-<test>` key, so no flake edit is needed when a
          # package adds its own tests.
          #
          # dsh-webStartup is temporarily excluded: dsh 0.2.1-alpha.1's
          # `dsh web` fails deterministically under node 24
          # (node-addon-require-builtin "Unsupported/no-getter"), inside
          # the sandbox and on the desktop alike. The test stays in
          # package.nix (it is correct — the product is broken); drop
          # this entry once a dsh bump boots again.
          excludedRuntimeTests = [ "dsh-webStartup" ];
          extraTests = pkgs.lib.removeAttrs (pkgs.lib.concatMapAttrs (
            name: package:
              pkgs.lib.mapAttrs' (
                test: drv: pkgs.lib.nameValuePair "${name}-${test}" drv
              ) (pkgs.lib.filterAttrs (test: _: test != "version") (package.passthru.tests or { }))
          ) packages) excludedRuntimeTests;
          dsh-platform-matrix =
            assert self.packages.x86_64-linux ? dsh;
            assert self.packages.aarch64-darwin ? dsh;
            assert !(self.packages.aarch64-linux ? dsh);
            assert !(self.packages ? "x86_64-darwin");
            pkgs.runCommand "dsh-platform-matrix" { } "touch $out";
        in
        pkgs.lib.mapAttrs (
          _: package: pkgs.lib.attrByPath [ "passthru" "tests" "version" ] package package
        ) packages
        // extraTests
        // {
          inherit dsh-platform-matrix;
        }
      );
    };
}

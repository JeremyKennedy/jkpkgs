{
  description = "jkpkgs: personal binary packages for AI/LLM tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
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
          claude-desktop =
            if system == "x86_64-linux" then
              pkgs.callPackage ./packages/claude-desktop/package.nix { }
            else
              pkgs.callPackage ./packages/claude-desktop/package-legacy.nix {
                patchy-cnb = pkgs.callPackage ./packages/claude-desktop/patchy-cnb.nix { };
              };
          opencode = pkgs.callPackage ./packages/opencode/package.nix { };
          opencode2 = pkgs.callPackage ./packages/opencode2/package.nix { };
          codex = pkgs.callPackage ./packages/codex/package.nix { };
          ccstatusline = pkgs.callPackage ./packages/ccstatusline/package.nix { };
          pi = pkgs.callPackage ./packages/pi/package.nix { };
          oh-my-pi = pkgs.callPackage ./packages/oh-my-pi/package.nix { };
          herdr = pkgs.callPackage ./packages/herdr/package.nix { };
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
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
        // {
          inherit dsh-platform-matrix;
        }
      );
    };
}

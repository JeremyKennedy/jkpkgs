{
  description = "jkpkgs: personal binary packages for AI/LLM tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
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
          patchy-cnb = pkgs.callPackage ./packages/claude-desktop/patchy-cnb.nix { };
        in
        {
          claude-code = pkgs.callPackage ./packages/claude-code/package.nix { };
          claude-desktop = pkgs.callPackage ./packages/claude-desktop/package.nix { inherit patchy-cnb; };
          opencode = pkgs.callPackage ./packages/opencode/package.nix { };
          opencode2 = pkgs.callPackage ./packages/opencode2/package.nix { };
          codex = pkgs.callPackage ./packages/codex/package.nix { };
          ccstatusline = pkgs.callPackage ./packages/ccstatusline/package.nix { };
          pi = pkgs.callPackage ./packages/pi/package.nix { };
          oh-my-pi = pkgs.callPackage ./packages/oh-my-pi/package.nix { };
          herdr = pkgs.callPackage ./packages/herdr/package.nix { };
        }
      );

      checks = forAllSystems (pkgs: {
        claude-code = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
        claude-desktop = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
        opencode = self.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
        opencode2 = self.packages.${pkgs.stdenv.hostPlatform.system}.opencode2;
        codex = self.packages.${pkgs.stdenv.hostPlatform.system}.codex;
        ccstatusline = self.packages.${pkgs.stdenv.hostPlatform.system}.ccstatusline;
        pi = self.packages.${pkgs.stdenv.hostPlatform.system}.pi;
        oh-my-pi = self.packages.${pkgs.stdenv.hostPlatform.system}.oh-my-pi;
        herdr = self.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
      });
    };
}

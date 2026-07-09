{
  description = "jkpkgs: personal binary packages for AI/LLM tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      overlays.default = import ./overlays/default.nix;

      packages = forAllSystems (pkgs: let
        patchy-cnb = pkgs.callPackage ./packages/claude-desktop/patchy-cnb.nix { };
      in {
        claude-code = pkgs.callPackage ./packages/claude-code/package.nix { };
        claude-desktop = pkgs.callPackage ./packages/claude-desktop/package.nix { inherit patchy-cnb; };
        opencode = pkgs.callPackage ./packages/opencode/package.nix { };
        codex = pkgs.callPackage ./packages/codex/package.nix { };
        ccstatusline = pkgs.callPackage ./packages/ccstatusline/package.nix { };
        pi = pkgs.callPackage ./packages/pi/package.nix { };
      });

      checks = forAllSystems (pkgs: {
        claude-code = self.packages.${pkgs.system}.claude-code;
        claude-desktop = self.packages.${pkgs.system}.claude-desktop;
        opencode = self.packages.${pkgs.system}.opencode;
        codex = self.packages.${pkgs.system}.codex;
        ccstatusline = self.packages.${pkgs.system}.ccstatusline;
        pi = self.packages.${pkgs.system}.pi;
      });
    };
}
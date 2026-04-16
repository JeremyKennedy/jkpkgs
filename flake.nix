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
      packages = forAllSystems (pkgs: let
        patchy-cnb = pkgs.callPackage ./packages/claude-desktop/patchy-cnb.nix { };
      in {
        claude-code = pkgs.callPackage ./packages/claude-code/package.nix { };
        claude-desktop = pkgs.callPackage ./packages/claude-desktop/package.nix { inherit patchy-cnb; };
        opencode = pkgs.callPackage ./packages/opencode/package.nix { };
        ccstatusline = pkgs.callPackage ./packages/ccstatusline/package.nix { };
      });

      checks = forAllSystems (pkgs: {
        claude-code = self.packages.${pkgs.system}.claude-code;
        claude-desktop = self.packages.${pkgs.system}.claude-desktop;
        opencode = self.packages.${pkgs.system}.opencode;
        ccstatusline = self.packages.${pkgs.system}.ccstatusline;
      });
    };
}

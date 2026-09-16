{
  applyPatches,
  callPackage,
  herdrSource,
  rustPlatform,
}:

let
  patchedSource = applyPatches {
    name = "herdr-source-patched";
    src = herdrSource;
    patches = [
      ./patches/omp-title-normalization.patch
      ./patches/handoff-title-state.patch
      ./patches/config-writer-safety.patch
    ];
  };
  basePackage = callPackage "${herdrSource}/nix/package.nix" { inherit rustPlatform; };
in
basePackage.overrideAttrs (_: {
  src = patchedSource;
})

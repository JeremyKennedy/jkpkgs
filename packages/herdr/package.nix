{
  callPackage,
  herdrSource,
  rustPlatform,
}:

let
  basePackage = callPackage "${herdrSource}/nix/package.nix" { inherit rustPlatform; };
in
basePackage.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./patches/omp-title-normalization.patch
    ./patches/handoff-title-state.patch
    ./patches/config-writer-safety.patch
  ];
})

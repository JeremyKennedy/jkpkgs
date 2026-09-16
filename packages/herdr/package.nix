{
  callPackage,
  herdrSource,
  rustPlatform,
}:

let
  version = "0.9.0";
in
(callPackage "${herdrSource}/nix/package.nix" { inherit rustPlatform; }).overrideAttrs (_: {
  inherit version;
  __intentionallyOverridingVersion = true;
})

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

output_kind=packages
if [[ ${1:-} == --checks ]]; then
    output_kind=checks
    shift
fi

system=$(nix eval --impure --raw --expr 'builtins.currentSystem')
if (($# == 0)); then
    mapfile -t installables < <(
        nix eval --impure --raw --apply "f: f \"${output_kind}\"" --expr '
          outputKind:
          let
            flake = builtins.getFlake (toString ./.);
            system = builtins.currentSystem;
            outputs =
              if outputKind == "checks"
              then flake.checks.${system}
              else flake.packages.${system};
          in
          builtins.concatStringsSep "\n" (
            map (name: ".#" + outputKind + "." + system + "." + name)
              (builtins.attrNames outputs)
          )
        '
    )
else
    installables=()
    for name in "$@"; do
        nix eval ".#${output_kind}.${system}.${name}" >/dev/null
        installables+=( ".#${output_kind}.${system}.${name}" )
    done
fi

nix build "${installables[@]}"

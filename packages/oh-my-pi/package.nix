{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  makeWrapper,
}:

# oh-my-pi ships as a bun-compiled single-file executable per platform (the
# `--binary` install mode from omp.sh). It is bun-native (#!/usr/bin/env bun,
# uses Bun.* APIs, engines.bun >= 1.3.14) and pulls heavy native deps, so the
# buildNpmPackage + node wrapper used for `pi` does not apply — we fetch the
# prebuilt binary directly.
#
# CRITICAL PACKAGING CONSTRAINT — do the ELF surgery by hand, minimally:
# bun standalone executables embed the entire app (a ~170MB /$bunfs/ trailer
# holding cli.js, native addons and wasm) appended after the ELF image and
# located via byte offsets baked into the file. Any patchelf operation that
# resizes the ELF shifts those offsets and corrupts the trailer:
#   * autoPatchelfHook / --set-rpath  -> grows the dynamic section, offsets
#     break, bun either falls back to its plain runtime CLI ("Script not found")
#     or SIGSEGVs on startup.
#   * --set-interpreter ALONE         -> patched in place, trailer intact, works.
# So we ONLY rewrite the interpreter.
#
# The interpreter is the host's nix-ld loader (/lib64/ld-linux-x86-64.so.2),
# NOT the nixpkgs stdenv one: nix-ld carries glibc/libstdc++/zlib in its own
# baked-in search path, so omp needs no LD_LIBRARY_PATH. We previously
# injected LD_LIBRARY_PATH via wrapProgram instead — but that variable
# propagates into every child omp spawns (agent shells, uv, venv pythons)
# and segfaults any nix python linked against a different glibc, because
# LD_LIBRARY_PATH preempts their RUNPATH. nix-ld's search path applies only
# to binaries that use the nix-ld interpreter, so children stay clean.
# Requires programs.nix-ld.enable on the host (all interactive hosts have it).
# Verified: `omp models` exits 0.
let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  asset =
    {
      x86_64-linux = "omp-linux-x64";
      aarch64-linux = "omp-linux-arm64";
      aarch64-darwin = "omp-darwin-arm64";
      x86_64-darwin = "omp-darwin-x64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "oh-my-pi: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "oh-my-pi";
  inherit version;

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/${asset}";
    hash = hashes.${stdenv.hostPlatform.system};
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Stripping would rewrite the ELF and break the embedded bun trailer.
  dontStrip = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    patchelf
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/omp
    runHook postInstall
  '';

  # Linux only: repoint the interpreter at the host nix-ld loader
  # (trailer-safe). Darwin gets the Mach-O binary as-is.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $out/bin/omp
  '';

  meta = {
    description = "oh-my-pi (omp): bun-native coding agent";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = lib.licenses.mit;
    mainProgram = "omp";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}

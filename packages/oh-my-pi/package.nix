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
# So we ONLY rewrite the interpreter, then supply libc/libstdc++ through a
# wrapper's LD_LIBRARY_PATH instead of rpath. Verified: `omp models` exits 0.
# Runtime deps: glibc (libc/pthread/dl/m) plus gcc-lib for the native addons.
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
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/omp
    runHook postInstall
  '';

  # Linux only: patch the interpreter in place (trailer-safe) and inject libc
  # via LD_LIBRARY_PATH. Darwin gets the Mach-O binary as-is.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" $out/bin/omp
    wrapProgram $out/bin/omp \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.libc stdenv.cc.cc.lib ]}"
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

{
  lib,
  stdenvNoCC,
  fetchurl,
  binutils,
  gnutar,
  autoPatchelfHook,
  testers,
  gtk3,
  libnotify,
  nspr,
  nss,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cups,
  dbus,
  cairo,
  pango,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libgbm,
  libdrm,
  expat,
  libxcb,
  libxkbcommon,
  libsecret,
  systemd,
  alsa-lib,
  wayland,
  libxshmfence,
  zlib,
  gcc,
  libseccomp,
  libcap_ng,
}:
let
  pname = "claude-desktop";
  version = "1.40609.0";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname version;

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
    hash = "sha256-qW6W/4601Nf/p4Wrp/wj+GhLEqyD7S70Bg8PCfQXepg=";
  };

  nativeBuildInputs = [
    binutils
    gnutar
    autoPatchelfHook
  ];

  buildInputs = [
    gtk3
    libnotify
    nspr
    nss
    atk
    at-spi2-atk
    at-spi2-core
    cups
    dbus
    cairo
    pango
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libgbm
    libdrm
    expat
    libxcb
    libxkbcommon
    libsecret
    systemd
    alsa-lib
    wayland
    libxshmfence
    zlib
    gcc.cc.lib
    libseccomp
    libcap_ng
  ];

  dontUnpack = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    ar p "$src" data.tar.xz | tar --no-same-owner --no-same-permissions -xJf - -C "$out"

    mkdir -p "$out/bin"
    ln -s "$out/usr/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop"

    substituteInPlace "$out/usr/share/applications/com.anthropic.Claude.desktop" \
      --replace-fail "Exec=claude-desktop" "Exec=$out/bin/claude-desktop"

    runHook postInstall
  '';

  passthru.tests.version = testers.testVersion {
    package = finalAttrs.finalPackage;
    command = "${finalAttrs.finalPackage}/bin/claude-desktop --version";
  };

  meta = with lib; {
    description = "Claude Desktop for Linux";
    homepage = "https://claude.com/download";
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
})

{
  autoPatchelfHook,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  copyDesktopItems,
  cups,
  dbus,
  expat,
  fetchurl,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  harfbuzz,
  lib,
  libGL,
  libdrm,
  libgbm,
  libnotify,
  libpulseaudio,
  libsecret,
  libxkbcommon,
  makeDesktopItem,
  makeWrapper,
  mesa,
  nspr,
  nss,
  pango,
  pciutils,
  pipewire,
  runtimeShell,
  stdenv,
  stdenvNoCC,
  systemd,
  vulkan-loader,
  wrapGAppsHook3,
  xdg-utils,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
}:
stdenvNoCC.mkDerivation rec {
  pname = "helium-bin";
  version = "0.14.2.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64_linux.tar.xz";
    hash = "sha256-Tx7XpzyLxd+KyIPuzMelkBnyiaLPau59nmvjH4C/ubA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
    wrapGAppsHook3
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    libGL
    libdrm
    libgbm
    libnotify
    libpulseaudio
    libsecret
    libxkbcommon
    mesa
    nspr
    nss
    pango
    pciutils
    pipewire
    stdenv.cc.cc.lib
    systemd
    vulkan-loader
    libx11
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
    libxcb
  ];

  sourceRoot = "helium-${version}-x86_64_linux";

  desktopItems = [
    (makeDesktopItem {
      name = "helium";
      desktopName = "Helium";
      genericName = "Web Browser";
      comment = "Access the Internet";
      exec = "helium %U";
      terminal = false;
      startupNotify = true;
      startupWMClass = "helium";
      categories = [
        "Network"
        "WebBrowser"
      ];
      mimeTypes = [
        "application/pdf"
        "application/rdf+xml"
        "application/rss+xml"
        "application/xhtml+xml"
        "application/xhtml_xml"
        "application/xml"
        "image/gif"
        "image/jpeg"
        "image/png"
        "image/webp"
        "text/html"
        "text/xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
      actions = {
        new-window = {
          name = "New Window";
          exec = "helium";
        };
        new-private-window = {
          name = "New Incognito Window";
          exec = "helium --incognito";
        };
      };
      icon = "helium";
    })
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/helium" "$out/bin"
    cp -r . "$out/lib/helium/"
    chmod -R u+w "$out/lib/helium"

    ln -s "$out/lib/helium/helium" "$out/bin/helium-unwrapped"

    install -Dm755 /dev/stdin "$out/bin/helium" <<'EOF'
    #!${runtimeShell}
    export CHROME_VERSION_EXTRA="NixOS"
    export CHROME_WRAPPER="$(readlink -f "$0")"
    HERE="${placeholder "out"}/lib/helium"
    export LD_LIBRARY_PATH="$HERE:$HERE/lib:$HERE/lib.target''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec "$HERE/helium" "$@"
    EOF

    for sizeDir in "$out"/lib/helium/product_logo_*; do
      if [ -d "$sizeDir" ]; then
        size="$(basename "$sizeDir" | cut -d_ -f3)"
        install -Dm644 "$sizeDir/helium.png" "$out/share/icons/hicolor/''${size}x''${size}/apps/helium.png"
      fi
    done

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/helium" \
      --prefix PATH : ${lib.makeBinPath [xdg-utils]} \
      --set-default HELIUM_WRAPPER "nix"
  '';

  meta = with lib; {
    description = "Private, fast, and honest browser based on Chromium";
    homepage = "https://helium.computer";
    license = with licenses; [gpl3Plus bsd3];
    sourceProvenance = with sourceTypes; [binaryNativeCode];
    maintainers = [];
    mainProgram = "helium";
    platforms = ["x86_64-linux"];
  };
}

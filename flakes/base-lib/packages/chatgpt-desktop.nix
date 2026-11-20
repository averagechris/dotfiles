{
  pkgs,
  lib,
  ...
}: let
  runtime = pkgs.buildFHSEnv {
    name = "chatgpt-runtime";
    targetPkgs = p:
      with p; [
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
        libGL
        libgbm
        libnotify
        libsecret
        libusb1
        libxkbcommon
        nspr
        nss
        openssl
        pango
        stdenv.cc.cc.lib
        systemd
        tpm2-tss
        vulkan-loader
        libx11
        libxcb
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxrandr
        xdg-utils
        bash
        coreutils
        gitMinimal
      ];
    runScript = pkgs.writeShellScript "chatgpt-launch" ''
      exec "''${XDG_DATA_HOME:-$HOME/.local/share}/chatgpt-desktop/current/usr/lib/chatgpt/ChatGPT" "$@"
    '';
  };
  update = pkgs.writeShellApplication {
    name = "chatgpt-update";
    runtimeInputs = [pkgs.curl pkgs.dpkg pkgs.coreutils pkgs.util-linux];
    text = ''
      base="''${XDG_DATA_HOME:-$HOME/.local/share}/chatgpt-desktop"
      mkdir -p "$base"
      exec 9>"$base/update.lock"
      flock 9
      stage=$(mktemp -d "$base/.update.XXXXXX")
      trap 'rm -rf "$stage"' EXIT
      curl --proto '=https' --tlsv1.2 -fL --retry 3 \
        https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb \
        -o "$stage/chatgpt.deb"
      version=$(dpkg-deb -f "$stage/chatgpt.deb" Version)
      if [ ! -d "$base/$version" ]; then
        mkdir "$stage/app"
        dpkg-deb -x "$stage/chatgpt.deb" "$stage/app"
        test -x "$stage/app/usr/lib/chatgpt/ChatGPT"
        mv "$stage/app" "$base/$version"
      fi
      ln -sfn "$version" "$base/current.next"
      mv -Tf "$base/current.next" "$base/current"
      install -Dm644 "$base/current/usr/share/pixmaps/chatgpt.png" \
        "''${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/chatgpt.png"
      echo "ChatGPT $version installed. Quit and reopen ChatGPT to use it."
    '';
  };
  launcher = pkgs.writeShellScriptBin "chatgpt" ''
    if [ ! -x "''${XDG_DATA_HOME:-$HOME/.local/share}/chatgpt-desktop/current/usr/lib/chatgpt/ChatGPT" ]; then
      ${update}/bin/chatgpt-update
    fi
    exec ${runtime}/bin/chatgpt-runtime "$@"
  '';
in
  pkgs.symlinkJoin {
    name = "chatgpt-desktop";
    paths = [
      launcher
      update
      (pkgs.makeDesktopItem {
        name = "chatgpt";
        desktopName = "ChatGPT";
        exec = "chatgpt %U";
        icon = "chatgpt";
        categories = ["Utility" "Development"];
        mimeTypes = ["x-scheme-handler/codex"];
      })
    ];
    meta = {
      description = "Official ChatGPT desktop app with an updatable user-local payload";
      mainProgram = "chatgpt";
      platforms = ["x86_64-linux"];
      license = lib.licenses.unfree;
    };
  }

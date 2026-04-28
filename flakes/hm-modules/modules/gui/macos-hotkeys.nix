{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.macosHotkeys;
  terminalPackage = config.dotfiles.gui.terminal.package;
  terminalAppName =
    if terminalPackage.pname == "ghostty"
    then "Ghostty"
    else if terminalPackage.pname == "wezterm"
    then "WezTerm"
    else terminalPackage.meta.mainProgram or terminalPackage.pname;
  focusTerminal = pkgs.writeShellApplication {
    name = "focus-dotfiles-terminal";
    runtimeInputs = [terminalPackage];
    text = ''
      osascript <<'APPLESCRIPT'
      set terminalAppName to "${terminalAppName}"
      set terminalCommand to "${config.dotfiles.gui.terminal.binPath}"

      tell application "System Events"
        set terminalIsRunning to exists process terminalAppName
      end tell

      if terminalIsRunning then
        tell application terminalAppName to activate
      else
        do shell script terminalCommand & " >/dev/null 2>&1 &"
      end if
      APPLESCRIPT
    '';
  };
  focusDefaultBrowser = pkgs.writeShellApplication {
    name = "focus-default-browser";
    text = ''
      osascript <<'APPLESCRIPT'
      set browserCandidates to {"Safari", "Google Chrome", "Firefox", "Firefox Developer Edition", "Helium", "Arc", "Brave Browser", "Microsoft Edge"}

      tell application "System Events"
        set runningBrowsers to name of processes whose name is in browserCandidates
      end tell

      if (count of runningBrowsers) > 0 then
        tell application (item 1 of runningBrowsers) to activate
      else
        do shell script "open about:blank"
      end if
      APPLESCRIPT
    '';
  };
  skhdConfig = pkgs.writeText "skhdrc" ''
    # Focus or launch the dotfiles-selected terminal.
    cmd + alt - t : ${focusTerminal}/bin/focus-dotfiles-terminal

    # Focus a running browser, or open the default browser if none is running.
    cmd + alt - b : ${focusDefaultBrowser}/bin/focus-default-browser

    # Screenshot selected region directly to the clipboard.
    cmd + alt - s : /usr/sbin/screencapture -ic

    # Logi-friendly tab navigation aliases. These emit the common macOS
    # previous/next tab shortcuts after skhd captures the ergonomic aliases.
    cmd + alt - 0x21 : /usr/bin/osascript -e 'tell application "System Events" to key code 33 using {command down, shift down}'
    cmd + alt - 0x1E : /usr/bin/osascript -e 'tell application "System Events" to key code 30 using {command down, shift down}'

    # Colemak-DH vertical navigation: N/E are analogous to QWERTY J/K.
    cmd + alt - n : /usr/bin/osascript -e 'tell application "System Events" to key code 126 using {control down}'
    cmd + alt - e : /usr/bin/osascript -e 'tell application "System Events" to key code 125 using {control down}'

    # Lock screen. This intentionally shadows the native Force Quit chord.
    cmd + alt - 0x35 : /System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend
  '';
in {
  options.dotfiles.macosHotkeys.enable = lib.mkEnableOption "macOS global hotkeys";

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.skhd focusTerminal focusDefaultBrowser];

    launchd.agents.skhd = {
      enable = true;
      config = {
        ProgramArguments = ["${pkgs.skhd}/bin/skhd" "-c" "${skhdConfig}"];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/skhd.log";
        StandardErrorPath = "/tmp/skhd.log";
      };
    };
  };
}

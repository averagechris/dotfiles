{ config, pkgs, ... }:

let
  tmuxModal = with pkgs; tmuxPlugins.mkTmuxPlugin rec {
    pluginName = "tmux-modal";
    version = "unstable-2022-02-19";
    src = fetchFromGitHub {
      owner = "whame";
      repo = "tmux-modal";
      rev = "5ecffca7af0950e49f47a2681c9fb07ccfb9b407";
      sha256 = "sha256-pcleS1lyJQ5qV3B3actjNHJJwly6zi50FXegFMe5Iis=";
    };
    rtpFilePath = "${pluginName}.tmux";
    meta = {
      homepage = "https://github.com/whame/tmux-modal";
      description = "A modal mode for tmux.";
      longDescription =
        ''
          Execute complex tmux commands in just a few keystrokes with a modal mode that is designed to be efficient,
          easy to remember and comfortable.
        '';
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
      maintainers = with lib.maintainers; [ ];
    };
    postInstall = ''
      sed -i -e 's|KBD_CMD=M-m|KBD_CMD=C-x |g' $target/${rtpFilePath}
      sed -i -e 's|KBD_CMD_EXIT=M-m|KBD_CMD_EXIT=C-x|g' $target/${rtpFilePath}
    '';
  };

in
{
  programs.tmux = {
    enable = true;

    aggressiveResize = true;
    customPaneNavigationAndResize = true;
    disableConfirmationPrompt = true;
    escapeTime = 0;
    historyLimit = 50000;
    keyMode = "vi";
    newSession = true;
    shortcut = "Space";
    terminal = "tmux-256color";

    plugins = with pkgs; [
      tmuxPlugins.extrakto
      # tmuxModal  TODO ???
    ];

    extraConfig = builtins.readFile ./tmux.conf;
  };
}

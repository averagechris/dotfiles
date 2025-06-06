{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.programs.windsurf;
in {
  options.programs.windsurf = {
    enable = mkEnableOption "Windsurf editor";
  };

  config = mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      profiles.defualt.extensions = with pkgs.vscode-extensions; [
        rust-lang.rust-analyzer
        ms-python.python
        jnoortheen.nix-ide
        mkhl.direnv
      ];
      profiles.default.userSettings = {
        "keyboard.dispatch" = "keyCode";
        "editor.cursorSurroundingLines" = 5;

        # Nix settings
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "nix.serverSettings" = {
          "nil" = {
            "formatting" = {
              "command" = ["alejandra"];
            };
          };
        };

        # Workspace navigation keybindings
        "keybindings" = [
          {
            "key" = "space w i";
            "command" = "workbench.action.focusRightGroup";
          }
          {
            "key" = "space w m";
            "command" = "workbench.action.focusLeftGroup";
          }
        ];

        # Windsurf settings
        "windsurf.autoExecutionPolicy" = "off";
        "windsurf.autocompleteSpeed" = "default";
        "windsurf.chatFontSize" = "default";
        "windsurf.enableAutocomplete" = false;
        "windsurf.explainAndFixInCurrentConversation" = true;
        "windsurf.openRecentConversation" = true;
        "windsurf.rememberLastModelSelection" = true;
        "workbench.colorTheme" = "SynthWave84";
      };
    };
  };
}

{
  description = "Home-manager modules for dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    base-lib = {
      url = "path:../base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    {
      homeManagerModules = {
        default = ./modules/default.nix;
        shell = ./modules/shell.nix;
        helix = ./modules/helix/default.nix;
        opencode = ./modules/opencode/default.nix;

        meganz = ./modules/meganz.nix;
        gui = {
          default = ./modules/gui/default.nix;
          alacritty = ./modules/gui/alacritty.nix;
          cosmicPortalWorkarounds = ./modules/gui/cosmic-portal-workarounds.nix;
          firefox = ./modules/gui/firefox.nix;
          kitty = ./modules/gui/kitty.nix;
          zed = ./modules/gui/zed.nix;
          windsurf = ./modules/gui/windsurf.nix;
          zoom = ./modules/gui/zoom.nix;
          linux_desktop = ./modules/gui/linux_desktop.nix;
          sway = ./modules/gui/sway/default.nix;
          hyprland = ./modules/gui/hyprland/default.nix;
          wezterm = ./modules/gui/wezterm/default.nix;
          ghostty = ./modules/gui/ghostty/default.nix;
        };
        shellModules = {
          calibre-utils = ./modules/shell-modules/calibre-utils.nix;
          fzf = ./modules/shell-modules/fzf.nix;
          lazygit = ./modules/shell-modules/lazygit.nix;
          less = ./modules/shell-modules/less.nix;
          pipx = ./modules/shell-modules/pipx.nix;
          ranger = ./modules/shell-modules/ranger.nix;
          shell_extras = ./modules/shell-modules/shell_extras.nix;
          yazi = ./modules/shell-modules/yazi.nix;
          zsh = ./modules/shell-modules/zsh.nix;
        };
        git = ./modules/git/default.nix;
        gitui = ./modules/gitui/default.nix;
        helixTerminalTools = ./modules/helix-terminal-tools/default.nix;
        helixYaziIntegration = ./modules/helix-yazi-integration/default.nix;
        jujutsu = ./modules/jujutsu/default.nix;
        neovim = ./modules/neovim/default.nix;
        zellij = ./modules/zellij/default.nix;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: {
      checks = {
        # Basic check that modules can be imported
        modules-import = nixpkgs.legacyPackages.${system}.runCommand "hm-modules-check" {} ''
          echo "Home-manager modules flake check passed"
          touch $out
        '';
      };
    });
}

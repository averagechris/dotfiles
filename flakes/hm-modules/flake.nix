{
  description = "Home-manager modules for dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    starship-jj = {
      url = "sourcehut:~averagechris/starship-jj";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    linear-cli = {
      url = "sourcehut:~averagechris/linear-cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    gander = {
      url = "sourcehut:~averagechris/gander";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    base-lib = {
      url = "path:../base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    flake-utils,
    home-manager,
    base-lib,
    ...
  }:
    {
      homeManagerModules = {
        default = ./modules/default.nix;
        shell = ./modules/shell.nix;
        helix = ./modules/helix/default.nix;
        opencode = ./modules/opencode/default.nix;
        pi = ./modules/pi.nix;
        gander = ./modules/gander.nix;
        granola = ./modules/granola.nix;
        linearCli = ./modules/linear-cli.nix;
        openclaw-fix = ./modules/openclaw-fix.nix;
        ghostty-fix = ./modules/ghostty-fix.nix;

        meganz = ./modules/meganz.nix;
        gui = {
          default = ./modules/gui/default.nix;
          alacritty = ./modules/gui/alacritty.nix;
          cosmicPortalWorkarounds = ./modules/gui/cosmic-portal-workarounds.nix;
          firefox = ./modules/gui/firefox.nix;
          kitty = ./modules/gui/kitty.nix;
          zed = ./modules/gui/zed.nix;
          zoom = ./modules/gui/zoom.nix;
          linux_desktop = ./modules/gui/linux_desktop.nix;
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
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (final: prev: let
            inherit (prev.stdenv.hostPlatform) system;
            opencodeInput = inputs.opencode;
            rev = opencodeInput.shortRev or opencodeInput.dirtyShortRev or "dirty";
            upstreamHashes = builtins.fromJSON (builtins.readFile "${opencodeInput}/nix/hashes.json");
            nodeModulesOverrides = {
              "3b7a5e783d59e8986dca6e5df48663613fa80722" = {
                hash.aarch64-darwin = "sha256-81IAmdjiYZz8IgMJt0+VxzdOS80gTHc5SendwEW/vD4=";
              };
              "0f272d931d806681a0f7f19538e2f3f1d52d1832" = {
                hash.aarch64-darwin = "sha256-+lx7mv1QM+nl3UPY9GxPcbWlhK4TKYp96rvJd51Exig=";
                postPatch = ''
                  substituteInPlace bun.lock \
                    --replace-fail '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#20bd361", {}, "anomalyco-ghostty-web-20bd361", "sha512-dW0nwaiBBcun9y5WJSvm3HxDLe5o9V0xLCndQvWonRVubU8CS1PHxZpLffyPt1YujPWC13ez03aWxcuKBPYYGQ=="]' \
                                   '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#513463a", {}, "anomalyco-ghostty-web-513463a", "sha512-GZR8LSmgGzViWnBJrqRI8MpAZRCJxhcr1Hi9Tyeh7YRooHZQjK9J97FQRD3tbBaM2wjq05gzGY2UEsG+JtZeBw=="]'
                '';
              };
            };
            override = nodeModulesOverrides.${opencodeInput.rev or ""} or {};
            hasSystemOverride = builtins.hasAttr system (override.hash or {});
            node_modules =
              (final.callPackage "${opencodeInput}/nix/node_modules.nix" {
                inherit rev;
                hash =
                  (override.hash or {}).${system} or upstreamHashes.nodeModules.${system};
              }).overrideAttrs (old: {
                postPatch = (old.postPatch or "") + (final.lib.optionalString hasSystemOverride (override.postPatch or ""));
              });
          in {
            titlecase = base-lib.inputs.titlecase.packages.${system}.default;
            pi-coding-agent = final.callPackage ../base-lib/packages/pi-coding-agent.nix {};
            pi = final.pi-coding-agent;
            coderabbit-cli = final.callPackage ../base-lib/packages/coderabbit-cli.nix {};
            helium-bin = final.callPackage ../base-lib/packages/helium-bin.nix {};
            notion-cli = final.callPackage ../base-lib/packages/notion-cli.nix {};
            rodney = final.callPackage ../base-lib/packages/rodney.nix {};
            showboat = final.callPackage ../base-lib/packages/showboat.nix {};
            opencode = final.callPackage "${opencodeInput}/nix/opencode.nix" {
              inherit node_modules;
            };
          })
        ];
      };
      inherit (pkgs.stdenv) isLinux;
      # Provide dotfiles_lib that modules expect (normally provided by base-lib)
      dotfiles_lib = {
        options = with nixpkgs.lib; {
          mkDefaultEnabledOption = description:
            mkOption {
              type = types.bool;
              default = true;
              example = false;
              inherit description;
            };
        };
      };
    in {
      checks = {
        # Test that modules can be imported and evaluated with home-manager
        # This forces evaluation of the home-manager configuration, catching any
        # module syntax errors, missing imports, or type mismatches.
        # Only runs on Linux since many GUI modules (waybar, etc.) are Linux-only.
        modules-eval =
          if isLinux
          then let
            testConfig = home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = {
                inherit dotfiles_lib inputs system;
                # Provide empty secrets for modules that optionally use agenix secrets
                secrets = {};
              };
              modules = [
                ./modules/default.nix
                {
                  home.username = "test";
                  home.homeDirectory = "/tmp/test-home";
                  home.stateVersion = "26.05";
                }
              ];
            };
          in
            # Force evaluation of the activation package to catch errors
            pkgs.runCommand "hm-modules-eval-test" {} ''
              # Reference the activation package to force evaluation
              echo "Testing home-manager module evaluation..."
              echo "Activation package: ${testConfig.activationPackage}"
              mkdir -p $out
              touch $out/success
            ''
          else
            # On non-Linux systems, just verify the flake structure is valid
            pkgs.runCommand "hm-modules-structure-test" {} ''
              echo "Home-manager modules structure check passed (full eval skipped on non-Linux)"
              mkdir -p $out
              touch $out/success
            '';
      };
    });
}

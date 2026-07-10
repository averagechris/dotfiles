{
  description = "Home-manager modules for dotfiles";

  inputs = {
    base-lib.url = "path:../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    flake-utils.follows = "base-lib/flake-utils";
    home-manager.follows = "base-lib/home-manager";
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    starship-jj = {
      url = "sourcehut:~averagechris/starship-jj";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.systems.follows = "flake-utils/systems";
    };
    linear-cli = {
      url = "sourcehut:~averagechris/linear-cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    srht = {
      url = "sourcehut:~averagechris/srht";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gander = {
      url = "sourcehut:~averagechris/gander";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sideshow = {
      url = "sourcehut:~averagechris/sideshow";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rdny = {
      url = "sourcehut:~averagechris/rdny";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.srht.follows = "srht";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
    };
    nitter-link = {
      url = "git+https://git.sr.ht/~averagechris/nitter-link?ref=refs/tags/v0.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
    };
    opencode.follows = "base-lib/opencode";
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
        ctx = ./modules/ctx.nix;
        gander = ./modules/gander.nix;
        granola = ./modules/granola.nix;
        rdny = ./modules/rdny.nix;
        sideshow = ./modules/sideshow.nix;
        linearCli = ./modules/linear-cli;
        srht = ./modules/srht.nix;
        nitterLink = ./modules/nitter-link.nix;
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
            helium-bin = final.callPackage ../base-lib/packages/helium-bin.nix {};
            nitter-link-chrome-extension = inputs.nitter-link.packages.${system}.chrome-extension;
            nitter-link-firefox-extension = inputs.nitter-link.packages.${system}.firefox-extension;
            notion-cli = final.callPackage ../base-lib/packages/notion-cli.nix {};
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
                sshKeys = inputs.base-lib.sshKeys;
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

        nitter-link-stable-path = let
          fakeExtensionV1 = pkgs.runCommand "fake-nitter-link-package-v1" {} ''
            mkdir -p $out/share/nitter-link/chrome $out/share/nitter-link/firefox
            printf '{"manifest_version":3,"name":"nitter-link","version":"0.0.1"}\n' > $out/share/nitter-link/chrome/manifest.json
            printf '{"manifest_version":2,"name":"nitter-link","version":"0.0.1","browser_specific_settings":{"gecko":{"id":"nitter-link@averagechris"}}}\n' > $out/share/nitter-link/firefox/manifest.json
          '';
          fakeExtensionV2 = pkgs.runCommand "fake-nitter-link-package-v2" {} ''
            mkdir -p $out/share/nitter-link/chrome $out/share/nitter-link/firefox
            printf '{"manifest_version":3,"name":"nitter-link","version":"0.0.2"}\n' > $out/share/nitter-link/chrome/manifest.json
            printf '{"manifest_version":2,"name":"nitter-link","version":"0.0.2","browser_specific_settings":{"gecko":{"id":"nitter-link@averagechris"}}}\n' > $out/share/nitter-link/firefox/manifest.json
          '';
          mkTestConfig = extensionPackage:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = {
                inherit dotfiles_lib inputs system;
                sshKeys = inputs.base-lib.sshKeys;
                secrets = {};
              };
              modules = [
                ./modules/nitter-link.nix
                {
                  home.username = "test";
                  home.homeDirectory = "/tmp/test-home";
                  home.stateVersion = "26.05";
                  programs.nitter-link = {
                    enable = true;
                    chromiumBrowsers.helium = {
                      enable = true;
                      inherit extensionPackage;
                      stablePath = "/tmp/test-home/.config/net.imput.helium/nitter-link";
                    };
                    firefoxBrowsers.zen = {
                      enable = true;
                      inherit extensionPackage;
                      temporaryManual = {
                        enable = true;
                        stablePath = "/tmp/test-home/.config/zen/nitter-link-temporary";
                      };
                    };
                  };
                }
              ];
            };
          configV1 = mkTestConfig fakeExtensionV1;
          configV2 = mkTestConfig fakeExtensionV2;
          chromeKey = "net.imput.helium/nitter-link";
          zenKey = "zen/nitter-link-temporary";
          chromeSourceV1 = configV1.config.xdg.configFile.${chromeKey}.source;
          chromeSourceV2 = configV2.config.xdg.configFile.${chromeKey}.source;
          zenSourceV1 = configV1.config.xdg.configFile.${zenKey}.source;
          zenSourceV2 = configV2.config.xdg.configFile.${zenKey}.source;
        in
          pkgs.runCommand "nitter-link-stable-path-test" {} ''
            test "${chromeSourceV1}" = "${fakeExtensionV1}/share/nitter-link/chrome"
            test "${chromeSourceV2}" = "${fakeExtensionV2}/share/nitter-link/chrome"
            test "${zenSourceV1}" = "${fakeExtensionV1}/share/nitter-link/firefox"
            test "${zenSourceV2}" = "${fakeExtensionV2}/share/nitter-link/firefox"
            test -f "${chromeSourceV1}/manifest.json"
            test -f "${chromeSourceV2}/manifest.json"
            test -f "${zenSourceV1}/manifest.json"
            test -f "${zenSourceV2}/manifest.json"
            touch $out
          '';
      };
    });
}

{
  config,
  lib,
  pkgs,
  inputs ? {},
  system ? pkgs.stdenv.hostPlatform.system,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.programs.nitter-link;
  defaultChromePackage =
    if inputs ? nitter-link && inputs.nitter-link ? packages && builtins.hasAttr system inputs.nitter-link.packages
    then inputs.nitter-link.packages.${system}.chrome-extension
    else pkgs.nitter-link-chrome-extension;
  defaultFirefoxPackage =
    if inputs ? nitter-link && inputs.nitter-link ? packages && builtins.hasAttr system inputs.nitter-link.packages
    then inputs.nitter-link.packages.${system}.firefox-extension
    else pkgs.nitter-link-firefox-extension;
  underConfigHome = path: lib.hasPrefix "${config.xdg.configHome}/" path;
  chromiumBrowser = types.submodule ({
    name,
    config,
    ...
  }: {
    options = {
      enable = mkEnableOption "nitter-link for ${name}";
      extensionPackage = mkOption {
        type = types.package;
        default = defaultChromePackage;
        defaultText = lib.literalExpression "inputs.nitter-link.packages.${pkgs.stdenv.hostPlatform.system}.chrome-extension";
        description = "Built nitter-link package containing share/nitter-link/chrome.";
      };
      extensionPath = mkOption {
        type = types.path;
        default = "${config.extensionPackage}/share/nitter-link/chrome";
        defaultText = lib.literalExpression ''"\${config.extensionPackage}/share/nitter-link/chrome"'';
        description = "Unpacked Chromium extension directory containing manifest.json.";
      };
      stablePath = mkOption {
        type = types.str;
        description = "Stable Home Manager managed path used by the browser to load the unpacked extension.";
      };
    };
  });
  firefoxBrowser = types.submodule ({
    name,
    config,
    ...
  }: {
    options = {
      enable = mkEnableOption "nitter-link for ${name}";
      extensionPackage = mkOption {
        type = types.package;
        default = defaultFirefoxPackage;
        defaultText = lib.literalExpression "inputs.nitter-link.packages.${pkgs.stdenv.hostPlatform.system}.firefox-extension";
        description = "Built nitter-link package containing share/nitter-link/firefox and archives.";
      };
      temporaryManual = {
        enable = mkEnableOption "a stable unpacked temporary-add-on path for manual about:debugging loading";
        stablePath = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Stable Home Manager managed path exposing the unpacked Firefox tree for manual temporary loading.";
        };
        extensionPath = mkOption {
          type = types.path;
          default = "${config.extensionPackage}/share/nitter-link/firefox";
          defaultText = lib.literalExpression ''"\${config.extensionPackage}/share/nitter-link/firefox"'';
          description = "Unpacked Firefox extension directory containing manifest.json and the upstream Gecko extension ID.";
        };
      };
    };
  });
  enabledChromium = lib.filterAttrs (_: browser: browser.enable) cfg.chromiumBrowsers;
  enabledFirefox = lib.filterAttrs (_: browser: browser.enable) cfg.firefoxBrowsers;
  chromiumFiles = lib.mapAttrs' (_: browser:
    lib.nameValuePair (lib.removePrefix "${config.xdg.configHome}/" browser.stablePath) {
      source = browser.extensionPath;
      recursive = true;
    })
  enabledChromium;
  firefoxFiles = lib.mapAttrs' (_: browser:
    lib.nameValuePair (lib.removePrefix "${config.xdg.configHome}/" browser.temporaryManual.stablePath) {
      source = browser.temporaryManual.extensionPath;
      recursive = true;
    })
  (lib.filterAttrs (_: browser: browser.temporaryManual.enable) enabledFirefox);
in {
  options.programs.nitter-link = {
    enable = mkEnableOption "stable browser integration for nitter-link";
    chromiumBrowsers = mkOption {
      type = types.attrsOf chromiumBrowser;
      default = {};
      description = "Chromium-family browsers that should receive a stable unpacked-extension symlink.";
    };
    firefoxBrowsers = mkOption {
      type = types.attrsOf firefoxBrowser;
      default = {};
      description = "Firefox-family browsers. This module does not mutate profiles or extension databases.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (browser: underConfigHome browser.stablePath) (lib.attrValues enabledChromium);
        message = "programs.nitter-link chromium stablePath values must live under xdg.configHome so Home Manager can manage stable symlinks.";
      }
      {
        assertion = lib.all (browser: ! browser.temporaryManual.enable || browser.temporaryManual.stablePath != null) (lib.attrValues enabledFirefox);
        message = "programs.nitter-link firefox temporaryManual.enable requires temporaryManual.stablePath.";
      }
      {
        assertion = lib.all (browser: ! browser.temporaryManual.enable || underConfigHome browser.temporaryManual.stablePath) (lib.attrValues enabledFirefox);
        message = "programs.nitter-link firefox temporaryManual.stablePath values must live under xdg.configHome so Home Manager can manage stable symlinks.";
      }
    ];

    xdg.configFile = chromiumFiles // firefoxFiles;
  };
}

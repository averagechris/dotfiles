{
  inputs,
  lib,
  overlays,
  pkgs,
  sshKeys,
  ...
}: let
  weztermPackage =
    pkgs.runCommand "${pkgs.wezterm.name}-without-compiler-references" {
      inherit (pkgs.wezterm) meta passthru;
      nativeBuildInputs = [pkgs.removeReferencesTo];
    } ''
      mkdir -p "$out"
      cp -R --no-preserve=ownership ${pkgs.wezterm}/. "$out"
      chmod -R u+w "$out"

      for bin in \
        "$out/Applications/WezTerm.app/Contents/MacOS/wezterm" \
        "$out/Applications/WezTerm.app/Contents/MacOS/wezterm-gui" \
        "$out/Applications/WezTerm.app/Contents/MacOS/wezterm-mux-server"; do
        remove-references-to -t ${pkgs.stdenv.cc} "$bin"
      done
    '';
in {
  imports = [
    inputs.darwin-modules.darwinModules.colemak-dh
    inputs.darwin-modules.darwinModules.custom-sshd
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = lib.attrValues overlays;

  nix = {
    enable = false; # Determinate Nix manages the daemon on this Mac.
    package = pkgs.nixVersions.stable;
    extraOptions = ''experimental-features = nix-command flakes'';
    gc.automatic = false;
    settings.require-sigs = true;
    settings.extra-nix-path = "nixpkgs=flake:nixpkgs";
  };

  networking = {
    computerName = "taro";
    hostName = "taro";
    localHostName = "taro";
    applicationFirewall = {
      enable = true;
      allowSigned = true;
      allowSignedApp = true;
      enableStealthMode = true;
    };
  };

  programs = {
    nix-index.enable = true;
    zsh.enable = true;
  };

  dotfiles.colemakDh.enable = true;
  dotfiles.customSshd = {
    enable = true;
    port = 2222;
  };

  environment.systemPackages = with pkgs; [
    gitMinimal
    nh
    neovim
    nix-output-monitor
    which
  ];

  system = {
    defaults.NSGlobalDomain = {
      AppleEnableSwipeNavigateWithScrolls = true;
      AppleFontSmoothing = 2;
      AppleInterfaceStyle = null;
      AppleInterfaceStyleSwitchesAutomatically = true;
      AppleKeyboardUIMode = 3;
      AppleMeasurementUnits = "Inches";
      AppleMetricUnits = 0;
      ApplePressAndHoldEnabled = true;
      AppleShowAllExtensions = true;
      AppleShowAllFiles = false;
      AppleShowScrollBars = "Automatic";
      AppleTemperatureUnit = "Fahrenheit";
      InitialKeyRepeat = 10;
      KeyRepeat = 3;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticWindowAnimationsEnabled = true;
      NSDisableAutomaticTermination = false;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      NSScrollAnimationEnabled = true;
      NSTextShowsControlCharacters = false;
      NSUseAnimatedFocusRing = true;
      NSWindowResizeTime = 0.05;
      _HIHideMenuBar = false;
      "com.apple.keyboard.fnState" = false;
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.sound.beep.feedback" = 0;
      "com.apple.sound.beep.volume" = 0.472367;
      "com.apple.swipescrolldirection" = true;
      "com.apple.trackpad.enableSecondaryClick" = true;
      "com.apple.trackpad.scaling" = 1.0;
      "com.apple.trackpad.trackpadCornerClickBehavior" = null;
    };
    defaults.dock = {
      enable-spring-load-actions-on-all-items = false;
      autohide = true;
      autohide-delay = 0.15;
      autohide-time-modifier = 0.5;
      dashboard-in-overlay = false;
      expose-animation-duration = 0.75;
      expose-group-apps = true;
      launchanim = false;
      mineffect = "genie";
      minimize-to-application = true;
      mouse-over-hilite-stack = true;
      mru-spaces = false;
      orientation = "left";
      show-process-indicators = true;
      show-recents = false;
      showhidden = false;
      static-only = false;
      tilesize = 48;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
    };
    defaults.finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = false;
      CreateDesktop = false;
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
    };
    defaults.loginwindow = {
      DisableConsoleAccess = true;
      GuestEnabled = false;
      PowerOffDisabledWhileLoggedIn = false;
      RestartDisabled = false;
      RestartDisabledWhileLoggedIn = false;
      SHOWFULLNAME = false;
      ShutDownDisabled = false;
      ShutDownDisabledWhileLoggedIn = false;
      SleepDisabled = false;
      autoLoginUser = null;
    };
    defaults.screencapture = {
      disable-shadow = true;
      location = "~/screenshots/";
      type = "jpg";
    };
    defaults.spaces.spans-displays = false;
    defaults.CustomSystemPreferences."/Library/Preferences/com.apple.timezone.auto" = {
      Active = true;
    };
    defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
      "79" = {
        enabled = true;
        value = {
          type = "standard";
          parameters = [65535 123 262144];
        };
      };
      "81" = {
        enabled = true;
        value = {
          type = "standard";
          parameters = [65535 124 262144];
        };
      };
    };
    defaults.trackpad = {
      ActuationStrength = 1;
      Clicking = true;
      Dragging = false;
      FirstClickThreshold = 1;
      SecondClickThreshold = 1;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = false;
      remapCapsLockToEscape = true;
      swapLeftCommandAndLeftAlt = false;
    };
    primaryUser = "chris";
    stateVersion = 4;
  };

  users.groups.wheel.members = ["chris"];
  users.users.chris = {
    name = "chris";
    home = "/Users/chris";
    openssh.authorizedKeys.keys = [
      sshKeys.chris.thelio
      sshKeys.system.tater
    ];
  };

  services.openssh.enable = false;

  system.activationScripts.extraActivation.text = lib.mkAfter ''
    /usr/bin/pmset -c sleep 0
    /usr/sbin/systemsetup -setusingnetworktime on >/dev/null 2>&1 || true
  '';

  time.timeZone = null;

  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "26.05";
    imports = [inputs.hm-modules.homeManagerModules.default];

    dotfiles.shell = {
      enable = true;
      shell_scripts.enable = false;
      pipx.enable = false;
      gpg.enable = false;
    };
    dotfiles.gpg.enable = false;
    dotfiles.gui.enable = true;
    programs.signal.enable = false;
    dotfiles.gui.terminal = {
      package = lib.mkDefault weztermPackage;
      args = lib.mkDefault [];
      binPath = lib.mkDefault "${weztermPackage}/bin/wezterm";
    };
    dotfiles.wezterm.enable = true;
    programs.wezterm.package = weztermPackage;
    dotfiles.gander.enable = true;
    dotfiles.devCache = {
      enable = true;
      cargoSweep.roots = [
        "/Users/chris/projects"
        "/Users/chris/contrib"
      ];
    };

    programs.git = {
      settings = {
        user.name = "Chris Cummings";
        user.email = "chris@thesogu.com";
      };
      signing.signByDefault = false;
    };
    dotfiles.jujutsu = {
      prWorkflow.enable = true;
      workspaces.projectGroups = [
        {
          path = "~/projects";
          githubOwners = ["averagechris"];
        }
        {
          path = "~/contrib";
          githubOwners = ["*"];
        }
      ];
    };
    programs.jujutsu.settings = {
      # The shared module supplies a work-specific identity scope; clear it here.
      scope = lib.mkForce [];
      user = {
        name = "Chris Cummings";
        email = "chris@thesogu.com";
      };
      signing = lib.mkForce {
        behavior = "drop";
        backend = "none";
      };
    };

    dotfiles.agentSkills.databricks-cli.enable = false;
    dotfiles.agentSkills.linear-admin.enable = false;
    dotfiles.codex.enable = true;
    programs.opencode.enable = true;
    programs.pi.enable = true;
    dotfiles.agentSkills.memo.source = inputs.memo + "/skills/memo";
    dotfiles.opencode.agentTools = with pkgs; [
      {
        package = nh;
        name = "nh";
        description = "build and activate NixOS, Darwin, and Home Manager configurations";
      }
      {
        package = nix-output-monitor;
        name = "nom";
        description = "monitor Nix build progress and logs";
      }
      {
        package = inputs.memo.packages.${pkgs.stdenv.hostPlatform.system}.memo;
        name = "memo";
        description = "store and retrieve lasting decisions and workflow context";
      }
      {
        package = gh;
        name = "gh";
        description = "inspect and manage GitHub issues, pull requests, and CI";
      }
    ];
  };
}

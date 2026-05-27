{
  config,
  pkgs,
  inputs,
  lib,
  overlays,
  ...
}: {
  age.identityPaths = ["/Users/chris/.ssh/id_ed25519" "/Users/chris/.ssh/id_rsa"];

  age.secrets = {
    circleci-token = {
      file = ../../../secrets/circleci-token.age;
      owner = "chris";
      mode = "0400";
    };

    gpg-private-key = {
      file = ../../../secrets/gpg-private-key.age;
      owner = "chris";
      mode = "0400";
    };

    gpg-key-id = {
      file = ../../../secrets/gpg-key-id.age;
      owner = "chris";
      mode = "0400";
    };
  };

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    git
    nh
    neovim
    nix-output-monitor
    which
  ];

  nixpkgs.config.allowUnsupportedSystem = true;
  nixpkgs.overlays = lib.attrValues overlays;
  nix = {
    enable = false; # must be false with determinate nix trying that out :shrug:
    package = pkgs.nixVersions.stable;
    /*
    With Determinate Nix on macOS, nix-daemon ignores these client-provided
    settings. Configure substituters/keys via Determinate Nix instead using:
      nixpkgs/scripts/setup-darwin-determinate-nix.sh

    If not using Determinate Nix, uncomment the following and set nix.enable = true
    so nix-darwin manages /etc/nix/nix.conf.

    settings.substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://averagechris-dotfiles.cachix.org"
      "https://devenv.cachix.org"
      "https://helix.cachix.org"
    ];
    settings.trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "averagechris-dotfiles.cachix.org-1:VwJkl5dG1+xGDY5x884mH/kVwwpgwBAdBKIF3BZiia4="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
    ];
    settings.trusted-users = ["@wheel" "chris"];
    */
    extraOptions = ''experimental-features = nix-command flakes'';
    gc.automatic = false;
    settings.require-sigs = true;
    settings.extra-nix-path = "nixpkgs=flake:nixpkgs";
  };

  networking = let
    n = "suremac";
  in {
    computerName = n;
    hostName = n;
    localHostName = n;
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

  system = {
    defaults.NSGlobalDomain = {
      AppleEnableSwipeNavigateWithScrolls = true;
      AppleFontSmoothing = 2;
      AppleInterfaceStyle = null; # could be "Dark" for all the time dark mode
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
      "com.apple.mouse.tapBehavior" = 1; # tap to click
      "com.apple.sound.beep.feedback" = 0;
      "com.apple.sound.beep.volume" = 0.472367; # 25%
      "com.apple.swipescrolldirection" = true; # natural scroll direction
      "com.apple.trackpad.enableSecondaryClick" = true;
      "com.apple.trackpad.scaling" = 1.0;
      "com.apple.trackpad.trackpadCornerClickBehavior" = null;
    };
    defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
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
      wvous-bl-corner = 1; # disable hot corners
      wvous-br-corner = 1; # disable hot corners
      wvous-tl-corner = 1; # disable hot corners
      wvous-tr-corner = 1; # disable hot corners
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
    defaults.spaces = {
      spans-displays = false;
    };
    defaults.CustomSystemPreferences."/Library/Preferences/com.apple.timezone.auto" = {
      Active = true;
    };
    defaults.CustomUserPreferences."com.apple.symbolichotkeys" = {
      AppleSymbolicHotKeys = {
        # Mission Control: move left/right a Space. Keep these enabled so
        # keyboard-synthesizing tools like Logi Options can use stable arrow
        # shortcuts instead of layout-sensitive letter shortcuts.
        "79" = {
          enabled = true;
          value = {
            type = "standard";
            parameters = [65535 123 262144]; # Control + Left Arrow
          };
        };
        "81" = {
          enabled = true;
          value = {
            type = "standard";
            parameters = [65535 124 262144]; # Control + Right Arrow
          };
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
  };
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "26.05";
    imports = [
      inputs.hm-modules.homeManagerModules.default
      inputs.mac-app-util.homeManagerModules.default
      ./aws.nix
    ];
    targets.darwin.copyApps.enableChecks = false;
    dotfiles.shell = {
      enable = true;
      shell_scripts.enable = false;
      pipx.enable = false;
      gpg.enable = true;
    };
    dotfiles.gui.enable = true;
    dotfiles.wezterm.enable = true;
    dotfiles.macosHotkeys.enable = true;
    dotfiles.gui.terminal = {
      package = lib.mkDefault pkgs.wezterm;
      args = lib.mkDefault [];
      binPath = lib.mkDefault "${pkgs.wezterm}/bin/wezterm";
    };
    programs.git.settings = {
      user.name = "Chris Cummings";
      user.email = "chris.cummings@sureapp.com";
    };
    programs.git.signing.signByDefault = true;
    dotfiles.jujutsu.workspaces.projectGroups = [
      {path = "~/projects";}
      {path = "~/sureapp";}
    ];
    programs.jujutsu.settings.scope = [
      {
        paths = ["~/sureapp/**"];
        user = {
          name = "Chris Cummings";
          email = "chris.cummings@sureapp.com";
        };
      }
    ];
    programs.opencode.enable = true;
    programs.pi.enable = true;
    dotfiles.opencode.circleciTokenFile = "/run/agenix/circleci-token";
    dotfiles.opencode.agentSupportPackages = with pkgs; [
      python313Packages.databricks-sql-connector
    ];
    dotfiles.opencode.agentTools = with pkgs; [
      {
        package = circleci-cli;
        name = "circleci";
        description = "CircleCI CLI";
      }
      {
        package = databricks-cli;
        name = "databricks-cli";
      }
      {
        package = gh;
        name = "gh";
        description = "GitHub CLI";
      }
      {
        package = pkgs.rodney;
        name = "rodney";
        description = "Chrome automation CLI";
      }
      {
        package = pkgs.showboat;
        name = "showboat";
        description = "work documentation CLI";
      }
      {
        package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear;
        name = "linear";
        description = "Linear CLI";
      }
    ];

    # programs.firefox.package = pkgs.firefox-devedition-bin;
    programs.firefox.enable = false;
    programs.zoom.enable = false;
    programs.darktable.enable = false;
    programs.signal.enable = false;
    programs.waybar.enable = false;
  };

  fonts.packages = [pkgs.nerd-fonts.droid-sans-mono];
  programs.gnupg.agent.enable = true;

  launchd.user.agents.nix-gc = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 14d"
      ];
      StartCalendarInterval = [
        {
          Weekday = 1; # Monday
          Hour = 12;
          Minute = 0;
        }
        {
          Weekday = 2; # Tuesday
          Hour = 12;
          Minute = 0;
        }
        {
          Weekday = 3; # Wednesday
          Hour = 12;
          Minute = 0;
        }
        {
          Weekday = 4; # Thursday
          Hour = 12;
          Minute = 0;
        }
        {
          Weekday = 5; # Friday
          Hour = 12;
          Minute = 0;
        }
      ];
      StandardOutPath = "/tmp/nix-gc.log";
      StandardErrorPath = "/tmp/nix-gc.log";
    };
  };

  system.activationScripts.locationAwareTime.text = ''
    echo "configuring location-aware time..." >&2
    systemsetup -setusingnetworktime on >/dev/null 2>&1 || true
  '';

  homebrew = {
    enable = false;
    casks = [
      "firefox-developer-edition"
    ];
    taps = [
      "homebrew/cask-versions"
    ];
  };

  # Let macOS set the timezone from the current network-derived location instead
  # of pinning this laptop to one coast in the declarative config.
  time.timeZone = null;
}

{
  pkgs,
  inputs,
  lib,
  overlays,
  ...
}: {
  imports = [
    ../karabiner-elements.nix
  ];
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    git
    nix-prefetch-scripts
    neovim
    which
  ];

  nixpkgs.config.allowUnsupportedSystem = true;
  nixpkgs.config.allowBroken = true;
  nixpkgs.overlays = lib.attrValues overlays;
  nix = {
    enable = false; # must be false with determinate nix trying that out :shrug:
    package = pkgs.nixVersions.stable;
    settings.substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://averagechris-dotfiles.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
      "https://devenv.cachix.org"
    ];
    settings.trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "averagechris-dotfiles.cachix.org-1:VwJkl5dG1+xGDY5x884mH/kVwwpgwBAdBKIF3BZiia4="
    ];
    settings.trusted-users = ["@wheel" "chris"];
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
  };

  programs = {
    nix-index.enable = true;
    zsh.enable = true;
  };

  programs.karabiner-elements = {
    enable = false;
    hyper.enable = true;
    modes = {
      colemak_mod_dh.bind = {
        e.to = "f";
        r.to = "p";
        t.to = "b";
        y.to = "j";
        u.to = "l";
        i.to = "u";
        o.to = "y";
        p.to = "semicolon";
        s.to = "r";
        d.to = "s";
        f.to = "t";
        h.to = "m";
        j.to = "n";
        k.to = "e";
        l.to = "i";
        semicolon.to = "o";
        z.to = "x";
        x.to = "c";
        c.to = "d";
        b.to = "z";
        n.to = "k";
        m.to = "h";
      };
      #   navigation_colemak_dh.bind = {
      #   };
      home_row_modifiers_colemak_dh.bind = {
        a.if_held = "left_option";
        r.if_held = "left_command";
        s.if_held = "left_control";
        t.if_held = "left_shift";
        o.if_held = "right_option";
        i.if_held = "right_command";
        e.if_held = "right_control";
        n.if_held = "right_shift";
      };
    };
    layers = {
      "space+command" = {
        unique_name = "space_namespace";
        layer = {
          space.open = "Raycast.app";
          r = {
            unique_name = "raycast_extensions";
            layer = {
              a.raycast = "extensions/raycast/raycast-ai/ai-chat";
              A.raycast = "extensions/raycast/raycast-ai/send-to-ai-chat";
              e.raycast = "extensions/raycast/emoji-symbols/search-emoji-symbols";
              n.raycast = "extensions/raycast/floating-notes/toggle-floating-notes-window";
              N.raycast = "extensions/raycast/floating-notes/toggle-floating-notes-focus";
              p.raycast = "extensions/raycast/clipboard-history/clipboard-history";
              c.raycast = "extensions/raycast/raycast/confetti";
            };
          };
          o = {
            unique_name = "open_applications";
            layer = {
              t.open = "Alacritty.app";
              # f.open = "Firefox Developer Edition.app";
              n.open = "Notion.app";
            };
          };
          w = {
            unique_name = "window_management";
            layer = {
              c.raycast = "extensions/raycast/window-management/reasonable-size";
              f.raycast = "extensions/raycast/window-management/almost-maximize";
              F.raycast = "extensions/raycast/window-management/toggle-fullscreen";
              m.raycast = "extensions/raycast/window-management/left-half";
              M.raycast = "extensions/raycast/window-management/first-three-fourths";
              i.raycast = "extensions/raycast/window-management/right-half";
              I.raycast = "extensions/raycast/window-management/last-three-fourths";
              "i+command".raycast = "extensions/raycast/window-management/first-fourth";
              "m+command".raycast = "extensions/raycast/window-management/last-fourth";
              e.raycast = "extensions/raycast/window-management/top-half";
              n.raycast = "extensions/raycast/window-management/bottom-half";
              # TODO window_move mode
            };
          };
        };
      };
    };
    # layers = {
    #   space = {
    #     mandatory_modifiers = ["command"];
    #     layer.bind = {
    #       space.open = "Raycast.app";
    #     };
    #   };
    # };
    # layers = let
    #   space_layer = {
    #     layer.name = "space";
    #     layer.bind = [
    #       {
    #         space.open = "raycast";
    #         r.layer = {
    #           name = "raycast";
    #           bind = [
    #             {
    #               a.raycast = "extensions/raycast/raycast-ai/ai-chat";
    #               e.raycast = "extensions/raycast/emoji-symbols/search-emoji-symbols";
    #               p.raycast = "extensions/raycast/clipboard-history/clipboard-history";
    #               P.raycast = "extensions/raycast/raycast/confetti";
    #             }
    #           ];
    #         };
    #         w.layer = {
    #           name = "window";
    #           bind = {
    #           };
    #         };
    #         o.layer = {
    #           name = "open";
    #           bind = [
    #             {
    #               f.open = "Firefox Developer Edition.app";
    #               F.open = "Finder.app";
    #               n.open = "Notion.app";
    #               s.open = "Slack.app";
    #               S.open = "Settings.app";
    #               t.open = "Alacritty.app";
    #             }
    #           ];
    #         };
    #         # TODO this should activate a transient mode instead of a layer
    #         # s.layer = {
    #         #   name = "system";
    #         #   bind = [
    #         #     {
    #         #       n.to = "volume_increment";
    #         #       e.to = "volume_decrement";
    #         #     }
    #         #   ];
    #         # };
    #         t.layer = {
    #           name = "toggles";
    #           bind = [
    #             {
    #               grave_accent_and_tilde.toggle_mode = "colemak_mod_dh";
    #               t.raycast = "extensions/raycast/system/toggle-system-appearance";
    #             }
    #             {
    #               grave_accent_and_tilde.toggle_mode = "home_row_modifiers_colemak_dh";
    #               grave_accent_and_tilde.mandatory_mods = [
    #                 "left_shift"
    #                 "right_shift"
    #               ];
    #             }
    #           ];
    #         };
    #       }
    #     ];
    #   };
    # in {
    #   layer.name = "global";
    #   layer.bind = [
    #     {
    #       space.layer = space_layer;
    #       space.mandatory_mods = ["left_command"];
    #     }
    #     {
    #       space.layer = space_layer;
    #       space.mandatory_mods = ["right_command"];
    #     }
    #   ];
    # };
  };

  # TODO look into services.spacebar
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
    defaults.alf = {
      allowdownloadsignedenabled = 0;
      allowsignedenabled = 0;
      globalstate = 1;
      loggingenabled = 0;
      stealthenabled = 1;
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
    home.stateVersion = "25.05";
    imports = [
      ../../../hm_modules
      ../../../nixpkgs/sure
      inputs.mac-app-util.homeManagerModules.default
    ];
    dotfiles.shell = {
      enable = true;
      shell_scripts.enable = false;
      pipx.enable = false;
      gpg.enable = true;
    };
    dotfiles.gui.enable = true;
    dotfiles.gui.sway.enable = false;
    programs.git = {
      userName = "Chris Cummings";
      userEmail = "chris.cummings@sureapp.com";
      signing.signByDefault = true;
    };
    programs.jujutsu.settings.scope = [
      {
        paths = ["~/sureapp/**"];
        user = {
          name = "Chris Cummings";
          email = "chris.cummings@sureapp.com";
        };
      }
    ];

    # programs.firefox.package = pkgs.firefox-devedition-bin;
    programs.zoom.enable = false;
    programs.darktable.enable = false;
    programs.signal.enable = false;
    programs.waybar.enable = false;
    programs.windsurf.enable = false; # this is overlayed into windsurf

    home.packages = with pkgs; [raycast postman];
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

  homebrew = {
    enable = false;
    casks = [
      "firefox-developer-edition"
    ];
    taps = [
      "homebrew/cask-versions"
    ];
  };

  time.timeZone = "America/New_York";
}

{
  pkgs,
  inputs,
  input-modules,
  ...
}: {
  nixpkgs.config.allowUnfree = true;
  imports = [
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    }
  ];
  environment.systemPackages = with pkgs; [
    git
    nix-prefetch-scripts
    neovim
    which
  ];

  nixpkgs.config.allowUnsupportedSystem = true;
  nixpkgs.config.allowBroken = true;
  nix = {
    package = pkgs.nixFlakes;
    settings.substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://averagechris-dotfiles.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
    ];
    settings.trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "averagechris-dotfiles.cachix.org-1:VwJkl5dG1+xGDY5x884mH/kVwwpgwBAdBKIF3BZiia4="
    ];
    extraOptions = ''experimental-features = nix-command flakes'';
    gc.automatic = true;
    readOnlyStore = true;
    settings.require-sigs = true;
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

  # TODO look into services.spacebar
  services.nix-daemon.enable = true;

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
      expose-group-by-app = true;
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
      TrackpadRightClick = false;
      TrackpadThreeFingerDrag = true;
    };
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = false;
      remapCapsLockToEscape = true;
      swapLeftCommandAndLeftAlt = false;
    };
    stateVersion = 4;
  };

  users.users.chrisnotnix = {
    name = "chrisnotnix";
    home = "/Users/chrisnotnix";
  };
  home-manager.users.chrisnotnix = {pkgs, ...}: {
    home.stateVersion = "22.11";
    imports = [
      ../../../hm_modules
      ../../terminal_emulator
    ];
    dotfiles.shell = {
      enable = true;
      nerdfonts.enable = true;
      shell_scripts.enable = false;
      gitui.enable = false;
      helix.enable = false;
      zellij.enable = false;
    };
  };

  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    (nerdfonts.override {
      fonts = [
        "FiraCode"
        "DroidSansMono"
        "Overpass"
      ];
    })
  ];

  time.timeZone = "America/Chicago";
}

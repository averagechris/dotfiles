{
  config,
  pkgs,
  inputs,
  lib,
  overlays,
  sshKeys,
  ...
}: let
  ctxPackage = inputs.ctx.packages.${pkgs.stdenv.hostPlatform.system}.ctx;
  rdnyPackage = inputs.rdny.packages.${pkgs.stdenv.hostPlatform.system}.rdny;
  srhtPackage = inputs.srht.packages.${pkgs.stdenv.hostPlatform.system}.srht;
  rdnyHeliumPackage = pkgs.writeShellApplication {
    name = "rdny-helium";
    runtimeInputs = [pkgs.coreutils pkgs.curl rdnyPackage];
    text = ''
      set -euo pipefail

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/rdny/visible-helium"
      profile_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/rdny/visible-helium-profile"
      endpoint="http://127.0.0.1:9333/json/version"

      mkdir -p "$state_dir" "$profile_dir"

      if ! rdny --state-dir "$state_dir" status >/dev/null 2>&1; then
        if ! curl --fail --silent --show-error "$endpoint" >/dev/null 2>&1; then
          /usr/bin/open -na Helium --args \
            --remote-debugging-address=127.0.0.1 \
            --remote-debugging-port=9333 \
            --user-data-dir="$profile_dir"

          for _ in $(seq 1 100); do
            if curl --fail --silent "$endpoint" >/dev/null 2>&1; then
              break
            fi
            sleep 0.1
          done
        fi

        if ! curl --fail --silent --show-error "$endpoint" >/dev/null; then
          printf 'Helium did not expose its DevTools endpoint at 127.0.0.1:9333\n' >&2
          exit 1
        fi

        rdny --state-dir "$state_dir" connect helium
      fi

      if [[ $# -eq 0 ]]; then
        exec rdny --state-dir "$state_dir" status
      fi
      exec rdny --state-dir "$state_dir" "$@"
    '';
  };
  # The nixpkgs Darwin WezTerm build embeds the absolute clang-wrapper path in
  # OpenSSL compiler metadata inside the app binaries. That single non-runtime
  # string keeps the full clang/LLVM/Apple SDK closure alive in the user profile,
  # so copy the cached package and scrub only that build-time reference.
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
  appTrampolinePackage = pkgs.writeShellApplication {
    name = "dotfiles-mac-app-trampolines";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -euo pipefail

      usage() {
        printf 'usage: %s sync-trampolines SOURCE_DIR TARGET_DIR\n' "$0" >&2
      }

      if [[ "''${1:-}" != sync-trampolines || $# -ne 3 ]]; then
        usage
        exit 2
      fi

      source_dir="$2"
      target_dir="$3"
      mkdir -p "$target_dir"

      shopt -s nullglob
      for source_app in "$source_dir"/*.app; do
        app_name="$(basename "$source_app")"
        bundle_name="''${app_name%.app}"
        target_app="$target_dir/$app_name"
        executable="$target_app/Contents/MacOS/open-source-app"

        rm -rf "$target_app"
        mkdir -p "$target_app/Contents/MacOS"

        cat >"$target_app/Contents/Info.plist" <<PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>open-source-app</string>
        <key>CFBundleIdentifier</key>
        <string>com.thesogu.dotfiles.trampoline.$bundle_name</string>
        <key>CFBundleName</key>
        <string>$bundle_name</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
      </dict>
      </plist>
      PLIST

        cat >"$executable" <<SCRIPT
      #!/bin/sh
      exec /usr/bin/open "$source_app" --args "\$@"
      SCRIPT
        chmod +x "$executable"
      done
    '';
  };
in {
  imports = [
    inputs.darwin-modules.darwinModules.colemak-dh
    inputs.darwin-modules.darwinModules.custom-sshd
    ./self-update.nix
  ];

  age.identityPaths = ["/Users/chris/.ssh/id_ed25519" "/Users/chris/.ssh/id_rsa"];

  dotfiles.colemakDh.enable = true;
  dotfiles.customSshd.enable = true;

  age.secrets = {
    openrouter-api-key = {
      file = ../../../secrets/openrouter-api-key-work.age;
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

    granola-token = {
      file = ../../../secrets/granola-token.age;
      owner = "chris";
      mode = "0400";
    };

    opencode-sure-stack-context = {
      file = ../../../secrets/opencode-sure-stack-context.age;
      owner = "chris";
      mode = "0400";
    };

    # kubectl reads this decrypted path directly via KUBECONFIG (see aws.nix).
    suremac-kubeconfig-eks = {
      file = ../../../secrets/suremac-kubeconfig-eks.age;
      owner = "chris";
      mode = "0400";
    };
  };

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    gitMinimal
    nh
    neovim
    nix-output-monitor
    notion-cli
    which
  ];

  nixpkgs.config.allowUnsupportedSystem = true;
  nixpkgs.overlays = lib.attrValues overlays;
  system.activationScripts.postActivation.text = lib.mkAfter ''
    ${appTrampolinePackage}/bin/dotfiles-mac-app-trampolines sync-trampolines "/Applications/Nix Apps" "/Applications/Nix Trampolines"
  '';
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
    openssh.authorizedKeys.keys = [
      sshKeys.chris.thelio
      sshKeys.system.tater
    ];
  };

  services.openssh.enable = true;

  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "26.05";
    home.packages = with pkgs; [
      inputs.slack.packages.${pkgs.stdenv.hostPlatform.system}.slack
      kubernetes-helm
      rdnyHeliumPackage
    ];
    imports = [
      inputs.hm-modules.homeManagerModules.default
      ./aws.nix
    ];
    targets.darwin.copyApps.enableChecks = false;
    home.activation.trampolineApps = inputs.home-manager.lib.hm.dag.entryAfter ["writeBoundary"] ''
      fromDir="$HOME/Applications/Home Manager Apps"
      toDir="$HOME/Applications/Home Manager Trampolines"
      ${appTrampolinePackage}/bin/dotfiles-mac-app-trampolines sync-trampolines "$fromDir" "$toDir"
    '';
    dotfiles.shell = {
      enable = true;
      shell_scripts.enable = false;
      pipx.enable = false;
      gpg.enable = true;
    };
    dotfiles.gui.enable = true;
    dotfiles.wezterm.enable = true;
    programs.wezterm.package = weztermPackage;
    dotfiles.macosHotkeys.enable = false;
    dotfiles.gander.enable = true;
    dotfiles.devCache = {
      enable = true;
      sccache.cacheSize = "100G";
      cleanup = {
        # This laptop churns through Nix/Cargo/Docker artifacts quickly while
        # agents work in parallel. Cleanup is due every six hours, but a cheap
        # five-minute gate waits for CPU headroom and no conflicting dev tools.
        intervalSeconds = 21600;
        retryIntervalSeconds = 300;
        lowDisk = {
          enable = true;
          checkIntervalSeconds = 900;
          minFreeGiB = 10;
          dockerBuilderMaxUsedSpace = "10GB";
        };
      };
      nixGc.olderThanDays = 3;
      # --recursive picks up nested checkouts too, including managed jj
      # workspaces under ~/projects/ws/<repo>/* and ~/sureapp/ws/<repo>/*.
      cargoSweep = {
        staleDays = 3;
        roots = [
          "/Users/chris/projects"
          "/Users/chris/sureapp"
        ];
      };
      docker = {
        retention = "336h";
        builderMaxUsedSpace = "30GB";
        pruneVolumes = true;
      };
    };
    dotfiles.gui.terminal = {
      package = lib.mkDefault weztermPackage;
      args = lib.mkDefault [];
      binPath = lib.mkDefault "${weztermPackage}/bin/wezterm";
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
    dotfiles.jujutsu.prWorkflow.enable = true;
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
    dotfiles.opencode.sessionCleanup.enable = true;
    programs.opencode.skills.granola-meeting-context = builtins.readFile ../../hm-modules/modules/opencode/skills/granola-meeting-context/SKILL.md;
    programs.opencode.skills.pup-cli = builtins.readFile ../../hm-modules/modules/opencode/skills/pup-cli/SKILL.md;
    programs.opencode.skills.sentry-cli = builtins.readFile ../../hm-modules/modules/opencode/skills/sentry-cli/SKILL.md;
    programs.opencode.skills.suremac-jj-pr = builtins.readFile ../../hm-modules/modules/opencode/skills/suremac-jj-pr/SKILL.md;
    home.activation.cleanup-opencode-pup-stack-hints = inputs.home-manager.lib.hm.dag.entryBefore ["checkFilesChanged"] ''
      skill="$HOME/.config/opencode/skills/pup-cli/SKILL.md"
      backup="$skill.hm.bak"

      # Older generations appended the private stack appendix directly to the
      # Home Manager-managed pup-cli skill. Remove that generated local copy and
      # its stale backup before checkFilesChanged so Home Manager can relink the
      # now-public-only pup-cli skill without backup collisions.
      if [[ -f "$skill" ]] && ${pkgs.gnugrep}/bin/grep -q '^## Sure stack hints$' "$skill"; then
        ${pkgs.coreutils}/bin/rm -f "$skill"
      fi
      ${pkgs.coreutils}/bin/rm -f "$backup"
    '';
    home.activation.install-opencode-sure-stack-context = inputs.home-manager.lib.hm.dag.entryAfter ["linkGeneration"] ''
      skill="$HOME/.config/opencode/skills/sure-stack-context/SKILL.md"
      publicSkill="${../../hm-modules/modules/opencode/skills/sure-stack-context/SKILL.md}"
      secret="${config.age.secrets.opencode-sure-stack-context.path}"

      if [[ -r "$publicSkill" && -r "$secret" ]]; then
        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.coreutils}/bin/cp "$publicSkill" "$tmp"
        ${pkgs.coreutils}/bin/chmod u+w "$tmp"
        ${pkgs.coreutils}/bin/printf '\n' >> "$tmp"
        ${pkgs.coreutils}/bin/cat "$secret" >> "$tmp"
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$skill")"
        ${pkgs.coreutils}/bin/rm -f "$skill"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp" "$skill"
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    '';
    programs.pi = {
      enable = true;
      openrouterApiKeyFile = config.age.secrets.openrouter-api-key.path;
    };
    dotfiles.ctx = {
      enable = true;
      package = ctxPackage;
      index.enable = true;
    };
    dotfiles.granola = {
      enable = true;
      tokenFile = config.age.secrets.granola-token.path;
      sync.enable = true;
    };
    dotfiles.sideshow = {
      enable = true;
      srht.tokenCommand = ["/usr/bin/security" "find-generic-password" "-s" "srht" "-a" "sr.ht" "-w"];
      tools = {
        ffmpeg.enable = true;
        aws = {
          enable = true;
          package = pkgs.awscli2;
        };
      };
    };
    dotfiles.rdny = {
      enable = true;
      package = rdnyPackage;
      binaries = {
        chrome = {
          enable = true;
          path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
        };
        ffmpeg.enable = true;
      };
      connect.targets.helium = "127.0.0.1:9333";
    };
    dotfiles.agentSkills.rdny-browser.extraText = ''
      ## suremac browser choice

      Use ordinary `rdny` commands for browser automation unless the user
      explicitly asks to see the browser, control a graphical browser, or use
      visible Helium. `rdny start` uses a task-owned, isolated Google Chrome
      profile and is headless unless `--show` is passed; do not pass `--show`
      for normal automation.

      For an explicit visible-browser request, use `rdny-helium` in place of
      `rdny` for every command, for example:

      ```bash
      rdny-helium pages
      rdny-helium open https://example.com
      rdny-helium click 'button'
      ```

      `rdny-helium` reconnects to the dedicated graphical Helium session when
      it is already available. Otherwise it starts visible Helium with a
      loopback CDP endpoint and a persistent profile separate from the user's
      ordinary Helium profile, then connects. Do not terminate or replace an
      ordinary Helium process to make it controllable.
    '';
    dotfiles.srht.enable = true;
    dotfiles.opencode.agentSupportPackages = [];
    dotfiles.opencode.agentTools = with pkgs; [
      {
        package = awscli2;
        name = "aws";
        description = "AWS CLI";
      }
      {
        package = ctxPackage;
        name = "ctx";
        description = "agent history search CLI";
      }
      {
        package = kubectl;
        name = "kubectl";
        description = "Kubernetes CLI";
      }
      {
        package = pkgs.pup;
        name = "pup";
        description = "Datadog CLI";
      }
      {
        package = pkgs.sentry;
        name = "sentry";
        description = "Sentry CLI";
      }
      {
        package = notion-cli;
        name = "ntn";
        description = "Notion CLI";
      }
      {
        package = gh;
        name = "gh";
        description = "GitHub CLI";
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
      {
        package = inputs.granola-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
        name = "granola";
        description = "Granola meeting notes CLI";
      }
      {
        package = srhtPackage;
        name = "srht";
        description = "SourceHut CLI";
      }
    ];

    programs.firefox.enable = false;
    programs.nitter-link = {
      enable = true;
      chromiumBrowsers.helium = {
        enable = true;
        extensionPackage = inputs.nitter-link.packages.${pkgs.stdenv.hostPlatform.system}.chrome-extension;
        stablePath = "/Users/chris/.config/net.imput.helium/nitter-link";
      };
    };
    programs.kitty.enable = false;
    programs.zoom.enable = false;
    programs.darktable.enable = false;
    programs.signal.enable = false;
    programs.waybar.enable = false;

    dotfiles.linearCli = {
      enable = true;
      package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear;
      cacheRefresh.enable = true;
      hygieneAutomation.enable = true;
    };
    dotfiles.agentSkills.linear-admin.enable = false;
    dotfiles.agentSkills.databricks-cli.enable = false;
  };

  fonts.packages = [pkgs.nerd-fonts.droid-sans-mono];
  programs.gnupg.agent.enable = true;

  # NOTE: nix-darwin only runs its fixed set of activation fragments
  # (preActivation, extraActivation, postActivation, ...); arbitrary names are
  # silently ignored, so this must extend one of them.
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    echo "configuring location-aware time..." >&2
    systemsetup -setusingnetworktime on >/dev/null 2>&1 || true
  '';

  homebrew = {
    enable = false;
    casks = [];
    taps = [];
  };

  # Let macOS set the timezone from the current network-derived location instead
  # of pinning this laptop to one coast in the declarative config.
  time.timeZone = null;
}

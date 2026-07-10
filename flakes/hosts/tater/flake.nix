{
  description = "Tater NixOS system configuration (ThinkPad T14s Gen 5 AMD)";

  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    nixos-modules = {
      url = "path:../../nixos-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    hm-modules = {
      url = "path:../../hm-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "home-manager";
      inputs.opencode.follows = "base-lib/opencode";
      inputs.nitter-link.follows = "nitter-link";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    systems.url = "github:nix-systems/default-linux";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";
    helix.follows = "hm-modules/helix";
    starship-jj.follows = "hm-modules/starship-jj";
    gander.follows = "hm-modules/gander";
    srht = {
      url = "sourcehut:~averagechris/srht";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ctx = {
      url = "sourcehut:~averagechris/ctx";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
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
    hyprland = {
      # Pinned to the revision Hyprspace currently tests against so the
      # compositor and overview plugin agree on Hyprland's internal plugin ABI.
      url = "github:hyprwm/Hyprland/0002f148c9a4fe421a9d33c0faa5528cdc411e62";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    Hyprspace = {
      url = "github:KZDKM/Hyprspace";
      inputs.hyprland.follows = "hyprland";
      inputs.systems.follows = "systems";
    };
    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    anyrun = {
      url = "github:anyrun-org/anyrun";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    pip-chrome-extension = {
      url = "git+https://git.sr.ht/~averagechris/pip-chrome-extension";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nitter-link = {
      url = "git+https://git.sr.ht/~averagechris/nitter-link?ref=refs/tags/v0.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    base-lib,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    inherit (base-lib) lib;
    pkgs = nixpkgs.legacyPackages.${system};
    bool = value:
      if value
      then "true"
      else "false";
    taterSystem = lib.mkNixosHost {
      inherit system;
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };
    cfg = taterSystem.config;
    hm = cfg.home-manager.users.chris;
    greetdCommand = cfg.services.greetd.settings.default_session.command or "";
    greetdUser = cfg.services.greetd.settings.default_session.user or "";
    greetdHyprlandConfigPath =
      if greetdCommand != ""
      then pkgs.lib.last (pkgs.lib.splitString " " greetdCommand)
      else "";
  in {
    nixosConfigurations.tater = taterSystem;

    deploy.nodes.tater = lib.mkDeploy' self.nixosConfigurations.tater;

    checks.${system} = {
      tater-desktop-static = pkgs.runCommand "tater-desktop-static-check" {nativeBuildInputs = [pkgs.bash pkgs.ripgrep pkgs.shellcheck];} ''
        set -euo pipefail

        root=${./../../..}
        tater="$root/flakes/hosts/tater/configuration.nix"
        hyprlock="$root/flakes/hm-modules/modules/gui/hyprlock/default.nix"
        eww="$root/flakes/hm-modules/modules/gui/eww/config/eww.yuck"
        ewwModule="$root/flakes/hm-modules/modules/gui/eww/default.nix"
        greetd="$root/flakes/nixos-modules/modules/greetd.nix"
        hyprlandDesktop="$root/flakes/nixos-modules/modules/hyprland-desktop.nix"
        scripts="$root/flakes/hm-modules/modules/gui/eww/config/scripts"

        assert_eq() {
          name="$1"
          actual="$2"
          expected="$3"
          if [[ "$actual" != "$expected" ]]; then
            echo "FAIL $name: expected '$expected', got '$actual'" >&2
            exit 1
          fi
          echo "PASS $name"
        }

        assert_contains() {
          name="$1"
          haystack="$2"
          needle="$3"
          if [[ "$haystack" != *"$needle"* ]]; then
            echo "FAIL $name: expected command to contain '$needle'" >&2
            echo "$haystack" >&2
            exit 1
          fi
          echo "PASS $name"
        }

        echo "== Script correctness =="
        # Why this matters: Eww and monitor helpers are shell-heavy, and a syntax
        # error here can break the bar after a rebuild even when Nix evaluation
        # succeeds. Shellcheck catches the highest-value issues without encoding
        # subjective desktop policy.
        bash -n "$scripts"/*.sh
        shellcheck "$scripts"/*.sh

        echo "== Known-bad greeter tripwires =="
        # Why this matters: these are previously observed greeter breakages. Keep
        # this as a narrow tripwire list, not a broad style policy for all CSS.
        ! rg -n 'hyprtcl|lighten\(|transform:|@keyframes|animation:' "$greetd" "$hyprlandDesktop"

        echo "== Evaluated login/auth invariants =="
        # Why these matter: they test the final merged NixOS config rather than
        # hard-coding source layout. If these fail, the machine may boot without a
        # usable graphical login or without the expected auth fallback paths.
        assert_eq "greetd enabled" ${bool cfg.services.greetd.enable} true
        assert_eq "regreet enabled" ${bool cfg.programs.regreet.enable} true
        assert_eq "greetd runs as greeter" ${builtins.toJSON greetdUser} greeter
        assert_contains "greetd starts inside dbus-run-session" ${builtins.toJSON greetdCommand} dbus-run-session
        assert_contains "greetd starts start-hyprland" ${builtins.toJSON greetdCommand} start-hyprland
        assert_eq "fprintd enabled" ${bool cfg.services.fprintd.enable} true
        assert_eq "fprintd TOD enabled" ${bool cfg.services.fprintd.tod.enable} true
        assert_eq "sudo uses password-first auth" ${bool cfg.security.pam.services.sudo.fprintAuth} false

        echo "== Evaluated Wi-Fi stability invariants =="
        # Why these matter: tater's MT7925e has a history of disconnect/recovery
        # failures. These assertions preserve the mitigations that make the laptop
        # usable while still allowing intentional policy changes in one obvious
        # place.
        assert_eq "NetworkManager uses iwd for Wi-Fi" ${builtins.toJSON cfg.networking.networkmanager.wifi.backend} iwd
        assert_eq "NetworkManager Wi-Fi powersave disabled" ${bool (! cfg.networking.networkmanager.wifi.powersave)} true
        assert_eq "iwd enabled" ${bool cfg.networking.wireless.iwd.enable} true
        assert_eq "TLP Wi-Fi powersave off on battery" ${builtins.toJSON cfg.services.tlp.settings.WIFI_PWR_ON_BAT} off
        assert_eq "NetworkManager restarts on failure" ${builtins.toJSON cfg.systemd.services.NetworkManager.serviceConfig.Restart} always

        echo "== Evaluated laptop desktop invariants =="
        # Why these matter: they encode durable laptop behavior, not aesthetics:
        # docked/external-power lid close must not suspend out from under
        # clamshell mode, and the core desktop daemons must be enabled.
        assert_eq "logind ignores lid while docked" ${builtins.toJSON cfg.services.logind.settings.Login.HandleLidSwitchDocked} ignore
        assert_eq "logind ignores lid on external power" ${builtins.toJSON cfg.services.logind.settings.Login.HandleLidSwitchExternalPower} ignore
        assert_eq "systemd enables hibernation" ${builtins.toJSON cfg.systemd.sleep.settings.Sleep.AllowHibernation} yes
        assert_eq "systemd enables suspend-then-hibernate" ${builtins.toJSON cfg.systemd.sleep.settings.Sleep.AllowSuspendThenHibernate} yes
        assert_eq "systemd hibernates after one suspended hour" ${builtins.toJSON cfg.systemd.sleep.settings.Sleep.HibernateDelaySec} 1h
        assert_eq "tater disables zram while hibernating to disk" ${bool cfg.zramSwap.enable} false
        assert_eq "tater resumes from encrypted-root swapfile filesystem" ${builtins.toJSON cfg.boot.resumeDevice} /dev/disk/by-uuid/e817895a-ef3f-4289-8c9e-7e4e49703b13
        assert_eq "Hyprland system module enabled" ${bool cfg.programs.hyprland.enable} true
        assert_eq "kanshi enabled for chris" ${bool hm.services.kanshi.enable} true
        assert_eq "hypridle enabled for chris" ${bool hm.services.hypridle.enable} true
        assert_eq "hyprlock enabled for chris" ${bool hm.programs.hyprlock.enable} true
        listener_json='${builtins.toJSON hm.services.hypridle.settings.listener}'
        assert_contains "hypridle has home clamshell helper" "$listener_json" tater-home-docked
        assert_contains "hypridle has home clamshell suspend" "$listener_json" 3600
        assert_contains "hypridle uses suspend-then-hibernate" "$listener_json" suspend-then-hibernate
        assert_contains "hypridle honors shared idle inhibit" "$listener_json" dotfiles-idle-inhibit

        echo "== Source-level desktop tripwires =="
        # Why this matters: these names are integration points between separate
        # tools (Eww, Hyprland, kanshi, helper commands). Grepping them is more
        # appropriate than over-modeling the UI in Nix. If the policy changes,
        # update these few integration tripwires with the new names.
        rg -n 'tater-home-toggle|tater-home-open|tater-home-clamshell|tater-home-docked|tater-display-refresh|dotfiles-idle-inhibit|tater-network-recover|tater-desktop-doctor' "$tater" "$root/flakes/hm-modules/modules/gui/hypridle/default.nix"
        rg -n 'lock-on-undocked-lid-close|disable-builtin-display-when-lid-closed' "$root/flakes/hm-modules/modules/gui/hyprland/default.nix"
        rg -n 'idle-inhibit-widget|dotfiles-idle-inhibit' "$eww" "$root/flakes/hm-modules/modules/gui/eww/config/eww.scss"
        rg -n 'bar-internal|bar-external' "$eww" "$ewwModule"
        rg -n ':monitor "eDP-1"' "$eww"
        rg -n ':monitor "DP-2"' "$eww"
        rg -n 'scripts/workspaces\.sh eDP-1|scripts/workspaces\.sh DP-2' "$eww"
        rg -n 'Touch fingerprint sensor or type password' "$hyprlock"

        touch $out
      '';

      tater-hyprland-greeter-config = lib.mkHyprlandConfigCheck {
        name = "tater-hyprland-greeter-config";
        hyprlandPackage = cfg.programs.hyprland.package;
        configFile = greetdHyprlandConfigPath;
      };

      tater-hyprland-home-config = lib.mkHyprlandConfigCheck {
        name = "tater-hyprland-home-config";
        hyprlandPackage = hm.wayland.windowManager.hyprland.finalPackage;
        configFile = hm.xdg.configFile."hypr/hyprland.conf".source;
      };
    };
  };
}

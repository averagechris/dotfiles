{inputs}: {
  hostPkgs,
  lib,
  ...
}: let
  guestSystem = "aarch64-linux";
  hyprlandPackage = inputs.hyprland.packages.${guestSystem}.hyprland.overrideAttrs (old: {
    env =
      (old.env or {})
      // {
        GIT_TAG = "v${lib.removeSuffix "\n" (builtins.readFile "${inputs.hyprland}/VERSION")}";
      };
  });
  hyprlandPortalPackage = inputs.hyprland.packages.${guestSystem}.xdg-desktop-portal-hyprland;
  # Keep the test on the same nixpkgs ReGreet as the production module, rather
  # than accidentally testing a package supplied by the test driver's pkgs.
  regreetPackage = inputs.nixpkgs.legacyPackages.${guestSystem}.regreet;
in {
  name = "hyprland-greetd-vm";
  globalTimeout = 15 * 60;
  enableOCR = true;

  nodes.machine = {pkgs, ...}: {
    imports = [../../flakes/nixos-modules/modules/hyprland-desktop.nix];

    # Exercise the repository's actual Hyprland/ReGreet module. Keep the VM
    # otherwise deliberately generic: it must not inherit a host's hardware,
    # disk, network, user, or secret configuration.
    dotfiles.hyprland-desktop.enable = true;

    # Match the pinned compositor used by tater and thorny. runNixOSTest makes
    # the guest package set read-only, so select the production packages through
    # their supported NixOS options rather than adding a test-only overlay.
    programs.hyprland = {
      package = hyprlandPackage;
      portalPackage = hyprlandPortalPackage;
    };
    services.displayManager.regreet.package = regreetPackage;
    xdg.portal.extraPortals = lib.mkForce [
      hyprlandPortalPackage
      pkgs.xdg-desktop-portal-gtk
    ];

    users.users.vmtest = {
      isNormalUser = true;
      initialPassword = "vmtest";
      description = "Graphical VM test user";
    };

    # ReGreet 0.4 discovers users through AccountsService's ListCachedUsers,
    # which intentionally excludes a brand-new account that has never logged in.
    # Seed only this disposable VM account so the test models a greeter with a
    # selectable user instead of depending on mutable login history.
    systemd.services.accounts-daemon.preStart = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 /var/lib/AccountsService/users
      ${pkgs.coreutils}/bin/cat > /var/lib/AccountsService/users/vmtest <<'EOF'
      [User]
      SystemAccount=false
      EOF
      ${pkgs.coreutils}/bin/chmod 0600 /var/lib/AccountsService/users/vmtest
    '';

    hardware.graphics.enable = true;
    virtualisation = {
      cores = 2;
      memorySize = 3072;

      # Linux/aarch64 test hosts get this device from the test framework.
      # The Darwin-hosted driver needs it stated explicitly so Hyprland has a
      # DRM scanout and the driver can use QEMU screendump.
      qemu.options = lib.optionals hostPkgs.stdenv.hostPlatform.isDarwin [
        "-device virtio-gpu-pci"
      ];
    };

    environment.systemPackages = [pkgs.procps];
  };

  testScript = ''
    start_all()
    try:
        machine.wait_for_unit("multi-user.target", timeout=180)
        machine.wait_for_unit("greetd.service", timeout=120)

        # Prefer observable process/socket state over OCR or visual matching.
        # This proves the real greetd command reached Hyprland and ReGreet, and
        # that the compositor published its Wayland and control sockets.
        machine.wait_until_succeeds(
            "pgrep --full '^.*/bin/Hyprland( |$)'",
            timeout=120,
        )
        machine.wait_until_succeeds(
            "pgrep --full '^.*/bin/regreet( |$)'",
            timeout=120,
        )
        machine.wait_until_succeeds(
            "find /run/user -type s -name 'wayland-*' -print -quit | grep -q .",
            timeout=120,
        )
        machine.wait_until_succeeds(
            "find /run/user -type s -name '.socket.sock' -print -quit | grep -q .",
            timeout=120,
        )

        # ReGreet is an async Relm4 component. A running process only proves its
        # loading window exists; this marker is emitted after user discovery and
        # login-form setup have completed. OCR then proves that the stable,
        # prominent greeting actually reached the framebuffer without asserting
        # exact pixels.
        machine.wait_until_succeeds(
            "grep -Fq \"Using first found user 'vmtest' as initial user\" /var/log/regreet/log",
            timeout=120,
        )
        machine.wait_for_text(r"Welcome\s+back", timeout=60)
        # The keyboard and screenshot helpers both use the QEMU monitor. Also
        # make a direct monitor query so loss of monitor interaction is a clear
        # failure. Keep these checks in the protected block so their failures
        # get the same diagnostics as startup failures.
        qtree = machine.send_monitor_command("info qtree")
        assert "virtio-gpu" in qtree, qtree
        machine.send_key("tab")
        machine.sleep(1)
        machine.succeed("pgrep --full '^.*/bin/Hyprland( |$)'")
        machine.succeed("pgrep --full '^.*/bin/regreet( |$)'")
        # This is a human/agent diagnostic artifact, not a pixel assertion.
        machine.screenshot("hyprland-greetd-ready")
    except Exception:
        for diagnostic in [
            "systemctl --no-pager --full status greetd.service",
            "systemctl --no-pager --full status accounts-daemon.service",
            "journalctl -b -u greetd.service --no-pager -n 200",
            "journalctl -b -u accounts-daemon.service --no-pager -n 200",
            "cat /var/log/regreet/log 2>&1",
            "cat /var/lib/AccountsService/users/vmtest 2>&1",
            "busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts ListCachedUsers",
            "ps auxww",
            "find /run/user -name hyprland.log -exec cat {} \\; 2>&1",
            "find /dev/dri /run/user -maxdepth 4 -print 2>&1",
        ]:
            try:
                status, output = machine.execute(diagnostic)
                print(f"diagnostic ({status}) $ {diagnostic}\n{output}")
            except Exception as diagnostic_error:
                print(f"diagnostic failed $ {diagnostic}: {diagnostic_error}")
        try:
            machine.screenshot("hyprland-greetd-failure")
        except Exception as screenshot_error:
            print(f"could not capture failure screenshot: {screenshot_error}")
        raise
  '';
}

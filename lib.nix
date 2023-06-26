{
  inputs,
  nixpkgs,
}: rec {
  sshKeys = rec {
    chris.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com";
    chris.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com";
    chris.trap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO1u2+EqAzFOidZ+b0dixultkTyvIsOXZJsiG+/kDpJm chris@trap";
    system.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos";
    system.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy30vzaxmqc08+NcYYA7LflDqoZNdRoyVXVJ2H9p2Xp root@xps-nixos";
    usesRemoteBuilders = {
      inherit (system) thelio xps;
    };
  };

  overlays = {
    emacs = inputs.emacs-overlay.overlay;
    wayland = inputs.wayland-overlay.overlay;
  };

  specialArgs = {
    inherit inputs overlays sshKeys;
    input-modules.doom = inputs.nix-doom-emacs.hmModule;
    dotfiles_lib.options = with inputs.nixpkgs.legacyPackages.x86_64-linux.lib; {
      mkDefaultEnabledOption = description:
        mkOption {
          type = types.bool;
          default = true;
          example = false;
          description = mdDoc description;
        };
    };
  };

  mkHost = system: hostPath: let
    fn =
      if system == "aarch64-darwin"
      then inputs.darwin.lib.darwinSystem
      else nixpkgs.lib.nixosSystem;
  in
    fn {
      inherit specialArgs system;
      modules = [
        hostPath
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.extraSpecialArgs = specialArgs;
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
      ];
    };

  mkDeploy = host: {
    hostname = host.config.networking.hostName;
    profiles.system = {
      sshOpts = ["-t"];
      user = "root";
      path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos host;
      sshUser = "chris";
      fastConnection = true;
      magicRollback = false;
      autoRollback = false;
    };
  };

  mkCommitCheck = system: {
    pre-commit = inputs.pre-commit-hooks.lib.${system}.run {
      src = ./.;
      hooks = {
        alejandra.enable = true;
        statix.enable = true;
        shellcheck.enable = true;
        markdown-formatter = {
          enable = true;
          name = "markdown-formatter";
          types = ["markdown"];
          language = "system";
          pass_filenames = true;
          entry = with inputs.nixpkgs.legacyPackages.${system}.python311Packages; "${mdformat}/bin/mdformat";
        };
        markdown-linter = {
          enable = true;
          name = "markdown-linter";
          types = ["markdown"];
          language = "system";
          pass_filenames = true;
          entry = with inputs.nixpkgs.legacyPackages.${system}; "${mdl}/bin/mdl -g";
        };
      };
    };
  };
}

{
  description = "NixOS modules for dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    base-lib = {
      url = "path:../base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

   outputs = {...}: {
    nixosModules = {
      common = ./modules/common.nix;
      cosmicDesktop = ./modules/cosmic-desktop.nix;
      desktopCommon = ./modules/desktop-common.nix;
      networking = ./modules/networking.nix;
      docker = ./modules/docker.nix;
      sound = ./modules/sound.nix;
      tailscale = ./modules/tailscale.nix;
      virtualization = ./modules/virtualization.nix;
      greetd = ./modules/greetd.nix;
      isRemoteBuilder = ./modules/is-remote-builder.nix;
      useRemoteBuilds = ./modules/use-remote-builds.nix;
      opensshClient = ./modules/openssh-client.nix;
      dropbox = ./modules/dropbox.nix;
      graphical = ./modules/graphical.nix;
      searx = ./modules/searx.nix;
      sudoDeploy = ./modules/sudo-deploy.nix;
      users = {
        chris = ./modules/users/chris.nix;
        chrisMinimal = ./modules/users/chris-minimal.nix;
      };
      homeAssistant = ./modules/home-assistant/default.nix;
    };
  };
}

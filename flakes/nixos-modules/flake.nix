{
  description = "NixOS modules for dotfiles";

  outputs = {...}: {
    nixosModules = {
      common = ./modules/common.nix;
      cosmicDesktop = ./modules/cosmic-desktop.nix;
      hyprlandDesktop = ./modules/hyprland-desktop.nix;
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
      selfDeploy = ./modules/self-deploy.nix;
      users = {
        chris = ./modules/users/chris.nix;
        chrisMinimal = ./modules/users/chris-minimal.nix;
      };
      homeAssistant = ./modules/home-assistant/default.nix;
    };
  };
}

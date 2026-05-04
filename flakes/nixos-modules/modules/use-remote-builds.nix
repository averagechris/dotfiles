{sshKeys, ...}: {
  programs.ssh.extraConfig = ''
    Host eu.nixbuild.net
      PubkeyAcceptedKeyTypes ssh-ed25519
      IdentityFile /etc/ssh/ssh_host_ed25519_key

    Host thorny thelio-nixos
      PubkeyAcceptedKeyTypes ssh-ed25519
      IdentityFile /etc/ssh/ssh_host_ed25519_key
      BatchMode yes
      ConnectTimeout 5
      ConnectionAttempts 1
      ServerAliveInterval 5
      ServerAliveCountMax 1
  '';

  programs.ssh.knownHosts = {
    nixbuild = {
      hostNames = ["eu.nixbuild.net"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    };
    thorny = {
      hostNames = ["thorny" "thelio-nixos"];
      publicKey = sshKeys.system.thelio;
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "eu.nixbuild.net";
        system = "aarch64-linux";
        maxJobs = 100;
        supportedFeatures = ["benchmark" "big-parallel"];
      }
      {
        hostName = "thorny";
        sshUser = "chris";
        sshKey = "/etc/ssh/ssh_host_ed25519_key";
        system = "x86_64-linux";
        maxJobs = 16;
        speedFactor = 4;
        supportedFeatures = ["benchmark" "big-parallel" "kvm" "nixos-test"];
      }
    ];
  };
}

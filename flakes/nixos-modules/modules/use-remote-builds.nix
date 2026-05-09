{sshKeys, ...}: {
  programs.ssh.extraConfig = ''
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
    thorny = {
      hostNames = ["thorny" "thelio-nixos"];
      publicKey = sshKeys.system.thelio;
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "thorny";
        sshUser = "chris";
        sshKey = "/etc/ssh/ssh_host_ed25519_key";
        system = "x86_64-linux";
        maxJobs = 16;
        speedFactor = 4;
        supportedFeatures = ["benchmark" "big-parallel" "kvm" "nixos-test"];
      }
      {
        hostName = "thorny";
        sshUser = "chris";
        sshKey = "/etc/ssh/ssh_host_ed25519_key";
        system = "aarch64-linux";
        maxJobs = 4;
        speedFactor = 1;
        supportedFeatures = ["benchmark" "big-parallel"];
      }
    ];

    settings.builders-use-substitutes = true;
  };
}

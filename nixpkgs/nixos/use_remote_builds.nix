{_, ...}: {
  programs.ssh.extraConfig = ''
    Host eu.nixbuild.net
      PubkeyAcceptedKeyTypes ssh-ed25519
      IdentityFile /etc/ssh/ssh_host_ed25519_key
  '';

  programs.ssh.knownHosts = {
    nixbuild = {
      hostNames = ["eu.nixbuild.net"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    };
  };

  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    buildMachines = [
      {
        hostName = "gnome-work-vm";
        maxJobs = 8;
        protocol = "ssh";
        supportedFeatures = ["kvm" "benchmark" "big-parallel"];
        system = "aarch64-linux";
      }
      {
        hostName = "eu.nixbuild.net";
        maxJobs = 100;
        protocol = "ssh-ng";
        supportedFeatures = ["benchmark" "big-parallel"];
        system = "aarch64-linux";
      }
      {
        hostName = "taz";
        maxJobs = 4;
        protocol = "ssh";
        supportedFeatures = ["kvm" "benchmark" "big-parallel"];
        system = "x86_64-linux";
      }
    ];
  };
}

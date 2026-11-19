{
  description = "Darwin modules for nix-darwin configurations";

  outputs = {...}: {
    darwinModules = {
      colemak-dh = ./modules/colemak-dh;
      custom-sshd = ./modules/custom-sshd;
    };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkMerge [
    {
      programs.git = {
        # The default Darwin `git` output currently drags in Python plus the Darwin
        # compiler/SDK toolchain. The minimal build is enough for everyday CLI use
        # and keeps user profiles much smaller; hosts can override if they need a
        # non-minimal Git feature.
        package = lib.mkDefault pkgs.gitMinimal;

        # Note: The gpg module (flakes/hm-modules/modules/gpg.nix) manages git config
        # including signing.key when dotfiles.gpg.enable = true. It imports the GPG key
        # from agenix and configures signing during activation.
        settings = {
          pull.rebase = true;
          init.defaultBranch = "main";
        };
        ignores = [".DS_Store"];
      };
    }

    (lib.mkIf config.programs.git.enable {
      home.packages = [pkgs.gnupg];
    })
  ];
}

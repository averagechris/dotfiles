{
  pkgs,
  sli-repo,
  ...
}: let
  sli = import ./sli.nix {
    inherit pkgs;
    inherit sli-repo;
  };
in {
  imports = [
    ./aws.nix
  ];

  config.programs.zsh = {
    cdpath = [
      "$HOME/sureapp"
    ];
  };

  # didn't seem worth it to nix-ify the kube config
  # add kube config imperatively via
  # aws eks list-clusters --output text --profile once-for-each-profile
  # then aws eks update-config -name once-for-each-name-above --alias preferred-alias --profile once-for-each-profile

  config.home.packages = with pkgs; [
    gnumake
    kubectl
    sli
  ];
}

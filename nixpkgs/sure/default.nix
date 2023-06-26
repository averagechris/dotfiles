{pkgs, ...}: {
  imports = [
    ./aws.nix
  ];

  config.programs.zsh = {
    cdpath = [
      "$HOME/sureapp"
    ];
    initExtra = ''
      export PATH=$HOME/.local/bin:$PATH
    '';
  };

  # didn't seem worth it to nix-ify the kube config
  # add kube config imperatively via
  # aws eks list-clusters --output text --profile once-for-each-profile
  # then aws eks update-config -name once-for-each-name-above --alias preferred-alias --profile once-for-each-profile

  config.home.packages = with pkgs; [
    pipx
    gnumake
    kubectl
  ];
}

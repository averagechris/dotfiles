{pkgs, ...}: {
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
    k9s
  ];

  config.programs.git.includes = [
    {
      condition = "gitdir:~/sureapp";
      contents.user = {
        name = "Chris Cummings";
        email = "chris.cummings@sureapp.com";
        signingkey = "6304B355257051A4E8DF61362C35DD58F54BC52F";
      };
    }
  ];
}

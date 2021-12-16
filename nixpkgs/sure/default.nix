{ config, pkgs, ... }:

{
  imports = [
    ./aws.nix
    ./sli.nix
  ];

  config.programs.zsh = {
    cdpath = [
      "$HOME/sureapp"
    ];
    initExtra = ''
      refresh_poetry_auth() {
        aws --profile registries-read sso login
        poetry config http-basic.codeartifact aws $(aws codeartifact get-authorization-token --domain sure --query authorizationToken --output text --profile registries-read)
      }
    '';
  };

  # didn't seem worth it to nix-ify the kube config
  # add kube config imperatively via
  # aws eks list-clusters --output text --profile once-for-each-profile
  # then aws eks update-config -name once-for-each-name-above --alias preferred-alias --profile once-for-each-profile

  config.home.packages = with pkgs; [
    kubectl
    k9s
  ];
}

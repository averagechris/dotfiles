{ config, pkgs, lib, ... }:
{
  virtualisation.docker.enable = true;
  virtualisation.podman.enable = false;

  environment.systemPackages = with pkgs; [
    docker
    docker-compose
    # podman-compose
  ];
}

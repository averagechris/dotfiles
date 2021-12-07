{ config, pkgs, lib, ... }:
{
  virtualisation.podman.enable = true;

  environment.systemPackages = with pkgs; [
    podman-compose
  ];
}

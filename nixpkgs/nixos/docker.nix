{ config, pkgs, lib, ... }:
{
  virtualisation.docker.enable = true;
  virtualisation.podman.enable = false;

  # for running elasticsearch containers
  # https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html#_linux
  boot.kernel.sysctl = {"vm.max_map_count" = 262144; };

  environment.systemPackages = with pkgs; [
    docker
    docker-compose
  ];
}

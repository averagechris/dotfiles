{
  lib,
  sshKeys,
  ...
}: {
  users.users.chris.openssh.authorizedKeys.keys = lib.attrValues sshKeys.usesRemoteBuilders;
}

{...}: {
  environment.sessionVariables = {
    # https://nixos.org/manual/nixos/unstable/release-notes.html#sec-release-22.05-notable-changes
    NIXOS_OZONE_WL = "1";
  };
}

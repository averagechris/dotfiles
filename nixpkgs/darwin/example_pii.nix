let
  userName = "<PUT_YOUR_USERNAME>";
in {
  inherit userName;
  homeDirectory = "/Users/${userName}";
}

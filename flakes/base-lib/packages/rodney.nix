{
  buildGoModule,
  lib,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "rodney";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "simonw";
    repo = pname;
    rev = "9e7ae93900bcb5316d02623706bc8861feec836f";
    hash = "sha256-/iGsaMfK8zeUkTXwU63mAAb4VpsllG87EH8ycoFZs5k=";
  };

  vendorHash = "sha256-h4U43W3hLoF+p25/jNRaW8okeEzAZQEmKtwB5l4kGW4=";

  subPackages = ["."];

  doCheck = false;

  meta = with lib; {
    description = "CLI for interacting with Chrome from agents and scripts";
    homepage = "https://github.com/simonw/rodney";
    license = licenses.asl20;
    mainProgram = "rodney";
    platforms = platforms.unix;
  };
}

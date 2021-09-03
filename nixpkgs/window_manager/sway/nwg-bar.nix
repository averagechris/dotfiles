{ lib
, buildGoModule
, fetchFromGitHub
, pkg-config
, cairo
, gobject-introspection
, gtk3
, gtk-layer-shell
}:

buildGoModule rec {
  pname = "nwg-bar";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "nwg-piotr";
    repo = pname;
    rev = "v${version}";
    sha256 = "1hmnl94i72xafdkvafssicwnd2bc82fahvvhg6761mra5p5cyidn";
  };

  vendorSha256 = "sha256-HyrjquJ91ddkyS8JijHd9HjtfwSQykXCufa2wzl8RNk=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ cairo gobject-introspection gtk3 gtk-layer-shell ];

  meta = with lib; {
    description = "GTK3-based button bar for sway and other wlroots-based compositors";
    homepage = "https://github.com/nwg-piotr/nwg-bar";
    license = licenses.mit;
    platforms = platforms.linux;
    # maintainers = with maintainers; [ plabadens ];
  };
}

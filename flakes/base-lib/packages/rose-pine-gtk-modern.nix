{
  fetchurl,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation rec {
  pname = "rose-pine-gtk-modern";
  version = "2.2.0";

  src = fetchurl {
    url = "https://github.com/rose-pine/gtk/archive/refs/tags/v${version}.tar.gz";
    # Verified with `nix store prefetch-file` against the upstream release archive.
    hash = "sha256-sfs1oWpaIIdH/dXSlRECudgPRwpUWnN2F1NYTyfg+Lc=";
  };

  installPhase = ''
    runHook preInstall

    for variant in rose-pine rose-pine-dawn rose-pine-moon; do
      gtk3Source="gtk3/$variant-gtk/gtk-3.0"
      theme="$out/share/themes/$variant"

      install -Dm644 "$gtk3Source/gtk.css" "$theme/gtk-3.0/gtk.css"
      install -Dm644 "$gtk3Source/gtk-dark.css" "$theme/gtk-3.0/gtk-dark.css"
      install -Dm644 "$gtk3Source/gtk.gresource" "$theme/gtk-3.0/gtk.gresource"
      install -Dm644 "gtk4/$variant.css" "$theme/gtk-4.0/gtk.css"
      install -Dm644 "gtk4/$variant.css" "$theme/gtk-4.0/gtk-dark.css"
    done

    runHook postInstall
  '';

  meta = {
    description = "Rosé Pine GTK 3 and GTK 4 themes without GTK 2 support";
    homepage = "https://github.com/rose-pine/gtk";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}

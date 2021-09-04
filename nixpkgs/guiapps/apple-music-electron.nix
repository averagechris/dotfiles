{ appimageTools, lib, fetchurl }:
let
  pname = "apple-music-electron";
  version = "2.5.0";
  name = "Apple.Music-${version}";

  src = fetchurl {
    url = "https://github.com/cryptofyre/Apple-Music-Electron/releases/download/v${version}/${name}.AppImage";
    sha256 = "18vvbmipcpddzsgp65arxcy8sdi3fn1dknkllmwy5kjdj5vd27lj";
  };

  appimageContents = appimageTools.extract { inherit name src; };
in
appimageTools.wrapType2 {
  inherit name src;

  # NOTE: the substituteInPlace to the .desktop file
  # adds ` -- ` before `--no-sandbox %U`
  # not sure if the argument should be omitted for passed through
  # 🤷🤷🤷
  # either way passing it through makes this work
  extraInstallCommands = ''
    mv $out/bin/${name} $out/bin/${pname}
    install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun' 'Exec=${pname} --'
    cp -r ${appimageContents}/usr/share/icons $out/share
  '';

  meta = with lib; {
    description = "Unofficial Apple Music application without having to bother with a Web Browser or iTunes";
    homepage = "https://github.com/iiFir3z/Apple-Music-Electron";
    license = licenses.mit;
    maintainers = [ maintainers.ivar ];
    platforms = [ "x86_64-linux" ];
  };
}

{ pkgs }: with pkgs; {
  video_compress = writeShellApplication {
    name = "video_compress";
    runtimeInputs = [ handbrake ];
    text = ''
      handbrake -i "$1" -o "$2" \
        -e x264 \
        -q 18 \
        -a 1,1 \
        -E faac,copy:ac3 \
        -B 256,256 \
        -6 dpl2,auto \
        -R Auto,Auto \
        -D 0.0,0.0 \
        -f mp4 \
        --detelecine \
        --decomb \
        --loose-anamorphic \
        -m \
        -x b-adapt=2:rc-lookahead=50
    '';
  };

  extract = writeShellApplication {
    name = "extract";
    runtimeInputs = [ gnutar bzip2 unrar unzip p7zip gzip ];
    text = ''
      if [ -f "$1" ] ; then
          case $1 in
              *.tar.bz2)   tar xjf "$1"     ;;
              *.tar.gz)    tar xzf "$1"     ;;
              *.bz2)       bzip2 "$1"       ;;
              *.rar)       unrar e "$1"     ;;
              *.gz)        gunzip "$1"      ;;
              *.tar)       tar xf "$1"      ;;
              *.tbz2)      tar xjf "$1"     ;;
              *.tgz)       tar xzf "$1"     ;;
              *.zip)       unzip "$1"       ;;
              *.Z)         uncompress "$1"  ;;
              *.7z)        7z x "$1"        ;;
              *)           echo "Missing extraction handler. \"$1\" cannot be extracted via extract()" >&2; return 2 ;;
          esac
      else
          echo "\"$1\" is not a valid file" >&2; return 1
      fi
    '';
  };

  rwhich = writeShellApplication {
    name = "rwhich";
    runtimeInputs = [ which ];
    text = ''readlink -f "$(which "$1")"'';
  };

  ph_find = writeShellApplication {
    name = "ph_find";
    runtimeInputs = [
      gnugrep
      fzf
      (callPackage ../passhole/passhole.nix { })
    ];
    text = ''
      ph show --field password "$(ph grep -i . | fzf)"
    '';
  };

  trim = writeShellApplication {
    name = "trim";
    runtimeInputs = [ gnused ];
    text = ''
      sed '/^$/d' \
        | sed -e 's/^ *//' \
        | sed -e 's/ *$//'
    '';
  };

}

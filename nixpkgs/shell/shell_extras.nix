{pkgs}:
with pkgs; rec {
  video_compress = writeShellApplication {
    name = "video_compress";
    runtimeInputs = [handbrake];
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
    runtimeInputs = [gnutar bzip2 unrar unzip p7zip gzip];
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
    runtimeInputs = [which];
    text = ''readlink -f "$(which "$1")"'';
  };

  ph_find = writeShellApplication {
    name = "ph_find";
    runtimeInputs = [
      gnugrep
      fzf
      (callPackage ../passhole/passhole.nix {})
    ];
    text = ''
      ph show --field password "$(ph grep -i . | fzf)"
    '';
  };

  trim = writeShellApplication {
    name = "trim";
    runtimeInputs = [gnused];
    text = ''
      sed '/^$/d' \
        | sed -e 's/^ *//' \
        | sed -e 's/ *$//'
    '';
  };

  list_systemd_services = writeShellApplication rec {
    name = "list_systemd_services";
    runtimeInputs = [bemenu fzf gawk];
    text = ''
      USER_OR_SYSTEM="user"
      FUZZY_FINDER="fzf --multi --exact --reverse --tiebreak=index"

      function echo_help () {
        echo "Usage: $0 [options]"
        echo Options:
        echo "  -h, --help      show this message"
        echo "  --user          passed to systemctl e.g. systemctl --user"
        echo "  --system        passed to systemctl e.g. systemctl --system"
        echo "  --fuzzy-finder  give an alternative fuzzy finder command"
        echo "                  defaults to: $FUZZY_FINDER"
        echo "                  bemenu is also supported. e.g."
        echo "                    ${name} --fuzzy-finder bemenu --ignorecase --center --margin 10 --list 10"
      }

      while [ $# -gt 0 ] && [ -n "$1" ]; do
        case "$1" in
          --help|-h)
            echo_help
            ;;
          --user|--system)
            USER_OR_SYSTEM="$1"
            ;;
          --fuzzy-finder)
            shift
            FUZZY_FINDER="$*"
            break
            ;;
          *)
            echo_help
            ;;
        esac

      if [ $# -gt 0 ]; then
         shift
      fi

      done

      systemctl "--$USER_OR_SYSTEM" list-unit-files --type=service --no-legend \
        | eval -- "$FUZZY_FINDER" \
        | awk '{print $1}'

    '';
  };

  bemenu_list_systemd_services = writeShellApplication {
    name = "bemenu_list_systemd_services";
    runtimeInputs = [list_systemd_services];
    text = "list_systemd_services --fuzzy-finder bemenu --ignorecase --center --margin 10 --list 10";
  };

  try_restart_systemd_user_services = writeShellApplication {
    name = "try_restart_systemd_user_services";
    runtimeInputs = [list_systemd_services];
    text = ''
      CHOICES="$(list_systemd_services "$@")"
      if [ -n "$CHOICES" ]; then
        systemctl --user try-restart "$CHOICES"
      fi
    '';
  };

  bemenu_try_restart_systemd_user_services = writeShellApplication {
    name = "bemenu_try_restart_systemd_user_services";
    runtimeInputs = [try_restart_systemd_user_services];
    text = "try_restart_systemd_user_services --fuzzy-finder bemenu --ignorecase --center --margin 10 --list 10";
  };
}

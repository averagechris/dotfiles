{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.audioOutput;

  audioOutput = pkgs.rustPlatform.buildRustPackage {
    pname = "audio-output";
    version = "0.1.0";
    src = ./audio-output-rs;

    cargoLock = {
      lockFile = ./audio-output-rs/Cargo.lock;
      outputHashes = {};
    };

    nativeBuildInputs = with pkgs; [makeWrapper];

    postFixup = ''
      wrapProgram $out/bin/audio-output \
        --prefix PATH : ${lib.makeBinPath [
        pkgs.fzf
        pkgs.libnotify
        pkgs.pulseaudio
        pkgs.wofi
      ]}
    '';

    meta = {
      description = "Opinionated PipeWire/PulseAudio output router";
      license = lib.licenses.mit;
    };
  };
in {
  options.dotfiles.audioOutput = {
    enable = lib.mkEnableOption "friendly PipeWire/PulseAudio output switching helper";

    daemon.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run audio-output as a user service that enforces the selected output for new streams.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [audioOutput];

    systemd.user.services.audio-output = lib.mkIf cfg.daemon.enable {
      Unit = {
        Description = "Enforce global PipeWire/PulseAudio output routing";
        After = ["pipewire-pulse.service" "wireplumber.service"];
        PartOf = ["graphical-session.target"];
      };

      Service = {
        ExecStart = "${audioOutput}/bin/audio-output daemon";
        Restart = "on-failure";
        RestartSec = 2;
      };

      Install.WantedBy = ["graphical-session.target"];
    };
  };
}

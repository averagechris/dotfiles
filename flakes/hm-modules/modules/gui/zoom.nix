{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.zoom;
in
  with lib; {
    options.programs.zoom = {
      enable = mkEnableOption "Enable zoom patched to work on wayland + sway";
    };

    config = mkIf cfg.enable {
      home.packages = [
        pkgs.zoom
      ];

      xdg.configFile."zoomus.conf".text = ''
        [General]
        GeoLocale=system
        SensitiveInfoMaskOn=true
        autoPlayGif=false
        autoScale=true
        bForceMaximizeWM=false
        blockUntrustedSSLCert=false
        captureHDCamera=true
        chatListPanelLastWidth=230
        conf.webserver=https://us06web.zoom.us
        conf.webserver.vendor.default=https://zoom.us
        enable.host.auto.grab=true
        enableAlphaBuffer=true
        enableCloudSwitch=false
        enableLog=true
        enableMiniWindow=true
        enableQmlCache=true
        enableScreenSaveGuard=false
        enableStartMeetingWithRoomSystem=false
        enableTestMode=false
        enableWaylandShare=True
        enablegpucomputeutilization=false
        fake.version=
        flashChatTime=0
        forceEnableTrayIcon=true
        forceSSOURL=
        host.auto.grab.interval=10
        isTransCoding=false
        logLevel=info
        newMeetingWithVideo=true
        playSoundForNewMessage=false
        scaleFactor=1
        shareBarTopMargin=0
        sso_domain=.zoom.us
        sso_gov_domain=.zoomgov.com
        system.audio.type=default
        timeFormat12HoursEnable=true
        upcoming_meeting_header_image=
        useSystemTheme=false

        [AS]
        showframewindow=true

        [chat.recent]
        recentlast.session=

        [zoom_new_im]
        is_landscape_mode=true
        main_frame_pixel_pos_narrow="376,680"
        main_frame_pixel_pos_wide="1908,2120"
      '';
    };
  }

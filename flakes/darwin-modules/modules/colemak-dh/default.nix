{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.colemakDh;
  bundleSource = ./colemak-mdh-bundle;
  bundleDestination = "/Library/Keyboard Layouts/Colemak mDH.bundle";
  currentInputSourceID = "io.github.colemakmods.keyboardlayout.colemakdh.colemakdhansi-extended";
  layoutName = "Colemak DH ANSI - Extended";
  layoutID = -25869;

  colemakSourceXml = ''
    <dict>
      <key>InputSourceKind</key>
      <string>Keyboard Layout</string>
      <key>KeyboardLayout ID</key>
      <integer>${toString layoutID}</integer>
      <key>KeyboardLayout Name</key>
      <string>${layoutName}</string>
    </dict>'';

  usSourceXml = ''
    <dict>
      <key>InputSourceKind</key>
      <string>Keyboard Layout</string>
      <key>KeyboardLayout ID</key>
      <integer>0</integer>
      <key>KeyboardLayout Name</key>
      <string>U.S.</string>
    </dict>'';

  enabledInputSourcesXml = ''
    <array>
    ${usSourceXml}
    ${colemakSourceXml}
    </array>'';

  selectedInputSourcesXml = ''
    <array>
    ${colemakSourceXml}
    </array>'';

  # Writes go through `defaults` (and therefore cfprefsd) instead of editing
  # plist files directly, and complex values are passed as XML property list
  # fragments so integer types are preserved.
  setInputSources = defaultsCmd: domain: ''
    ${defaultsCmd} write ${domain} AppleEnabledInputSources ${lib.escapeShellArg enabledInputSourcesXml}
    ${defaultsCmd} write ${domain} AppleSelectedInputSources ${lib.escapeShellArg selectedInputSourcesXml}
    ${defaultsCmd} write ${domain} AppleCurrentKeyboardLayoutInputSourceID ${lib.escapeShellArg currentInputSourceID}
  '';
in {
  options.dotfiles.colemakDh.enable = lib.mkEnableOption "Colemak Mod-DH keyboard layout bundle and input source defaults";

  config = lib.mkIf cfg.enable {
    system.requiresPrimaryUser = ["dotfiles.colemakDh.enable"];

    # NOTE: nix-darwin only runs a fixed set of activation script fragments
    # (preActivation, extraActivation, postActivation, ...); arbitrary
    # attribute names are silently ignored, so this must extend one of them.
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      # dotfiles.colemakDh: Colemak Mod-DH keyboard layout
      colemak_source_bundle=${lib.escapeShellArg "${bundleSource}"}
      colemak_target_bundle=${lib.escapeShellArg bundleDestination}

      if [ ! -d "$colemak_target_bundle" ] || ! /usr/bin/diff -qr "$colemak_source_bundle" "$colemak_target_bundle" >/dev/null 2>&1; then
        echo "installing Colemak Mod-DH keyboard layout bundle" >&2
        /bin/rm -rf "$colemak_target_bundle"
        /bin/mkdir -p "$(/usr/bin/dirname "$colemak_target_bundle")"
        /bin/cp -R "$colemak_source_bundle" "$colemak_target_bundle"
      fi
      # Outside the content guard so ownership is normalized even when a
      # pre-nix install left identical content owned by a regular user.
      /usr/sbin/chown -R root:wheel "$colemak_target_bundle"
      /bin/chmod -R u=rwX,go=rX "$colemak_target_bundle"

      # Login screen (system) level. Only seeded when the Colemak layout is
      # missing so activations do not clobber input sources added later.
      if ! /usr/bin/defaults read /Library/Preferences/com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | /usr/bin/grep -qF ${lib.escapeShellArg layoutName}; then
        echo "enabling Colemak Mod-DH for the login screen" >&2
        ${setInputSources "/usr/bin/defaults" "/Library/Preferences/com.apple.HIToolbox"}
      fi

      # Primary user level. Same guard: seed once, then leave the domain
      # alone so runtime layout switching is not fought by rebuilds.
      colemak_user=${lib.escapeShellArg config.system.primaryUser}
      colemak_uid=$(/usr/bin/id -u -- "$colemak_user")
      if ! /bin/launchctl asuser "$colemak_uid" /usr/bin/sudo --user="$colemak_user" -- /usr/bin/defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | /usr/bin/grep -qF ${lib.escapeShellArg layoutName}; then
        echo "seeding Colemak Mod-DH input sources for $colemak_user" >&2
        ${setInputSources ''/bin/launchctl asuser "$colemak_uid" /usr/bin/sudo --user="$colemak_user" -- /usr/bin/defaults'' "com.apple.HIToolbox"}
      fi
    '';
  };
}

# Audio output switching

Linux audio is managed with PipeWire and WirePlumber. The system module enables
PipeWire, PulseAudio compatibility, and a WirePlumber policy that ranks output
devices in this order:

1. Headphones / headset outputs
2. USB speakers, including AudioEngine-style USB DACs
3. HDMI / DisplayPort / monitor audio
4. Built-in laptop speakers

Bluetooth headphone outputs, including AirPods/AirPods Pro, are treated as
headphones and get the highest WirePlumber priority when connected.

WirePlumber uses these priorities for automatic default-output selection when
devices appear or disappear. Existing applications can still keep playing to an
old sink, so the Home Manager shell module also installs `audio-output`.

## `audio-output` helper and daemon

`audio-output` is a Rust CLI that wraps `pactl` with friendlier names. Selecting
an output saves it as the desired global output, sets the PipeWire/PulseAudio
default sink, and moves existing streams there.

Home Manager also starts `audio-output daemon` as a user service. The daemon
watches `pactl subscribe` events and enforces the selected global output for new
streams. This fixes the surprising browser/Electron case where paused playback
destroys its audio stream and pressing play later creates a new stream on an old
output.

```bash
audio-output status      # show default sink and classified outputs
audio-output list        # alias for status
audio-output pick        # choose an output with fzf
audio-output menu        # choose an output with a graphical wofi menu
audio-output headphones  # switch to headphones / headset
audio-output speakers    # switch to USB speakers / AudioEngine
audio-output monitor     # switch to HDMI or DisplayPort audio
audio-output laptop      # switch to built-in speakers
audio-output cycle       # cycle headphones -> speakers -> monitor -> laptop
audio-output daemon-status
audio-output streams     # show active playback streams and app names
```

The selected output and overrides are stored at
`$XDG_STATE_HOME/audio-output/state`.

## Dynamic overrides

Most streams follow the global output. If an app should use a different output,
add a dynamic override:

```bash
audio-output speakers
audio-output override add zoom headphones
audio-output override add spotify speakers
audio-output override list
audio-output override remove zoom
audio-output override clear
```

Overrides match case-insensitive substrings across stream metadata such as
`application.name`, `application.process.binary`, and media names. The daemon
applies overrides to both existing streams and newly-created streams.

Example: keep the system/global output on USB speakers, but force Zoom calls to
headphones:

```bash
audio-output speakers
audio-output override add zoom headphones
```

The helper classifies sinks from their PulseAudio/PipeWire sink name and
description. Explicit AudioEngine identity is treated as USB speakers, but
generic headset/headphone/earbud labels and Bluetooth `bluez_output` sinks win
over generic USB audio. This means a new USB or Bluetooth headset should
classify as headphones by default, while generic USB DACs without headset labels
classify as speakers. If a device is misclassified, inspect the current names
with:

```bash
audio-output status
pactl list sinks short
```

Then update the matching patterns in
`flakes/hm-modules/modules/shell-modules/audio-output-rs/src/main.rs` and the
related WirePlumber priority rules in `flakes/nixos-modules/modules/sound.nix`.

## Bluetooth audio quality

The WirePlumber Bluetooth policy enables common higher-quality playback codecs
in preference order: LDAC, aptX HD, aptX, AAC, SBC-XQ, then SBC. AirPods and
AirPods Pro should normally use AAC/A2DP for good playback quality.

Bluetooth has one unavoidable caveat: using the headset microphone usually
switches the device from the high-quality A2DP playback profile to a headset
profile (`HFP/HSP`) with lower playback quality. For best music/video audio while
on calls, prefer a separate microphone when possible, or configure the call app
to use the laptop/webcam mic while headphones remain on the high-quality playback
profile.

Useful checks:

```bash
wpctl status
pactl list cards
```

Look for the Bluetooth card's active profile. For listening, prefer an A2DP
profile. For headset microphone use, expect HFP/HSP quality tradeoffs.

## Eww widget

The Eww volume widget includes the current output class next to the volume:

- `HP` - headphones / headset
- `USB` - USB speakers
- `MON` - monitor audio
- `LAP` - laptop speakers
- `OUT` - unknown output

Controls:

| Action | Effect |
| --- | --- |
| Scroll volume widget | Adjust volume |
| Click volume icon/percent | Toggle mute |
| Click output label | Cycle output |
| Right-click output label | Open graphical output chooser |

Use `audio-output speakers` as the quick recovery command when audio gets stuck
on the monitor or laptop speakers. With the daemon running, future streams also
follow that choice until another `audio-output` command changes it.

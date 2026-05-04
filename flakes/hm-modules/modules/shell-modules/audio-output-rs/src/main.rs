use anyhow::{anyhow, bail, Context, Result};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

#[derive(Clone, Debug, Eq, PartialEq)]
enum Target {
    Headphones,
    Speakers,
    Monitor,
    Laptop,
    Other,
}

impl Target {
    fn parse(value: &str) -> Option<Self> {
        match value.to_ascii_lowercase().as_str() {
            "headphones" | "headphone" | "headset" | "hp" => Some(Self::Headphones),
            "speakers" | "speaker" | "usb" | "usb-speakers" => Some(Self::Speakers),
            "monitor" | "hdmi" | "displayport" => Some(Self::Monitor),
            "laptop" | "builtin" | "built-in" => Some(Self::Laptop),
            "other" => Some(Self::Other),
            _ => None,
        }
    }

    fn as_str(&self) -> &'static str {
        match self {
            Self::Headphones => "headphones",
            Self::Speakers => "speakers",
            Self::Monitor => "monitor",
            Self::Laptop => "laptop",
            Self::Other => "other",
        }
    }

    fn label(&self) -> &'static str {
        match self {
            Self::Headphones => "󰋋 HP",
            Self::Speakers => "󰓃 USB",
            Self::Monitor => "󰍹 MON",
            Self::Laptop => "󰌢 LAP",
            Self::Other => "󰕾 OUT",
        }
    }
}

#[derive(Clone, Debug)]
struct Sink {
    id: String,
    name: String,
    description: String,
    target: Target,
}

#[derive(Clone, Debug)]
struct Stream {
    id: String,
    sink_id: String,
    props: BTreeMap<String, String>,
}

#[derive(Clone, Debug)]
struct Override {
    pattern: String,
    target: Target,
}

#[derive(Clone, Debug)]
struct State {
    enabled: bool,
    target: Target,
    overrides: Vec<Override>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            enabled: true,
            target: Target::Speakers,
            overrides: vec![],
        }
    }
}

fn main() -> Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("status");
    match cmd {
        "status" | "list" => print_status(),
        "pick" => pick(),
        "menu" => menu(),
        "daemon" => daemon(),
        "daemon-status" => daemon_status(),
        "eww-label" => eww_label(),
        "set" => set_target(args.get(1).ok_or_else(|| anyhow!("missing target"))?),
        "cycle" => cycle(),
        "override" => override_cmd(&args[1..]),
        "streams" => print_streams(),
        "help" | "-h" | "--help" => {
            usage();
            Ok(())
        }
        value if Target::parse(value).is_some() => set_target(value),
        _ => {
            usage();
            bail!("unknown command: {cmd}")
        }
    }
}

fn usage() {
    println!("Usage: audio-output <command>\n\nCommands:\n  status, list\n  pick\n  menu\n  set <speakers|headphones|monitor|laptop>\n  speakers|headphones|monitor|laptop\n  cycle\n  daemon\n  daemon-status\n  streams\n  override add <pattern> <target>\n  override remove <pattern>\n  override list\n  override clear");
}

fn run(cmd: &str, args: &[&str]) -> Result<String> {
    let out = Command::new(cmd)
        .args(args)
        .output()
        .with_context(|| format!("running {cmd}"))?;
    if !out.status.success() {
        bail!("{cmd} failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

fn pactl(args: &[&str]) -> Result<String> {
    run("pactl", args)
}

fn state_path() -> PathBuf {
    env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("audio-output/state")
}

fn read_state() -> State {
    let Ok(text) = fs::read_to_string(state_path()) else {
        return current_state_default();
    };
    parse_state(&text)
}

fn parse_state(text: &str) -> State {
    let mut state = State::default();
    for line in text.lines() {
        if let Some(v) = line.strip_prefix("enabled=") {
            state.enabled = v == "true";
        }
        if let Some(v) = line.strip_prefix("target=").and_then(Target::parse) {
            state.target = v;
        }
        if let Some(v) = line.strip_prefix("override=") {
            if let Some((pat, tgt)) = v
                .split_once('\t')
                .and_then(|(p, t)| Target::parse(t).map(|t| (p, t)))
            {
                state.overrides.push(Override {
                    pattern: pat.to_string(),
                    target: tgt,
                });
            }
        }
    }
    state
}

fn current_state_default() -> State {
    let target = sinks()
        .ok()
        .and_then(|all| {
            default_sink_name()
                .ok()
                .and_then(|name| all.into_iter().find(|s| s.name == name))
        })
        .map(|s| s.target)
        .unwrap_or(Target::Speakers);
    State {
        target,
        ..State::default()
    }
}

fn write_state(state: &State) -> Result<()> {
    let path = state_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, format_state(state))?;
    Ok(())
}

fn format_state(state: &State) -> String {
    let mut text = format!(
        "enabled={}\ntarget={}\n",
        state.enabled,
        state.target.as_str()
    );
    for o in &state.overrides {
        text.push_str(&format!("override={}\t{}\n", o.pattern, o.target.as_str()));
    }
    text
}

fn default_sink_name() -> Result<String> {
    pactl(&["info"])?
        .lines()
        .find_map(|l| l.strip_prefix("Default Sink: ").map(str::to_string))
        .ok_or_else(|| anyhow!("no default sink"))
}

fn classify(name: &str, description: &str) -> Target {
    let h = format!("{name} {description}").to_ascii_lowercase();
    if h.contains("audioengine") {
        Target::Speakers
    } else if h.contains("headphone")
        || h.contains("headset")
        || h.contains("earbud")
        || h.contains("airpod")
        || h.contains("airpods")
        || h.contains("bluez_output")
    {
        Target::Headphones
    } else if h.contains("usb audio") || h.contains("alsa_output.usb") {
        Target::Speakers
    } else if h.contains("hdmi")
        || h.contains("displayport")
        || h.contains("display port")
        || h.contains("monitor")
    {
        Target::Monitor
    } else if h.contains("built-in")
        || h.contains("speaker")
        || (h.contains("pci") && h.contains("analog"))
    {
        Target::Laptop
    } else {
        Target::Other
    }
}

fn sinks() -> Result<Vec<Sink>> {
    let short = pactl(&["list", "sinks", "short"])?;
    let detail = pactl(&["list", "sinks"])?;
    let mut out = vec![];
    for line in short.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 2 {
            continue;
        }
        let id = fields[0].to_string();
        let name = fields[1].to_string();
        let desc = description_for_sink(&detail, &name).unwrap_or_else(|| name.clone());
        let target = classify(&name, &desc);
        out.push(Sink {
            id,
            name,
            description: desc,
            target,
        });
    }
    Ok(out)
}

fn description_for_sink(detail: &str, name: &str) -> Option<String> {
    let mut in_sink = false;
    for line in detail.lines() {
        let t = line.trim();
        if t.starts_with("Sink #") {
            in_sink = false;
        }
        if t == format!("Name: {name}") {
            in_sink = true;
        }
        if in_sink {
            if let Some(v) = t.strip_prefix("Description: ") {
                return Some(v.to_string());
            }
        }
    }
    None
}

fn find_sink(target: &Target) -> Result<Sink> {
    sinks()?
        .into_iter()
        .find(|s| &s.target == target)
        .ok_or_else(|| anyhow!("no {} output found", target.as_str()))
}

fn sink_by_name(name: &str) -> Result<Sink> {
    sinks()?
        .into_iter()
        .find(|s| s.name == name)
        .ok_or_else(|| anyhow!("sink disappeared: {name}"))
}

fn set_target(value: &str) -> Result<()> {
    let target = Target::parse(value).ok_or_else(|| anyhow!("unknown target: {value}"))?;
    let mut state = read_state();
    state.target = target.clone();
    state.enabled = true;
    write_state(&state)?;
    let sink = find_sink(&target)?;
    enforce(&state, Some(&sink))?;
    notify("Audio output", &sink.description).ok();
    println!("Audio output: {}", sink.description);
    Ok(())
}

fn enforce(state: &State, forced_sink: Option<&Sink>) -> Result<()> {
    if !state.enabled {
        return Ok(());
    }
    let global = match forced_sink {
        Some(s) => s.clone(),
        None => find_sink(&state.target)?,
    };
    pactl(&["set-default-sink", &global.name]).ok();
    for stream in streams()? {
        let target = override_target(state, &stream).unwrap_or_else(|| state.target.clone());
        let sink = if target == state.target {
            global.clone()
        } else {
            find_sink(&target)?
        };
        if stream.sink_id != sink.id && stream.sink_id != sink.name {
            pactl(&["move-sink-input", &stream.id, &sink.name]).ok();
        }
    }
    Ok(())
}

fn streams() -> Result<Vec<Stream>> {
    let short = pactl(&["list", "sink-inputs", "short"])?;
    let detail = pactl(&["list", "sink-inputs"])?;
    let mut out = vec![];
    for line in short.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 2 {
            continue;
        }
        out.push(Stream {
            id: fields[0].to_string(),
            sink_id: fields[1].to_string(),
            props: props_for_stream(&detail, fields[0]),
        });
    }
    Ok(out)
}

fn props_for_stream(detail: &str, id: &str) -> BTreeMap<String, String> {
    let mut props = BTreeMap::new();
    let mut in_stream = false;
    for line in detail.lines() {
        let t = line.trim();
        if t.starts_with("Sink Input #") {
            in_stream = t == format!("Sink Input #{id}");
        }
        if in_stream {
            if let Some((k, v)) = t.split_once(" = ") {
                props.insert(k.to_string(), v.trim_matches('"').to_string());
            }
        }
    }
    props
}

fn override_target(state: &State, stream: &Stream) -> Option<Target> {
    let haystack = stream
        .props
        .values()
        .cloned()
        .collect::<Vec<_>>()
        .join(" ")
        .to_ascii_lowercase();
    state
        .overrides
        .iter()
        .find(|o| haystack.contains(&o.pattern.to_ascii_lowercase()))
        .map(|o| o.target.clone())
}

fn print_status() -> Result<()> {
    let default = default_sink_name()?;
    let all = sinks()?;
    let desc = all
        .iter()
        .find(|s| s.name == default)
        .map(|s| s.description.as_str())
        .unwrap_or(&default);
    println!("Default: {desc}\n\nOutputs:");
    for s in all {
        let mark = if s.name == default { "*" } else { " " };
        println!(" {mark} {:<12} {}", s.target.as_str(), s.description);
    }
    Ok(())
}

fn pick() -> Result<()> {
    let default = default_sink_name().unwrap_or_default();
    let mut input = String::new();
    for s in sinks()? {
        let mark = if s.name == default { "*" } else { " " };
        input.push_str(&format!(
            "{mark}\t{}\t{}\t{}\t{}\n",
            s.target.as_str(),
            s.id,
            s.name,
            s.description
        ));
    }
    let mut child = Command::new("fzf")
        .args([
            "--height",
            "40%",
            "--reverse",
            "--prompt",
            "audio output> ",
            "--header",
            "Enter: switch output, Esc: cancel",
            "--with-nth",
            "1,2,5",
            "--delimiter",
            "\t",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .context("starting fzf")?;
    child.stdin.as_mut().unwrap().write_all(input.as_bytes())?;
    let out = child.wait_with_output()?;
    if !out.status.success() {
        return Ok(());
    }
    let line = String::from_utf8_lossy(&out.stdout);
    let fields: Vec<&str> = line.trim_end().split('\t').collect();
    if fields.len() >= 4 {
        let mut state = read_state();
        state.target = Target::parse(fields[1]).unwrap_or(Target::Other);
        state.enabled = true;
        write_state(&state)?;
        let sink = sink_by_name(fields[3])?;
        enforce(&state, Some(&sink))?;
        println!("Audio output: {}", sink.description);
    }
    Ok(())
}

fn menu() -> Result<()> {
    let default = default_sink_name().unwrap_or_default();
    let mut input = String::new();
    for s in sinks()? {
        let mark = if s.name == default { "●" } else { "○" };
        input.push_str(&format!(
            "{mark} {:<10} {}\t{}\t{}\n",
            s.target.as_str(),
            s.description,
            s.target.as_str(),
            s.name
        ));
    }

    let selection = if command_exists("wofi") {
        menu_with(
            "wofi",
            &[
                "--dmenu",
                "--prompt",
                "Audio output",
                "--width",
                "720",
                "--height",
                "360",
                "--insensitive",
            ],
            &input,
        )?
    } else {
        return pick();
    };

    if selection.trim().is_empty() {
        return Ok(());
    }

    let fields: Vec<&str> = selection.trim_end().split('\t').collect();
    if fields.len() >= 3 {
        let mut state = read_state();
        state.target = Target::parse(fields[1]).unwrap_or(Target::Other);
        state.enabled = true;
        write_state(&state)?;
        let sink = sink_by_name(fields[2])?;
        enforce(&state, Some(&sink))?;
        notify("Audio output", &sink.description).ok();
    }
    Ok(())
}

fn command_exists(command: &str) -> bool {
    Command::new("sh")
        .args(["-c", &format!("command -v {command} >/dev/null 2>&1")])
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn menu_with(command: &str, args: &[&str], input: &str) -> Result<String> {
    let mut child = Command::new(command)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .with_context(|| format!("starting {command}"))?;
    child.stdin.as_mut().unwrap().write_all(input.as_bytes())?;
    let out = child.wait_with_output()?;
    if !out.status.success() {
        return Ok(String::new());
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

fn cycle() -> Result<()> {
    let current = sinks()?
        .into_iter()
        .find(|s| default_sink_name().ok().as_deref() == Some(&s.name))
        .map(|s| s.target)
        .unwrap_or(Target::Other);
    let next = match current {
        Target::Headphones => Target::Speakers,
        Target::Speakers => Target::Monitor,
        Target::Monitor => Target::Laptop,
        _ => Target::Headphones,
    };
    set_target(next.as_str())
        .or_else(|_| set_target("speakers"))
        .or_else(|_| set_target("monitor"))
        .or_else(|_| set_target("laptop"))
}

fn daemon() -> Result<()> {
    println!(
        "audio-output daemon enforcing global output; state={}",
        state_path().display()
    );
    enforce(&read_state(), None).ok();
    let mut child = Command::new("pactl")
        .args(["subscribe"])
        .stdout(Stdio::piped())
        .spawn()
        .context("starting pactl subscribe")?;
    let stdout = child.stdout.take().context("pactl stdout")?;
    for line in BufReader::new(stdout).lines() {
        let line = line.unwrap_or_default();
        if line.contains("sink-input")
            || line.contains("sink")
            || line.contains("card")
            || line.contains("server")
        {
            thread::sleep(Duration::from_millis(100));
            enforce(&read_state(), None).ok();
        }
    }
    Ok(())
}

fn daemon_status() -> Result<()> {
    let state = read_state();
    println!("Enabled: {}", state.enabled);
    println!("Global target: {}", state.target.as_str());
    println!("Overrides:");
    for o in state.overrides {
        println!("  {} -> {}", o.pattern, o.target.as_str());
    }
    Ok(())
}

fn override_cmd(args: &[String]) -> Result<()> {
    let sub = args.first().map(String::as_str).unwrap_or("list");
    let mut state = read_state();
    match sub {
        "add" => {
            let pattern = args
                .get(1)
                .ok_or_else(|| anyhow!("missing pattern"))?
                .to_string();
            let target = Target::parse(args.get(2).ok_or_else(|| anyhow!("missing target"))?)
                .ok_or_else(|| anyhow!("unknown target"))?;
            state.overrides.retain(|o| o.pattern != pattern);
            state.overrides.push(Override { pattern, target });
            write_state(&state)?;
            enforce(&state, None).ok();
        }
        "remove" => {
            let pattern = args.get(1).ok_or_else(|| anyhow!("missing pattern"))?;
            state.overrides.retain(|o| &o.pattern != pattern);
            write_state(&state)?;
        }
        "clear" => {
            state.overrides.clear();
            write_state(&state)?;
        }
        "list" => {
            for o in state.overrides {
                println!("{} -> {}", o.pattern, o.target.as_str());
            }
        }
        _ => bail!("unknown override command"),
    }
    Ok(())
}

fn print_streams() -> Result<()> {
    for s in streams()? {
        let app = s
            .props
            .get("application.name")
            .or_else(|| s.props.get("application.process.binary"))
            .cloned()
            .unwrap_or_else(|| "unknown".into());
        println!("{}\t{}\t{}", s.id, s.sink_id, app);
    }
    Ok(())
}

fn eww_label() -> Result<()> {
    let state = read_state();
    let sink = find_sink(&state.target).or_else(|_| {
        sinks()?
            .into_iter()
            .find(|s| s.name == default_sink_name().unwrap_or_default())
            .ok_or_else(|| anyhow!("no sink"))
    })?;
    let suffix = if state.overrides.is_empty() { "" } else { "*" };
    println!("{}{}", sink.target.label(), suffix);
    Ok(())
}

fn notify(summary: &str, body: &str) -> Result<()> {
    run("notify-send", &["-a", "audio-output", summary, body]).map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_target_aliases() {
        assert_eq!(Target::parse("hp"), Some(Target::Headphones));
        assert_eq!(Target::parse("usb"), Some(Target::Speakers));
        assert_eq!(Target::parse("HDMI"), Some(Target::Monitor));
        assert_eq!(Target::parse("built-in"), Some(Target::Laptop));
        assert_eq!(Target::parse("wat"), None);
    }

    #[test]
    fn classifies_audioengine_usb_before_misleading_headset_description() {
        let target = classify(
            "alsa_output.usb-Audioengine_Audioengine_HD3_B40020170802-00.analog-stereo",
            "CSRA64210 [TaoTronics Headset BH-22 in charging mode] Analog Stereo",
        );

        assert_eq!(target, Target::Speakers);
    }

    #[test]
    fn classifies_generic_usb_headset_as_headphones() {
        let target = classify(
            "alsa_output.usb-Example_USB_Headset-00.analog-stereo",
            "Example USB Headset Analog Stereo",
        );

        assert_eq!(target, Target::Headphones);
    }

    #[test]
    fn classifies_generic_usb_audio_without_headset_as_speakers() {
        let target = classify(
            "alsa_output.usb-Generic_USB_Audio-00.analog-stereo",
            "Generic USB Audio Analog Stereo",
        );

        assert_eq!(target, Target::Speakers);
    }

    #[test]
    fn classifies_common_outputs() {
        assert_eq!(
            classify(
                "alsa_output.pci-0000_c3_00.1.HiFi__HDMI4__sink",
                "Radeon HDMI / DisplayPort Output"
            ),
            Target::Monitor
        );
        assert_eq!(
            classify(
                "alsa_output.pci-0000_c3_00.6.HiFi__Speaker__sink",
                "Ryzen HD Audio Controller Speaker"
            ),
            Target::Laptop
        );
        assert_eq!(
            classify("bluez_output.foo", "Sony Headphones"),
            Target::Headphones
        );
        assert_eq!(
            classify("bluez_output.11_22_33_44_55_66.1", "Chris's AirPods Pro"),
            Target::Headphones
        );
    }

    #[test]
    fn parses_sink_description_from_pactl_detail() {
        let detail = r#"
Sink #1
    State: SUSPENDED
    Name: alsa_output.monitor
    Description: Monitor Output
Sink #2
    State: SUSPENDED
    Name: alsa_output.usb-Audioengine_HD3.analog-stereo
    Description: CSRA64210 [TaoTronics Headset BH-22 in charging mode] Analog Stereo
"#;

        assert_eq!(
            description_for_sink(detail, "alsa_output.usb-Audioengine_HD3.analog-stereo"),
            Some("CSRA64210 [TaoTronics Headset BH-22 in charging mode] Analog Stereo".into())
        );
        assert_eq!(description_for_sink(detail, "missing"), None);
    }

    #[test]
    fn parses_stream_properties_for_only_requested_stream() {
        let detail = r#"
Sink Input #10
    Properties:
        application.name = "Zoom"
        media.name = "call"
Sink Input #11
    Properties:
        application.name = "Helium"
        application.process.binary = "helium"
"#;

        let props = props_for_stream(detail, "11");
        assert_eq!(props.get("application.name"), Some(&"Helium".to_string()));
        assert_eq!(
            props.get("application.process.binary"),
            Some(&"helium".to_string())
        );
        assert!(!props.values().any(|value| value == "Zoom"));
    }

    #[test]
    fn override_matching_is_case_insensitive_across_metadata() {
        let state = State {
            enabled: true,
            target: Target::Speakers,
            overrides: vec![Override {
                pattern: "zoom".into(),
                target: Target::Headphones,
            }],
        };
        let stream = Stream {
            id: "42".into(),
            sink_id: "1".into(),
            props: BTreeMap::from([("application.name".into(), "Zoom Workplace".into())]),
        };

        assert_eq!(override_target(&state, &stream), Some(Target::Headphones));
    }

    #[test]
    fn state_round_trips_to_line_format() {
        let original = State {
            enabled: true,
            target: Target::Speakers,
            overrides: vec![
                Override {
                    pattern: "zoom".into(),
                    target: Target::Headphones,
                },
                Override {
                    pattern: "spotify".into(),
                    target: Target::Speakers,
                },
            ],
        };

        let text = format_state(&original);
        let parsed = parse_state(&text);

        assert!(parsed.enabled);
        assert_eq!(parsed.target, Target::Speakers);
        assert_eq!(parsed.overrides.len(), 2);
        assert_eq!(parsed.overrides[0].pattern, "zoom");
        assert_eq!(parsed.overrides[0].target, Target::Headphones);
        assert_eq!(parsed.overrides[1].pattern, "spotify");
        assert_eq!(parsed.overrides[1].target, Target::Speakers);
    }

    #[test]
    fn parse_state_ignores_invalid_targets_and_overrides() {
        let parsed = parse_state(
            "enabled=false\ntarget=nonsense\noverride=zoom\tbogus\noverride=helium\tspeakers\n",
        );

        assert!(!parsed.enabled);
        assert_eq!(parsed.target, Target::Speakers);
        assert_eq!(parsed.overrides.len(), 1);
        assert_eq!(parsed.overrides[0].pattern, "helium");
        assert_eq!(parsed.overrides[0].target, Target::Speakers);
    }

    #[test]
    fn graphical_menu_selection_keeps_hidden_target_and_sink_fields() {
        let line = "● speakers   CSRA64210 [TaoTronics Headset BH-22 in charging mode] Analog Stereo\tspeakers\talsa_output.usb-Audioengine.analog-stereo";
        let fields: Vec<&str> = line.split('\t').collect();

        assert_eq!(fields.len(), 3);
        assert_eq!(Target::parse(fields[1]), Some(Target::Speakers));
        assert_eq!(fields[2], "alsa_output.usb-Audioengine.analog-stereo");
    }
}

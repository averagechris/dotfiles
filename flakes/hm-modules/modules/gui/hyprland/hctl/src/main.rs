use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    env, fs,
    io::{BufRead, BufReader},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::Duration,
};

static DRY_RUN: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    #[serde(default)]
    apps: BTreeMap<String, AppConfig>,
    #[serde(default)]
    workspaces: BTreeMap<String, WorkspaceConfig>,
    #[serde(default)]
    smart_gaps: SmartGapsConfig,
    #[serde(default)]
    eww: EwwConfig,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppConfig {
    #[serde(default)]
    r#match: MatchConfig,
    #[serde(default)]
    launch: Vec<String>,
    #[serde(default)]
    home_workspace: Option<String>,
    #[serde(default)]
    summon: ActionConfig,
    #[serde(default)]
    hide: HideConfig,
    #[serde(default)]
    borrow: ActionConfig,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MatchConfig {
    class: Option<String>,
    title: Option<String>,
    initial_class: Option<String>,
    initial_title: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ActionConfig {
    #[serde(default)]
    enabled: bool,
    #[serde(default)]
    floating: bool,
    #[serde(default)]
    center: bool,
    #[serde(default)]
    size: Option<Size>,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Deserialize)]
struct Size {
    width: i64,
    height: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HideConfig {
    #[serde(default)]
    enabled: bool,
    #[serde(default = "default_hide_method")]
    method: HideMethod,
}

impl Default for HideConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            method: HideMethod::CloseToTray,
        }
    }
}

fn default_hide_method() -> HideMethod {
    HideMethod::CloseToTray
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "kebab-case")]
enum HideMethod {
    CloseToTray,
    Minimize,
    MoveToWorkspace,
    MoveToSpecial,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceConfig {
    name: String,
    kind: WorkspaceKind,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "kebab-case")]
enum WorkspaceKind {
    Named,
    Special,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SmartGapsConfig {
    #[serde(default)]
    enabled: bool,
    #[serde(default)]
    profiles: Vec<GapProfile>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GapProfile {
    name: String,
    #[serde(default)]
    r#match: GapProfileMatch,
    gaps: GapTable,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GapProfileMatch {
    min_width: Option<i64>,
    max_width: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GapTable {
    one_window: Gaps,
    two_windows: Gaps,
    three_windows: Gaps,
    many_windows: Gaps,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Gaps {
    inner: i64,
    outer: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EwwConfig {
    #[serde(default = "default_eww_state_file")]
    state_file: String,
}

impl Default for EwwConfig {
    fn default() -> Self {
        Self {
            state_file: default_eww_state_file(),
        }
    }
}

fn default_eww_state_file() -> String {
    "$XDG_STATE_HOME/hctl/eww-state.json".to_string()
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Client {
    address: String,
    #[serde(default)]
    mapped: bool,
    #[serde(default)]
    hidden: bool,
    #[serde(default)]
    floating: bool,
    #[serde(default)]
    pinned: bool,
    #[serde(default)]
    class: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    initial_class: String,
    #[serde(default)]
    initial_title: String,
    workspace: ClientWorkspace,
}

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct ClientWorkspace {
    id: i64,
    #[serde(default)]
    name: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Monitor {
    #[serde(default)]
    name: String,
    #[serde(default)]
    x: i64,
    #[serde(default)]
    y: i64,
    #[serde(default)]
    width: i64,
    #[serde(default)]
    height: i64,
    #[serde(default)]
    focused: bool,
    #[serde(default)]
    active_workspace: ClientWorkspace,
}

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct ActiveWorkspace {
    id: i64,
    #[serde(default)]
    name: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EwwState {
    active_workspace: EwwWorkspace,
    apps: BTreeMap<String, EwwAppState>,
    smart_gaps: EwwSmartGaps,
    mode: EwwMode,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EwwWorkspace {
    id: i64,
    name: String,
    kind: String,
    window_count: usize,
    empty: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EwwAppState {
    running: bool,
    mapped: bool,
    workspace: Option<String>,
    home_workspace: Option<String>,
    borrowed: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EwwSmartGaps {
    profile: Option<String>,
    inner: Option<i64>,
    outer: Option<i64>,
    tiled_window_count: usize,
}

#[derive(Debug, Serialize)]
struct EwwMode {
    name: Option<String>,
}

struct Args {
    config_path: PathBuf,
    dry_run: bool,
    command: Vec<String>,
}

fn main() -> Result<()> {
    let args = parse_args()?;
    DRY_RUN.store(args.dry_run, Ordering::Relaxed);
    if args.command.is_empty() || args.command[0] == "help" || args.command[0] == "--help" {
        print_help();
        return Ok(());
    }

    let config = load_config(&args.config_path)?;
    match args.command[0].as_str() {
        "daemon" => daemon(&config),
        "summon" => with_app(&config, &args.command, summon),
        "hide" => with_app(&config, &args.command, hide),
        "borrow" => with_app(&config, &args.command, borrow),
        "return" => with_app(&config, &args.command, return_app),
        "toggle-borrow" => with_app(&config, &args.command, toggle_borrow),
        "goto" => goto_workspace(&config, &args.command),
        "video-pin" => video_pin(),
        "toggle-pin" => hypr_dispatch(&["pin"]),
        "zen-terminal" => zen_terminal(),
        "state" if args.command.get(1).map(String::as_str) == Some("eww") => {
            let state = build_eww_state(&config)?;
            println!("{}", serde_json::to_string_pretty(&state)?);
            Ok(())
        }
        other => bail!("unknown command: {other}"),
    }
}

fn parse_args() -> Result<Args> {
    parse_args_from(env::args().skip(1).collect())
}

fn parse_args_from(mut raw: Vec<String>) -> Result<Args> {
    let mut config_path = default_config_path()?;
    let mut dry_run = false;
    let mut i = 0;
    while i < raw.len() {
        if raw[i] == "--config" {
            let value = raw
                .get(i + 1)
                .ok_or_else(|| anyhow!("--config requires a path"))?;
            config_path = PathBuf::from(value);
            raw.drain(i..=i + 1);
        } else if raw[i] == "--dry-run" || raw[i] == "-n" {
            dry_run = true;
            raw.remove(i);
        } else {
            i += 1;
        }
    }
    Ok(Args {
        config_path,
        dry_run,
        command: raw,
    })
}

fn default_config_path() -> Result<PathBuf> {
    let base = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .ok_or_else(|| anyhow!("HOME is not set and XDG_CONFIG_HOME is unavailable"))?;
    Ok(base.join("hctl/config.json"))
}

fn load_config(path: &Path) -> Result<Config> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("failed to read config {}", path.display()))?;
    serde_json::from_str(&contents).with_context(|| format!("failed to parse {}", path.display()))
}

fn print_help() {
    println!(
        "hctl - Hyprland ergonomics control\n\n\
Usage:\n  hctl [--config PATH] [--dry-run|-n] <command> [args]\n\n\
Commands:\n  daemon\n  summon <app>\n  hide <app>\n  borrow <app>\n  return <app>\n  toggle-borrow <app>\n  goto <workspace>\n  video-pin\n  toggle-pin\n  zen-terminal\n  state eww"
    );
}

fn with_app(
    config: &Config,
    command: &[String],
    f: fn(&Config, &str, &AppConfig) -> Result<()>,
) -> Result<()> {
    let app_name = command
        .get(1)
        .ok_or_else(|| anyhow!("{} requires an app name", command[0]))?;
    let app = config
        .apps
        .get(app_name)
        .ok_or_else(|| anyhow!("unknown app: {app_name}"))?;
    f(config, app_name, app)
}

fn summon(_config: &Config, name: &str, app: &AppConfig) -> Result<()> {
    if !app.summon.enabled {
        bail!("summon is not enabled for {name}");
    }
    ensure_app_window(app)?;
    let client = find_client(app)?.ok_or_else(|| anyhow!("no window found for {name}"))?;
    let active = active_workspace()?;
    hypr_dispatch(&[
        "movetoworkspacesilent",
        &format!(
            "{},address:{}",
            active_workspace_target(&active),
            client.address
        ),
    ])?;
    apply_action(&client.address, &app.summon)?;
    hypr_dispatch(&["focuswindow", &format!("address:{}", client.address)])
}

fn hide(_config: &Config, name: &str, app: &AppConfig) -> Result<()> {
    if !app.hide.enabled {
        bail!("hide is not enabled for {name}");
    }
    let client = find_client(app)?.ok_or_else(|| anyhow!("no window found for {name}"))?;
    match app.hide.method {
        HideMethod::CloseToTray => {
            hypr_dispatch(&["closewindow", &format!("address:{}", client.address)])
        }
        HideMethod::Minimize | HideMethod::MoveToWorkspace | HideMethod::MoveToSpecial => {
            bail!(
                "hide method is configured but not implemented yet: {:?}",
                app.hide.method
            )
        }
    }
}

fn borrow(_config: &Config, name: &str, app: &AppConfig) -> Result<()> {
    if !app.borrow.enabled {
        bail!("borrow is not enabled for {name}");
    }
    ensure_app_window(app)?;
    let client = find_client(app)?.ok_or_else(|| anyhow!("no window found for {name}"))?;
    let active = active_workspace()?;
    hypr_dispatch(&[
        "movetoworkspacesilent",
        &format!(
            "{},address:{}",
            active_workspace_target(&active),
            client.address
        ),
    ])?;
    apply_action(&client.address, &app.borrow)?;
    hypr_dispatch(&["focuswindow", &format!("address:{}", client.address)])
}

fn return_app(config: &Config, name: &str, app: &AppConfig) -> Result<()> {
    let home = app
        .home_workspace
        .as_ref()
        .ok_or_else(|| anyhow!("{name} has no homeWorkspace"))?;
    let client = find_client(app)?.ok_or_else(|| anyhow!("no window found for {name}"))?;
    let workspace = config.workspaces.get(home);
    let target = workspace
        .map(|w| workspace_target(w))
        .unwrap_or_else(|| home.clone());
    hypr_dispatch(&[
        "movetoworkspacesilent",
        &format!("{},address:{}", target, client.address),
    ])?;
    hypr_dispatch(&["settiled", &format!("address:{}", client.address)])
}

fn toggle_borrow(config: &Config, name: &str, app: &AppConfig) -> Result<()> {
    let active = active_workspace()?;
    if let Some(client) = find_client(app)? {
        if client.workspace.name == active.name || client.workspace.id == active.id {
            return return_app(config, name, app);
        }
    }
    borrow(config, name, app)
}

fn goto_workspace(config: &Config, command: &[String]) -> Result<()> {
    let name = command
        .get(1)
        .ok_or_else(|| anyhow!("goto requires a workspace name"))?;
    let target = config
        .workspaces
        .get(name)
        .map(workspace_target)
        .unwrap_or_else(|| name.clone());
    hypr_dispatch(&["workspace", &target])
}

fn workspace_target(workspace: &WorkspaceConfig) -> String {
    match workspace.kind {
        WorkspaceKind::Named => format!("name:{}", workspace.name),
        WorkspaceKind::Special => format!("special:{}", workspace.name),
    }
}

fn active_workspace_target(workspace: &ActiveWorkspace) -> String {
    if workspace.name.parse::<i64>().is_ok() {
        workspace.name.clone()
    } else {
        format!("name:{}", workspace.name)
    }
}

fn video_pin() -> Result<()> {
    let monitor = focused_monitor()?;
    let active = active_client()?;
    let (width, height) = if monitor.width >= 2000 {
        (960, 540)
    } else {
        (640, 360)
    };
    let margin = 32;
    let x = monitor.x + (monitor.width - width - margin).max(margin);
    let y = monitor.y + (monitor.height - height - margin).max(margin);
    hypr_dispatch(&["setfloating", "active"])?;
    hypr_dispatch(&[
        "resizeactive",
        "exact",
        &width.to_string(),
        &height.to_string(),
    ])?;
    hypr_dispatch(&["moveactive", "exact", &x.to_string(), &y.to_string()])?;
    if active.map(|client| client.pinned).unwrap_or(false) {
        eprintln!("hctl video-pin: focused window is already pinned; leaving pin state unchanged");
        return Ok(());
    }
    hypr_dispatch(&["pin"])
}

fn zen_terminal() -> Result<()> {
    let monitor = focused_monitor()?;
    let width = if monitor.width >= 2000 {
        1400
    } else {
        1100.min(monitor.width - 80)
    };
    let height = if monitor.height >= 1200 {
        900
    } else {
        (monitor.height - 120).max(600)
    };
    hypr_dispatch(&["setfloating", "active"])?;
    hypr_dispatch(&[
        "resizeactive",
        "exact",
        &width.to_string(),
        &height.to_string(),
    ])?;
    hypr_dispatch(&["centerwindow"])
}

fn apply_action(address: &str, action: &ActionConfig) -> Result<()> {
    if action.floating {
        hypr_dispatch(&["setfloating", &format!("address:{address}")])?;
    }
    if action.size.is_some() || action.center {
        hypr_dispatch(&["focuswindow", &format!("address:{address}")])?;
    }
    if let Some(size) = action.size {
        let size = clamp_size_to_focused_monitor(size)?;
        hypr_dispatch(&[
            "resizeactive",
            "exact",
            &size.width.to_string(),
            &size.height.to_string(),
        ])?;
    }
    if action.center {
        hypr_dispatch(&["centerwindow"])?;
    }
    Ok(())
}

fn clamp_size_to_focused_monitor(size: Size) -> Result<Size> {
    let monitor = focused_monitor()?;
    Ok(clamp_size_to_monitor(size, &monitor))
}

fn clamp_size_to_monitor(size: Size, monitor: &Monitor) -> Size {
    Size {
        width: clamp_dimension(size.width, monitor.width, 80, 320),
        height: clamp_dimension(size.height, monitor.height, 80, 240),
    }
}

fn clamp_dimension(requested: i64, available: i64, margin: i64, preferred_min: i64) -> i64 {
    let maximum = (available - margin).max(1);
    let minimum = preferred_min.min(maximum);
    requested.min(maximum).max(minimum)
}

fn ensure_app_window(app: &AppConfig) -> Result<()> {
    if find_client(app)?.is_some() {
        return Ok(());
    }
    if app.launch.is_empty() {
        bail!("app is not running and has no launch command");
    }
    if DRY_RUN.load(Ordering::Relaxed) {
        eprintln!("dry-run: launch {}", shell_like_argv(&app.launch));
        return Ok(());
    }
    Command::new(&app.launch[0])
        .args(&app.launch[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .with_context(|| format!("failed to launch {}", app.launch[0]))?;

    for _ in 0..150 {
        thread::sleep(Duration::from_millis(100));
        if find_client(app)?.is_some() {
            return Ok(());
        }
    }
    bail!("launched app, but no matching window appeared")
}

fn shell_like_argv(argv: &[String]) -> String {
    argv.join(" ")
}

fn find_client(app: &AppConfig) -> Result<Option<Client>> {
    Ok(clients()?
        .into_iter()
        .find(|client| app_matches(app, client)))
}

fn app_matches(app: &AppConfig, client: &Client) -> bool {
    let m = &app.r#match;
    matches_optional(&m.class, &client.class)
        && matches_optional(&m.title, &client.title)
        && matches_optional(&m.initial_class, &client.initial_class)
        && matches_optional(&m.initial_title, &client.initial_title)
}

fn matches_optional(expected: &Option<String>, actual: &str) -> bool {
    expected
        .as_ref()
        .map_or(true, |expected| expected == actual)
}

fn clients() -> Result<Vec<Client>> {
    hypr_json(&["clients"])
}

fn monitors() -> Result<Vec<Monitor>> {
    hypr_json(&["monitors"])
}

fn active_workspace() -> Result<ActiveWorkspace> {
    hypr_json(&["activeworkspace"])
}

fn active_client() -> Result<Option<Client>> {
    active_client_from_value(hypr_json_value(&["activewindow"])?)
        .context("failed to parse active window")
}

fn active_client_from_value(value: serde_json::Value) -> Result<Option<Client>> {
    if value.is_null() || value.as_object().is_some_and(|object| object.is_empty()) {
        return Ok(None);
    }
    let client: Client = serde_json::from_value(value)?;
    if client.address.is_empty() {
        Ok(None)
    } else {
        Ok(Some(client))
    }
}

fn focused_monitor() -> Result<Monitor> {
    monitors()?
        .into_iter()
        .find(|monitor| monitor.focused)
        .ok_or_else(|| anyhow!("no focused monitor found"))
}

fn hypr_json<T: for<'de> Deserialize<'de>>(args: &[&str]) -> Result<T> {
    serde_json::from_value(hypr_json_value(args)?)
        .with_context(|| format!("failed to parse hyprctl {} -j output", args.join(" ")))
}

fn hypr_json_value(args: &[&str]) -> Result<serde_json::Value> {
    let output = Command::new("hyprctl")
        .args(args)
        .arg("-j")
        .output()
        .with_context(|| format!("failed to run hyprctl {} -j", args.join(" ")))?;
    if !output.status.success() {
        bail!(
            "hyprctl {} -j failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    serde_json::from_slice(&output.stdout)
        .with_context(|| format!("failed to parse hyprctl {} -j output", args.join(" ")))
}

fn hypr_dispatch(args: &[&str]) -> Result<()> {
    if DRY_RUN.load(Ordering::Relaxed) {
        eprintln!("dry-run: hyprctl dispatch {}", args.join(" "));
        return Ok(());
    }
    let output = Command::new("hyprctl")
        .arg("dispatch")
        .args(args)
        .output()
        .with_context(|| format!("failed to run hyprctl dispatch {}", args.join(" ")))?;
    if !output.status.success() {
        bail!(
            "hyprctl dispatch {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(())
}

fn hypr_keyword(args: &[&str]) -> Result<()> {
    if DRY_RUN.load(Ordering::Relaxed) {
        eprintln!("dry-run: hyprctl keyword {}", args.join(" "));
        return Ok(());
    }
    let output = Command::new("hyprctl")
        .arg("keyword")
        .args(args)
        .output()
        .with_context(|| format!("failed to run hyprctl keyword {}", args.join(" ")))?;
    if !output.status.success() {
        bail!(
            "hyprctl keyword {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(())
}

fn build_eww_state(config: &Config) -> Result<EwwState> {
    let active = active_workspace()?;
    let clients = clients()?;
    let monitor = focused_monitor()?;
    Ok(build_eww_state_from(config, &active, &clients, &monitor))
}

fn build_eww_state_from(
    config: &Config,
    active: &ActiveWorkspace,
    clients: &[Client],
    monitor: &Monitor,
) -> EwwState {
    let workspace_clients: Vec<&Client> = clients
        .iter()
        .filter(|client| client.workspace.id == active.id || client.workspace.name == active.name)
        .collect();
    let window_count = workspace_clients.len();
    let tiled_window_count = workspace_clients
        .iter()
        .filter(|client| !client.floating && !client.hidden)
        .count();
    let gap_selection = select_gaps(config, monitor.width, tiled_window_count);

    let apps = config
        .apps
        .iter()
        .map(|(name, app)| {
            let matched = clients.iter().find(|client| app_matches(app, client));
            let workspace = matched.map(|client| client.workspace.name.clone());
            let borrowed = match (&app.home_workspace, &workspace) {
                (Some(home), Some(current)) => current != home,
                _ => false,
            };
            (
                name.clone(),
                EwwAppState {
                    running: matched.is_some(),
                    mapped: matched
                        .map(|client| client.mapped && !client.hidden)
                        .unwrap_or(false),
                    workspace,
                    home_workspace: app.home_workspace.clone(),
                    borrowed,
                },
            )
        })
        .collect();

    EwwState {
        active_workspace: EwwWorkspace {
            id: active.id,
            name: active.name.clone(),
            kind: workspace_kind(config, &active.name),
            window_count,
            empty: window_count == 0,
        },
        apps,
        smart_gaps: EwwSmartGaps {
            profile: gap_selection.as_ref().map(|(name, _)| name.clone()),
            inner: gap_selection.as_ref().map(|(_, gaps)| gaps.inner),
            outer: gap_selection.as_ref().map(|(_, gaps)| gaps.outer),
            tiled_window_count,
        },
        mode: EwwMode { name: None },
    }
}

fn workspace_kind(config: &Config, name: &str) -> String {
    config
        .workspaces
        .iter()
        .find(|(_, workspace)| workspace.name == name)
        .map(|(_, workspace)| match workspace.kind {
            WorkspaceKind::Named => "named",
            WorkspaceKind::Special => "special",
        })
        .unwrap_or("unknown")
        .to_string()
}

fn select_gaps(
    config: &Config,
    monitor_width: i64,
    tiled_window_count: usize,
) -> Option<(String, Gaps)> {
    if !config.smart_gaps.enabled {
        return None;
    }
    let profile = config.smart_gaps.profiles.iter().find(|profile| {
        profile
            .r#match
            .min_width
            .map_or(true, |min_width| monitor_width >= min_width)
            && profile
                .r#match
                .max_width
                .map_or(true, |max_width| monitor_width <= max_width)
    })?;
    let gaps = match tiled_window_count {
        0 | 1 => profile.gaps.one_window,
        2 => profile.gaps.two_windows,
        3 => profile.gaps.three_windows,
        _ => profile.gaps.many_windows,
    };
    Some((profile.name.clone(), gaps))
}

fn daemon(config: &Config) -> Result<()> {
    let mut last_gaps = None;

    if let Err(err) = daemon_tick(config, &mut last_gaps) {
        eprintln!("hctl initial daemon tick failed: {err:#}");
    }

    if let Some(socket_path) = hyprland_socket2_path() {
        match UnixStream::connect(&socket_path) {
            Ok(stream) => return daemon_event_loop(config, stream, &mut last_gaps),
            Err(err) => eprintln!(
                "hctl failed to connect to Hyprland event socket {}; falling back to polling: {err}",
                socket_path.display()
            ),
        }
    } else {
        eprintln!(
            "hctl could not derive Hyprland event socket path; falling back to polling daemon"
        );
    }

    daemon_poll_loop(config, &mut last_gaps)
}

fn daemon_poll_loop(config: &Config, last_gaps: &mut Option<Gaps>) -> Result<()> {
    loop {
        if let Err(err) = daemon_tick(config, last_gaps) {
            eprintln!("hctl daemon tick failed: {err:#}");
        }
        thread::sleep(Duration::from_millis(750));
    }
}

fn daemon_event_loop(
    config: &Config,
    stream: UnixStream,
    last_gaps: &mut Option<Gaps>,
) -> Result<()> {
    let reader = BufReader::new(stream);
    for line in reader.lines() {
        let line = line?;
        if event_should_refresh(&line) {
            if let Err(err) = daemon_tick(config, last_gaps) {
                eprintln!("hctl daemon tick failed after Hyprland event {line:?}: {err:#}");
            }
        }
    }

    eprintln!("hctl Hyprland event socket closed; falling back to polling daemon");
    daemon_poll_loop(config, last_gaps)
}

fn hyprland_socket2_path() -> Option<PathBuf> {
    hyprland_socket2_path_from_env(
        env::var_os("XDG_RUNTIME_DIR"),
        env::var_os("HYPRLAND_INSTANCE_SIGNATURE"),
    )
}

fn hyprland_socket2_path_from_env(
    xdg_runtime_dir: Option<std::ffi::OsString>,
    instance_signature: Option<std::ffi::OsString>,
) -> Option<PathBuf> {
    Some(
        PathBuf::from(xdg_runtime_dir?)
            .join("hypr")
            .join(instance_signature?)
            .join(".socket2.sock"),
    )
}

fn event_should_refresh(event: &str) -> bool {
    let Some((name, _payload)) = event.split_once(">>") else {
        return false;
    };

    matches!(
        name,
        "activewindow"
            | "activewindowv2"
            | "changefloatingmode"
            | "closewindow"
            | "focusedmon"
            | "fullscreen"
            | "monitoradded"
            | "monitoraddedv2"
            | "monitorremoved"
            | "movewindow"
            | "movewindowv2"
            | "openwindow"
            | "openwindowv2"
            | "pin"
            | "submap"
            | "workspace"
            | "workspacev2"
    )
}

fn daemon_tick(config: &Config, last_gaps: &mut Option<Gaps>) -> Result<()> {
    let state = build_eww_state(config)?;
    if let (Some(inner), Some(outer)) = (state.smart_gaps.inner, state.smart_gaps.outer) {
        let gaps = Gaps { inner, outer };
        if last_gaps.as_ref() != Some(&gaps) {
            hypr_keyword(&["general:gaps_in", &inner.to_string()])?;
            hypr_keyword(&["general:gaps_out", &outer.to_string()])?;
            *last_gaps = Some(gaps);
        }
    } else {
        *last_gaps = None;
    }
    let path = expand_state_path(&config.eww.state_file)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, serde_json::to_string_pretty(&state)?)?;
    Ok(())
}

fn expand_state_path(raw: &str) -> Result<PathBuf> {
    expand_state_path_with_env(raw, env::var_os("XDG_STATE_HOME"), env::var_os("HOME"))
}

fn expand_state_path_with_env(
    raw: &str,
    xdg_state_home: Option<std::ffi::OsString>,
    home: Option<std::ffi::OsString>,
) -> Result<PathBuf> {
    if let Some(rest) = raw.strip_prefix("$XDG_STATE_HOME/") {
        let base = xdg_state_home
            .map(PathBuf::from)
            .or_else(|| home.map(|home| PathBuf::from(home).join(".local/state")))
            .ok_or_else(|| anyhow!("HOME is not set and XDG_STATE_HOME is unavailable"))?;
        return Ok(base.join(rest));
    }
    Ok(PathBuf::from(raw))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> Config {
        serde_json::from_str(
            r#"
            {
              "apps": {
                "signal": {
                  "match": { "class": "signal" },
                  "launch": ["signal-desktop"],
                  "homeWorkspace": "chat",
                  "borrow": {
                    "enabled": true,
                    "floating": true,
                    "center": true,
                    "size": { "width": 900, "height": 1000 }
                  }
                },
                "keepassxc": {
                  "match": { "class": "org.keepassxc.KeePassXC" },
                  "launch": ["keepassxc"],
                  "summon": {
                    "enabled": true,
                    "floating": true,
                    "center": true,
                    "size": { "width": 900, "height": 650 }
                  },
                  "hide": { "enabled": true, "method": "close-to-tray" }
                }
              },
              "workspaces": {
                "chat": { "name": "chat", "kind": "named" },
                "scratch": { "name": "scratch", "kind": "special" }
              },
              "smartGaps": {
                "enabled": true,
                "profiles": [
                  {
                    "name": "laptop",
                    "match": { "maxWidth": 1999 },
                    "gaps": {
                      "oneWindow": { "inner": 12, "outer": 32 },
                      "twoWindows": { "inner": 10, "outer": 24 },
                      "threeWindows": { "inner": 8, "outer": 12 },
                      "manyWindows": { "inner": 8, "outer": 12 }
                    }
                  },
                  {
                    "name": "externalLarge",
                    "match": { "minWidth": 2000 },
                    "gaps": {
                      "oneWindow": { "inner": 28, "outer": 180 },
                      "twoWindows": { "inner": 22, "outer": 120 },
                      "threeWindows": { "inner": 16, "outer": 72 },
                      "manyWindows": { "inner": 8, "outer": 24 }
                    }
                  }
                ]
              },
              "eww": { "stateFile": "$XDG_STATE_HOME/hctl/eww-state.json" }
            }
            "#,
        )
        .expect("test config should parse")
    }

    fn client(class: &str, workspace_id: i64, workspace_name: &str, floating: bool) -> Client {
        Client {
            address: format!("0x{workspace_id:x}{class:x<4}"),
            mapped: true,
            hidden: false,
            floating,
            pinned: false,
            class: class.to_string(),
            title: class.to_string(),
            initial_class: class.to_string(),
            initial_title: class.to_string(),
            workspace: ClientWorkspace {
                id: workspace_id,
                name: workspace_name.to_string(),
            },
        }
    }

    #[test]
    fn parses_v1_config_and_hide_enum() {
        let config = test_config();
        let keepass = config.apps.get("keepassxc").unwrap();
        assert_eq!(keepass.launch, ["keepassxc"]);
        assert!(matches!(keepass.hide.method, HideMethod::CloseToTray));
        assert!(config.workspaces.contains_key("chat"));
    }

    #[test]
    fn parses_global_dry_run_and_config_flags() {
        let args = parse_args_from(vec![
            "--dry-run".to_string(),
            "--config".to_string(),
            "/tmp/hctl.json".to_string(),
            "video-pin".to_string(),
        ])
        .unwrap();

        assert!(args.dry_run);
        assert_eq!(args.config_path, PathBuf::from("/tmp/hctl.json"));
        assert_eq!(args.command, ["video-pin"]);
    }

    #[test]
    fn active_client_parsing_handles_empty_and_pinned_windows() {
        assert!(active_client_from_value(serde_json::json!({}))
            .unwrap()
            .is_none());
        assert!(active_client_from_value(serde_json::Value::Null)
            .unwrap()
            .is_none());

        let active = active_client_from_value(serde_json::json!({
            "address": "0xabc",
            "mapped": true,
            "pinned": true,
            "class": "mpv",
            "workspace": { "id": 2, "name": "2" }
        }))
        .unwrap()
        .unwrap();

        assert_eq!(active.address, "0xabc");
        assert!(active.pinned);
    }

    #[test]
    fn app_matching_uses_exact_configured_fields() {
        let config = test_config();
        let signal = config.apps.get("signal").unwrap();
        assert!(app_matches(signal, &client("signal", 1, "1", false)));
        assert!(!app_matches(signal, &client("Signal", 1, "1", false)));
    }

    #[test]
    fn workspace_targets_distinguish_named_and_special() {
        let config = test_config();
        assert_eq!(
            workspace_target(config.workspaces.get("chat").unwrap()),
            "name:chat"
        );
        assert_eq!(
            workspace_target(config.workspaces.get("scratch").unwrap()),
            "special:scratch"
        );
    }

    #[test]
    fn active_workspace_target_preserves_numbered_and_names_named() {
        assert_eq!(
            active_workspace_target(&ActiveWorkspace {
                id: 1,
                name: "1".to_string(),
            }),
            "1"
        );
        assert_eq!(
            active_workspace_target(&ActiveWorkspace {
                id: -99,
                name: "chat".to_string(),
            }),
            "name:chat"
        );
    }

    #[test]
    fn smart_gaps_select_width_profile_and_window_count() {
        let config = test_config();
        assert_eq!(
            select_gaps(&config, 3840, 1),
            Some((
                "externalLarge".to_string(),
                Gaps {
                    inner: 28,
                    outer: 180
                }
            ))
        );
        assert_eq!(
            select_gaps(&config, 3840, 2),
            Some((
                "externalLarge".to_string(),
                Gaps {
                    inner: 22,
                    outer: 120
                }
            ))
        );
        assert_eq!(
            select_gaps(&config, 1920, 4),
            Some((
                "laptop".to_string(),
                Gaps {
                    inner: 8,
                    outer: 12
                }
            ))
        );
    }

    #[test]
    fn eww_state_derives_borrowed_apps_and_tiled_count() {
        let config = test_config();
        let active = ActiveWorkspace {
            id: 3,
            name: "3".to_string(),
        };
        let clients = vec![
            client("signal", 3, "3", true),
            client("ghostty", 3, "3", false),
            client("org.keepassxc.KeePassXC", 4, "4", true),
        ];
        let monitor = Monitor {
            name: "DP-2".to_string(),
            x: 1920,
            y: 0,
            width: 3840,
            height: 2160,
            focused: true,
            active_workspace: ClientWorkspace {
                id: 3,
                name: "3".to_string(),
            },
        };

        let state = build_eww_state_from(&config, &active, &clients, &monitor);
        assert_eq!(state.active_workspace.window_count, 2);
        assert_eq!(state.smart_gaps.tiled_window_count, 1);
        assert_eq!(state.smart_gaps.profile.as_deref(), Some("externalLarge"));
        assert!(state.apps.get("signal").unwrap().borrowed);
        assert!(!state.apps.get("keepassxc").unwrap().borrowed);
    }

    #[test]
    fn action_sizes_clamp_to_monitor_work_area_margin() {
        let laptop = Monitor {
            name: "eDP-1".to_string(),
            x: 0,
            y: 0,
            width: 1920,
            height: 1080,
            focused: true,
            active_workspace: ClientWorkspace::default(),
        };

        assert_eq!(
            clamp_size_to_monitor(
                Size {
                    width: 900,
                    height: 1000,
                },
                &laptop,
            ),
            Size {
                width: 900,
                height: 1000,
            }
        );

        assert_eq!(
            clamp_size_to_monitor(
                Size {
                    width: 3000,
                    height: 1800,
                },
                &laptop,
            ),
            Size {
                width: 1840,
                height: 1000,
            }
        );
    }

    #[test]
    fn state_path_expands_xdg_state_home_or_home_default() {
        assert_eq!(
            expand_state_path_with_env(
                "$XDG_STATE_HOME/hctl/eww-state.json",
                Some("/tmp/state".into()),
                Some("/home/chris".into())
            )
            .unwrap(),
            PathBuf::from("/tmp/state/hctl/eww-state.json")
        );
        assert_eq!(
            expand_state_path_with_env(
                "$XDG_STATE_HOME/hctl/eww-state.json",
                None,
                Some("/home/chris".into())
            )
            .unwrap(),
            PathBuf::from("/home/chris/.local/state/hctl/eww-state.json")
        );
    }

    #[test]
    fn hyprland_socket_path_uses_runtime_and_instance_signature() {
        assert_eq!(
            hyprland_socket2_path_from_env(Some("/run/user/1000".into()), Some("abc123".into())),
            Some(PathBuf::from("/run/user/1000/hypr/abc123/.socket2.sock"))
        );
        assert_eq!(
            hyprland_socket2_path_from_env(Some("/run/user/1000".into()), None),
            None
        );
    }

    #[test]
    fn event_filter_refreshes_for_relevant_hyprland_events() {
        assert!(event_should_refresh("workspace>>3"));
        assert!(event_should_refresh("workspacev2>>3,chat"));
        assert!(event_should_refresh("openwindow>>0xabc,3,Signal,Signal"));
        assert!(event_should_refresh("closewindow>>0xabc"));
        assert!(event_should_refresh("monitoradded>>DP-4"));
        assert!(event_should_refresh("monitorremoved>>DP-4"));
        assert!(event_should_refresh("submap>>chat"));
        assert!(!event_should_refresh("malformed"));
    }
}

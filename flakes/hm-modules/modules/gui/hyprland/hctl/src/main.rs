use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    env, fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::Duration,
};

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

#[derive(Debug, Copy, Clone, Deserialize)]
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

#[derive(Debug, Copy, Clone, Serialize, Deserialize)]
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
    command: Vec<String>,
}

fn main() -> Result<()> {
    let args = parse_args()?;
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
    let mut raw: Vec<String> = env::args().skip(1).collect();
    let mut config_path = default_config_path()?;
    let mut i = 0;
    while i < raw.len() {
        if raw[i] == "--config" {
            let value = raw
                .get(i + 1)
                .ok_or_else(|| anyhow!("--config requires a path"))?;
            config_path = PathBuf::from(value);
            raw.drain(i..=i + 1);
        } else {
            i += 1;
        }
    }
    Ok(Args {
        config_path,
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
Usage:\n  hctl [--config PATH] <command> [args]\n\n\
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
        &format!("{},address:{}", active.name, client.address),
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
        &format!("{},address:{}", active.name, client.address),
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
    ])
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

fn video_pin() -> Result<()> {
    let monitor = focused_monitor()?;
    let (width, height) = if monitor.width >= 2000 {
        (960, 540)
    } else {
        (640, 360)
    };
    let margin = 32;
    let x = (monitor.width - width - margin).max(margin);
    let y = (monitor.height - height - margin).max(margin);
    hypr_dispatch(&["setfloating", "active"])?;
    hypr_dispatch(&[
        "resizeactive",
        "exact",
        &width.to_string(),
        &height.to_string(),
    ])?;
    hypr_dispatch(&["moveactive", "exact", &x.to_string(), &y.to_string()])?;
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
    if let Some(size) = action.size {
        hypr_dispatch(&[
            "resizewindowpixel",
            "exact",
            &size.width.to_string(),
            &size.height.to_string(),
            &format!("address:{address}"),
        ])?;
    }
    if action.center {
        hypr_dispatch(&["focuswindow", &format!("address:{address}")])?;
        hypr_dispatch(&["centerwindow"])?;
    }
    Ok(())
}

fn ensure_app_window(app: &AppConfig) -> Result<()> {
    if find_client(app)?.is_some() {
        return Ok(());
    }
    if app.launch.is_empty() {
        bail!("app is not running and has no launch command");
    }
    Command::new(&app.launch[0])
        .args(&app.launch[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .with_context(|| format!("failed to launch {}", app.launch[0]))?;

    for _ in 0..50 {
        thread::sleep(Duration::from_millis(100));
        if find_client(app)?.is_some() {
            return Ok(());
        }
    }
    bail!("launched app, but no matching window appeared")
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

fn focused_monitor() -> Result<Monitor> {
    monitors()?
        .into_iter()
        .find(|monitor| monitor.focused)
        .ok_or_else(|| anyhow!("no focused monitor found"))
}

fn hypr_json<T: for<'de> Deserialize<'de>>(args: &[&str]) -> Result<T> {
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

    Ok(EwwState {
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
    })
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
    loop {
        if let Err(err) = daemon_tick(config) {
            eprintln!("hctl daemon tick failed: {err:#}");
        }
        thread::sleep(Duration::from_millis(750));
    }
}

fn daemon_tick(config: &Config) -> Result<()> {
    let state = build_eww_state(config)?;
    if let (Some(inner), Some(outer)) = (state.smart_gaps.inner, state.smart_gaps.outer) {
        hypr_keyword(&["general:gaps_in", &inner.to_string()])?;
        hypr_keyword(&["general:gaps_out", &outer.to_string()])?;
    }
    let path = expand_state_path(&config.eww.state_file)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, serde_json::to_string_pretty(&state)?)?;
    Ok(())
}

fn expand_state_path(raw: &str) -> Result<PathBuf> {
    if let Some(rest) = raw.strip_prefix("$XDG_STATE_HOME/") {
        let base = env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
            .ok_or_else(|| anyhow!("HOME is not set and XDG_STATE_HOME is unavailable"))?;
        return Ok(base.join(rest));
    }
    Ok(PathBuf::from(raw))
}

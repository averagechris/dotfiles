use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;
use std::collections::HashMap;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, IsTerminal, Write};
#[cfg(unix)]
use std::os::unix::fs as unix_fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::*;

#[derive(Debug, Clone)]
pub(crate) struct ProjectGroup {
    pub(crate) path: PathBuf,
    pub(crate) workspace_dir: String,
}

#[derive(Debug, Clone)]
pub(crate) struct WsConfig {
    pub(crate) project_groups: Vec<ProjectGroup>,
    pub(crate) copy_envrc: String,
    pub(crate) venv_mode: String,
    pub(crate) direnv_allow: bool,
    pub(crate) docker_cleanup: String,
    pub(crate) docker_remove_volumes: bool,
    pub(crate) fetch_remote: Option<String>,
    pub(crate) clone_artifacts: Vec<String>,
    pub(crate) sweep_idle: String,
}

pub(crate) const DEFAULT_SWEEP_IDLE: &str = "14d";

pub(crate) const DEFAULT_CLONE_ARTIFACTS: &[&str] = &[".direnv", "target", "node_modules", ".venv"];

#[derive(Debug, Clone)]
pub(crate) struct WorkspaceContext {
    pub(crate) repo_root: PathBuf,
    pub(crate) workspace_root: PathBuf,
    pub(crate) managed_workspace: bool,
}

pub fn run_ws(args: Vec<OsString>) -> Result<()> {
    run_ws_with_warning(args, |message| eprintln!("{message}"))
}

pub(crate) fn run_ws_with_warning<F>(args: Vec<OsString>, mut warn: F) -> Result<()>
where
    F: FnMut(&str),
{
    let mut iter = args.into_iter();
    let Some(sub) = iter.next() else {
        print_ws_usage();
        return Ok(());
    };
    let rest: Vec<_> = iter.collect();
    match sub.to_string_lossy().as_ref() {
        "add" => ws_add(rest, &mut warn),
        "list" => ws_list(rest),
        "path" => ws_path(rest),
        "forget" | "rm" => ws_forget(rest),
        "prune" => ws_prune(rest),
        "du" => ws_du(rest),
        "sweep" => ws_sweep(rest),
        "gc" => ws_gc(rest),
        "root" => ws_root(rest),
        "-h" | "--help" | "help" => {
            print_ws_usage();
            Ok(())
        }
        other => {
            bail!("unknown ws subcommand: {other}\n\nRun `jj ws --help` for available commands.")
        }
    }
}

pub(crate) fn print_ws_usage() {
    eprintln!("Usage:\n  jj ws add <name> [-r <revset>] [-q]\n  jj ws list [--pick]\n  jj ws path <name>|--pick\n  jj ws forget <name>|--pick [--force] [--purge] [--dry-run] [-q]\n  jj ws prune [--delete] [--pick]\n  jj ws du\n  jj ws sweep [--idle <duration>] [--dry-run]\n  jj ws gc [--older-than 7d] [--dry-run]\n  jj ws root\n\nExamples:\n  jj ws add feature-x -q\n  cd \"$(jj ws path feature-x)\"\n  jj ws forget feature-x\n  jj ws sweep --idle 14d --dry-run\n\nPath: <project-group>/<workspace-dir>/<repo>/<workspace>\nHelp: jj ws <command> --help");
}

pub(crate) fn print_ws_add_usage() {
    eprintln!("Usage:\n  jj ws add <name> [-r <revset>] [--project-group <path>] [--venv=<copy|link|none>] [--no-envrc] [--no-venv] [--no-clone-artifacts] [--no-direnv] [--no-hooks] [-q]\n\nCreates <project-group>/<workspace-dir>/<repo>/<name>.\nDefault base: main checkout -> inferred remote bookmark; workspace -> @.\nClones configured build artifacts (dotfiles.workspaces.clone-artifacts) from the source checkout; --no-clone-artifacts skips them.\n--no-hooks skips .jj-workspace.toml postcreate hooks.\n\nExamples:\n  jj ws add feature-x -q\n  jj ws add followup -r @\n  jj ws add hotfix --revision main@origin");
}

pub(crate) fn print_ws_list_usage() {
    eprintln!("Usage:\n  jj ws list [--pick]\n\nLists workspaces for this repo. --pick requires an interactive terminal.");
}

pub(crate) fn print_ws_path_usage() {
    eprintln!("Usage:\n  jj ws path <name>\n  jj ws path --pick\n\nPrints only the workspace path. --pick requires an interactive terminal.");
}

pub(crate) fn print_ws_forget_usage() {
    eprintln!("Usage:\n  jj ws forget <name> [--force] [--purge|--keep-dir] [--no-docker] [--docker-volumes|--keep-docker-volumes] [--no-hooks] [--dry-run] [-q]\n  jj ws forget --pick [options]\n\nForgets a workspace and moves its directory into <workspace-root>/.trash so\nuntracked files stay recoverable; `jj ws gc` deletes trash later.\n--purge deletes immediately instead of trashing. --keep-dir leaves the\ndirectory in place after forgetting. Refuses current/non-empty work unless --force.\nDocker Compose cleanup removes volumes by default; use --keep-docker-volumes to keep them.\n--no-hooks skips .jj-workspace.toml preforget hooks and the default Docker cleanup.\n\nExamples:\n  jj ws forget feature-x --dry-run\n  jj ws forget feature-x\n  jj ws forget scratch --force --purge -q");
}

pub(crate) fn print_ws_prune_usage() {
    eprintln!("Usage:\n  jj ws prune [--dry-run] [--delete] [--pick] [--yes]\n\nPrints stale workspace dirs. Use --delete to move them into .trash (recoverable via `jj ws gc`). --pick requires a terminal.");
}

pub(crate) fn print_ws_gc_usage() {
    eprintln!("Usage:\n  jj ws gc [--older-than <duration>] [--dry-run]\n\nDeletes trash entries under this repo's <workspace-root>/.trash that are at or\nolder than the retention period. Default retention comes from\ndotfiles.workspaces.trash-retention (7d). Durations use h, d, or w suffixes;\n`--older-than 0h` deletes all trash.\n\nExamples:\n  jj ws gc --dry-run\n  jj ws gc --older-than 0h");
}

pub(crate) fn print_ws_du_usage() {
    eprintln!("Usage:\n  jj ws du\n\nReports apparent bytes per registered managed workspace: total, one column per configured artifact (dotfiles.workspaces.clone-artifacts), other, last-touched (unix seconds), and idle seconds.\nNote: on APFS, cloned artifacts share blocks with the source checkout, so apparent sizes can overcount real disk usage.");
}

pub(crate) fn print_ws_sweep_usage() {
    eprintln!("Usage:\n  jj ws sweep [--idle <duration>] [--dry-run]\n\nRemoves configured artifact directories from managed workspaces idle for at least <duration> (default dotfiles.workspaces.sweep-idle, 14d). Durations: positive integers with h, d, or w; 0h is allowed for smoke tests. Never touches the current workspace, the main checkout, or paths outside the workspace root. Symlinks are never followed.\nNote: on APFS, cloned artifacts share blocks with the source checkout, so reported bytes can overcount real disk usage.\n\nExamples:\n  jj ws sweep --dry-run\n  jj ws sweep --idle 0h");
}

pub(crate) fn print_ws_root_usage() {
    eprintln!("Usage:\n  jj ws root\n\nPrints this repo's managed workspace root.");
}

pub(crate) fn ws_config() -> Result<WsConfig> {
    let copy_envrc = jj_config_string("dotfiles.workspaces.copy-envrc")?
        .unwrap_or_else(|| "untracked".to_string());
    let venv_mode =
        jj_config_string("dotfiles.workspaces.venv-mode")?.unwrap_or_else(|| match jj_config_bool(
            "dotfiles.workspaces.link-venv",
        ) {
            Ok(Some(false)) => "none".to_string(),
            _ => "copy".to_string(),
        });
    validate_venv_mode(&venv_mode)?;
    let direnv_allow = jj_config_bool("dotfiles.workspaces.direnv-allow")?.unwrap_or(true);
    let docker_cleanup = jj_config_string("dotfiles.workspaces.docker-cleanup")?
        .unwrap_or_else(|| "auto".to_string());
    let docker_remove_volumes =
        jj_config_bool("dotfiles.workspaces.docker-remove-volumes")?.unwrap_or(true);
    let fetch_remote = jj_config_string("dotfiles.workspaces.fetch-remote")?;
    let clone_artifacts = match jj_config_string("dotfiles.workspaces.clone-artifacts")? {
        Some(raw) => parse_toml_string_array(&raw),
        None => DEFAULT_CLONE_ARTIFACTS
            .iter()
            .map(std::string::ToString::to_string)
            .collect(),
    };
    let sweep_idle = jj_config_string("dotfiles.workspaces.sweep-idle")?
        .unwrap_or_else(|| DEFAULT_SWEEP_IDLE.to_string());
    let groups = jj_config_project_groups()?;
    Ok(WsConfig {
        project_groups: groups,
        copy_envrc,
        venv_mode,
        direnv_allow,
        docker_cleanup,
        docker_remove_volumes,
        fetch_remote,
        clone_artifacts,
        sweep_idle,
    })
}

pub(crate) fn jj_config_string(key: &str) -> Result<Option<String>> {
    let output = run_jj_capture_allow_failure(["config", "get", key])?;
    if !output.status.success() {
        return Ok(None);
    }
    let value = output.stdout.trim().trim_matches('"').to_string();
    Ok((!value.is_empty()).then_some(value))
}

pub(crate) fn jj_config_bool(key: &str) -> Result<Option<bool>> {
    Ok(
        jj_config_string(key)?.and_then(|value| match value.as_str() {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        }),
    )
}

pub(crate) fn jj_config_project_groups() -> Result<Vec<ProjectGroup>> {
    // Prefer the generated flat shape because it is robust to parse from `jj config get`.
    // Each item is `path` or `path:workspace-dir`.
    let raw = jj_config_string("dotfiles.workspaces.project-groups")?
        .or_else(|| {
            jj_config_string("dotfiles.workspaces.project-dirs")
                .ok()
                .flatten()
        })
        .unwrap_or_else(|| "[\"~/projects\"]".to_string());
    let mut groups = Vec::new();
    for item in parse_toml_string_array(&raw) {
        let (path, workspace_dir) = item.split_once(':').unwrap_or((&item, "ws"));
        groups.push(ProjectGroup {
            path: expand_tilde(path),
            workspace_dir: workspace_dir.to_string(),
        });
    }
    if groups.is_empty() {
        bail!("no dotfiles.workspaces.project-groups configured");
    }
    Ok(groups)
}

pub(crate) fn parse_toml_string_array(raw: &str) -> Vec<String> {
    raw.trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .split(',')
        .map(|part| part.trim().trim_matches('"').trim_matches('\''))
        .filter(|part| !part.is_empty())
        .map(std::string::ToString::to_string)
        .collect()
}

pub(crate) fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}

pub(crate) fn current_context(
    config: &WsConfig,
    override_group: Option<PathBuf>,
) -> Result<WorkspaceContext> {
    let repo_root = PathBuf::from(run_jj_capture(["root", "--color=never"])?.stdout.trim());
    let repo_root = fs::canonicalize(&repo_root).unwrap_or(repo_root);
    workspace_context_for_repo(&repo_root, config, override_group)
}

pub(crate) fn workspace_context_for_repo(
    repo_root: &Path,
    config: &WsConfig,
    override_group: Option<PathBuf>,
) -> Result<WorkspaceContext> {
    let group = if let Some(path) = override_group {
        ProjectGroup {
            path: expand_tilde(&path.to_string_lossy()),
            workspace_dir: "ws".to_string(),
        }
    } else {
        config
            .project_groups
            .iter()
            .filter(|group| {
                repo_root.starts_with(
                    fs::canonicalize(&group.path).unwrap_or_else(|_| group.path.clone()),
                )
            })
            .max_by_key(|group| group.path.components().count())
            .cloned()
            .ok_or_else(|| {
                anyhow!(
                    "repo root {} is not under a configured workspace project group",
                    repo_root.display()
                )
            })?
    };
    let group_path = fs::canonicalize(&group.path).unwrap_or(group.path.clone());
    let rel = repo_root.strip_prefix(&group_path).unwrap_or(&repo_root);
    let parts: Vec<_> = rel.components().collect();
    let managed_workspace =
        parts.len() >= 3 && parts[0].as_os_str() == group.workspace_dir.as_str();
    let repo_name = if managed_workspace {
        parts[1].as_os_str().to_string_lossy().to_string()
    } else {
        repo_root
            .file_name()
            .ok_or_else(|| anyhow!("could not infer repo name from {}", repo_root.display()))?
            .to_string_lossy()
            .to_string()
    };
    let workspace_root = group_path.join(&group.workspace_dir).join(&repo_name);
    Ok(WorkspaceContext {
        repo_root: repo_root.to_path_buf(),
        workspace_root,
        managed_workspace,
    })
}

pub(crate) fn validate_ws_name(name: &str) -> Result<()> {
    if name.is_empty()
        || name.contains("..")
        || !name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
    {
        bail!("invalid workspace name {name:?}; use only letters, numbers, dots, underscores, and hyphens")
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct WsAddArgs {
    pub(crate) name: String,
    pub(crate) revision: Option<String>,
    pub(crate) project_group: Option<PathBuf>,
    pub(crate) quiet: bool,
    pub(crate) no_envrc: bool,
    pub(crate) venv_mode: Option<String>,
    pub(crate) no_venv: bool,
    pub(crate) no_clone_artifacts: bool,
    pub(crate) no_direnv: bool,
    pub(crate) no_hooks: bool,
    pub(crate) help: bool,
}

pub(crate) fn parse_ws_add_args(args: Vec<OsString>) -> Result<WsAddArgs> {
    let mut parsed = WsAddArgs::default();
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        if arg == OsStr::new("-r") || arg == OsStr::new("--revision") {
            parsed.revision = Some(os_to_string(
                iter.next().ok_or_else(|| anyhow!("missing revision"))?,
            )?);
        } else if let Some(value) = take_value_after_prefix(&arg, "--revision=")? {
            parsed.revision = Some(value);
        } else if arg == OsStr::new("--project-group") || arg == OsStr::new("--project-dir") {
            parsed.project_group = Some(PathBuf::from(os_to_string(
                iter.next()
                    .ok_or_else(|| anyhow!("missing project group"))?,
            )?));
        } else if let Some(value) = take_value_after_prefix(&arg, "--project-group=")? {
            parsed.project_group = Some(PathBuf::from(value));
        } else if let Some(value) = take_value_after_prefix(&arg, "--project-dir=")? {
            parsed.project_group = Some(PathBuf::from(value));
        } else if arg == OsStr::new("-q") || arg == OsStr::new("--quiet") {
            parsed.quiet = true;
        } else if arg == OsStr::new("--no-envrc") {
            parsed.no_envrc = true;
        } else if arg == OsStr::new("--venv") || arg == OsStr::new("--venv-mode") {
            parsed.venv_mode = Some(os_to_string(
                iter.next().ok_or_else(|| anyhow!("missing venv mode"))?,
            )?);
        } else if let Some(value) = take_value_after_prefix(&arg, "--venv=")? {
            parsed.venv_mode = Some(value);
        } else if let Some(value) = take_value_after_prefix(&arg, "--venv-mode=")? {
            parsed.venv_mode = Some(value);
        } else if arg == OsStr::new("--no-venv") {
            parsed.no_venv = true;
        } else if arg == OsStr::new("--no-clone-artifacts") {
            parsed.no_clone_artifacts = true;
        } else if arg == OsStr::new("--no-direnv") {
            parsed.no_direnv = true;
        } else if arg == OsStr::new("--no-hooks") {
            parsed.no_hooks = true;
        } else if arg == OsStr::new("-h") || arg == OsStr::new("--help") {
            parsed.help = true;
        } else if arg.to_string_lossy().starts_with('-') {
            bail!("unknown option: {}", arg.to_string_lossy());
        } else if parsed.name.is_empty() {
            parsed.name = os_to_string(arg)?;
        } else {
            bail!("unexpected extra argument: {}", arg.to_string_lossy());
        }
    }
    if !parsed.help && parsed.name.is_empty() {
        bail!("missing workspace name\n\nUsage: jj ws add <name> [-r <revset>] [-q]");
    }
    if let Some(mode) = parsed.venv_mode.as_deref() {
        validate_venv_mode(mode)?;
    }
    Ok(parsed)
}

pub(crate) fn ws_add<F>(args: Vec<OsString>, warn: &mut F) -> Result<()>
where
    F: FnMut(&str),
{
    let parsed = parse_ws_add_args(args)?;
    if parsed.help {
        print_ws_add_usage();
        return Ok(());
    }
    let name = parsed.name;
    validate_ws_name(&name)?;
    let config = ws_config()?;
    let ctx = current_context(&config, parsed.project_group)?;
    let dest = ctx.workspace_root.join(&name);
    if dest.exists() {
        bail!("workspace path already exists: {}\n\nChoose a different workspace name, or run `jj ws list` to inspect existing workspaces.", dest.display());
    }
    fs::create_dir_all(&ctx.workspace_root)
        .with_context(|| format!("failed to create {}", ctx.workspace_root.display()))?;
    let base = if let Some(rev) = parsed.revision {
        rev
    } else if ctx.managed_workspace {
        "@".to_string()
    } else {
        fetch_for_workspace(&config)?;
        infer_remote_integration_bookmark()?
    };
    let add_args = vec![
        OsString::from("workspace"),
        OsString::from("add"),
        OsString::from("--name"),
        OsString::from(&name),
        OsString::from("--revision"),
        OsString::from(&base),
        dest.clone().into_os_string(),
    ];
    if parsed.quiet {
        run_jj_capture_os(add_args)?;
    } else {
        run_jj_status_os(add_args)?;
    }
    let mut copied_envrc = false;
    let mut venv_action = None;
    let mut direnv_allowed = false;
    let copied_lint_config = copy_jj_lint_config_if_needed(&ctx.repo_root, &dest)?;
    if !parsed.no_envrc && config.copy_envrc != "never" {
        copied_envrc = copy_envrc_if_needed(&ctx.repo_root, &dest, &config.copy_envrc)?;
    }
    let venv_mode = parsed.venv_mode.as_deref().unwrap_or(&config.venv_mode);
    // Single source of truth for `.venv` handling: both the artifact walker's
    // list and the venv setup step derive from this one decision.
    let venv_tracked = file_is_tracked(&ctx.repo_root, ".venv")?;
    let venv_plan = effective_venv_plan(
        &config.clone_artifacts,
        venv_mode,
        parsed.no_venv,
        parsed.no_clone_artifacts,
        venv_tracked,
        &ctx.repo_root,
    );
    let mut artifacts = effective_clone_artifacts(&config.clone_artifacts, venv_plan);
    if parsed.no_clone_artifacts {
        artifacts.clear();
    }
    let cloned_artifacts = if artifacts.is_empty() {
        0
    } else {
        clone_artifact_dirs(&ctx.repo_root, &dest, &artifacts)
    };
    if venv_plan.setup {
        venv_action = setup_venv_if_needed(&ctx.repo_root, &dest, venv_mode)?;
    }
    if !parsed.no_direnv
        && config.direnv_allow
        && dest.join(".envrc").exists()
        && which::which("direnv").is_ok()
    {
        run_status(
            Command::new("direnv").arg("allow").arg(&dest),
            "direnv allow",
        )?;
        direnv_allowed = true;
    }
    let copied_ws_config = copy_jj_workspace_config_if_needed(&ctx.repo_root, &dest)?;
    if !parsed.no_hooks {
        match load_workspace_repo_config(&dest.join(WORKSPACE_REPO_CONFIG_FILE)) {
            Ok(Some(repo_config)) if !repo_config.hooks.postcreate.is_empty() => {
                let hook_env = HookEnv {
                    source: &ctx.repo_root,
                    dest: &dest,
                    name: &name,
                    repo_root: &ctx.repo_root,
                };
                if let Err(err) = run_workspace_hooks(
                    &repo_config.hooks.postcreate,
                    "postcreate",
                    &dest,
                    hook_env,
                ) {
                    warn(&format!(
                        "Warning: {err:#}; leaving workspace intact at {}",
                        dest.display()
                    ));
                }
            }
            Ok(_) => {}
            Err(err) => {
                warn(&format!("Warning: {err:#}; skipping postcreate hooks"));
            }
        }
    }
    if copied_ws_config && !parsed.quiet {
        println!("copied .jj-workspace.toml");
    }
    if parsed.quiet {
        println!("{}", dest.display());
    } else {
        println!("created workspace {name} at {}", dest.display());
        println!("base: {base}");
        if copied_envrc {
            println!("copied untracked .envrc");
        }
        if copied_lint_config {
            println!("copied .jj-lint.toml");
        }
        if let Some(action) = venv_action {
            println!("{} untracked .venv", action.past_tense());
        }
        if cloned_artifacts > 0 {
            println!("cloned {cloned_artifacts} build artifact(s)");
        }
        if direnv_allowed {
            println!("direnv allowed");
        }
    }
    Ok(())
}

pub(crate) fn copy_jj_lint_config_if_needed(src: &Path, dest: &Path) -> Result<bool> {
    let src_lint_config = src.join(".jj-lint.toml");
    let dest_lint_config = dest.join(".jj-lint.toml");
    if !src_lint_config.exists() || dest_lint_config.exists() {
        return Ok(false);
    }
    fs::copy(&src_lint_config, &dest_lint_config)
        .with_context(|| format!("failed to copy {}", src_lint_config.display()))?;
    Ok(true)
}

pub(crate) const WORKSPACE_REPO_CONFIG_FILE: &str = ".jj-workspace.toml";
pub(crate) const WORKSPACE_REPO_CONFIG_VERSION: u32 = 1;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorkspaceRepoConfig {
    pub(crate) version: u32,
    #[serde(default)]
    pub(crate) hooks: WorkspaceHooks,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorkspaceHooks {
    #[serde(default)]
    pub(crate) postcreate: Vec<String>,
    #[serde(default)]
    pub(crate) preforget: Option<Vec<String>>,
}

impl WorkspaceRepoConfig {
    pub(crate) fn preforget(&self) -> Option<&Vec<String>> {
        self.hooks.preforget.as_ref()
    }
}

pub(crate) fn load_workspace_repo_config(path: &Path) -> Result<Option<WorkspaceRepoConfig>> {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(err) => {
            return Err(err).with_context(|| format!("failed to read {}", path.display()));
        }
    };
    let config: WorkspaceRepoConfig = toml::from_str(&text)
        .with_context(|| format!("invalid workspace config {}", path.display()))?;
    if config.version != WORKSPACE_REPO_CONFIG_VERSION {
        bail!(
            "unsupported version {} in {}; expected {}",
            config.version,
            path.display(),
            WORKSPACE_REPO_CONFIG_VERSION
        );
    }
    for (phase, commands) in [
        ("postcreate", &config.hooks.postcreate),
        ("preforget", config.preforget().unwrap_or(&Vec::new())),
    ] {
        for command in commands {
            if command.trim().is_empty() {
                bail!("empty {phase} hook command in {}", path.display());
            }
        }
    }
    Ok(Some(config))
}

pub(crate) fn copy_jj_workspace_config_if_needed(src: &Path, dest: &Path) -> Result<bool> {
    let src_config = src.join(WORKSPACE_REPO_CONFIG_FILE);
    let dest_config = dest.join(WORKSPACE_REPO_CONFIG_FILE);
    if !src_config.exists() || dest_config.exists() {
        return Ok(false);
    }
    fs::copy(&src_config, &dest_config)
        .with_context(|| format!("failed to copy {}", src_config.display()))?;
    Ok(true)
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct HookEnv<'a> {
    pub(crate) source: &'a Path,
    pub(crate) dest: &'a Path,
    pub(crate) name: &'a str,
    pub(crate) repo_root: &'a Path,
}

pub(crate) fn run_workspace_hooks(
    commands: &[String],
    phase: &str,
    cwd: &Path,
    env: HookEnv<'_>,
) -> Result<()> {
    for command in commands {
        let mut cmd = Command::new("sh");
        cmd.args(["-c", command]).current_dir(cwd);
        cmd.env("JJ_WS_SOURCE", env.source);
        cmd.env("JJ_WS_DEST", env.dest);
        cmd.env("JJ_WS_NAME", env.name);
        cmd.env("JJ_WS_REPO_ROOT", env.repo_root);
        let status = cmd
            .status()
            .with_context(|| format!("failed to execute {phase} hook: {command}"))?;
        if !status.success() {
            bail!("{phase} hook failed: {command} ({status})");
        }
    }
    Ok(())
}

pub(crate) fn fetch_for_workspace(config: &WsConfig) -> Result<()> {
    let mut remotes = git_remotes()?;
    dedup(&mut remotes);
    match fetch_remote_choice(&remotes, config.fetch_remote.as_deref()) {
        FetchChoice::None => Ok(()),
        FetchChoice::Fetch(remote) => run_jj_status(["git", "fetch", "--remote", remote.as_str()]),
        FetchChoice::SkipAmbiguous(remotes) => {
            eprintln!("Warning: multiple remotes found and no dotfiles.workspaces.fetch-remote configured: {}; skipping fetch.\nHint: configure dotfiles.workspaces.fetch-remote or pass `--revision <bookmark>@<remote>`.", remotes.join(", "));
            Ok(())
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum FetchChoice {
    None,
    Fetch(String),
    SkipAmbiguous(Vec<String>),
}

pub(crate) fn fetch_remote_choice(remotes: &[String], configured: Option<&str>) -> FetchChoice {
    match remotes {
        [] => FetchChoice::None,
        [remote] => FetchChoice::Fetch(remote.clone()),
        many => configured
            .map(|remote| FetchChoice::Fetch(remote.to_string()))
            .unwrap_or_else(|| FetchChoice::SkipAmbiguous(many.to_vec())),
    }
}

pub(crate) fn infer_remote_integration_bookmark() -> Result<String> {
    let output = run_jj_capture([
        "bookmark", "list", "--all-remotes", "--color=never", "-T",
        "if(self.remote() && self.remote() != \"git\", self.name() ++ \"@\" ++ self.remote() ++ \"\\n\", \"\")",
    ])?;
    let bookmarks: Vec<String> = output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect();
    infer_remote_integration_bookmark_from(&bookmarks)
}

pub(crate) fn infer_remote_integration_bookmark_from(bookmarks: &[String]) -> Result<String> {
    let groups: Vec<Vec<String>> = vec![
        remote_matches(&bookmarks, &["develop"]),
        remote_matches(&bookmarks, &["dev"]),
        remote_matches(&bookmarks, &["main"]),
        remote_matches(&bookmarks, &["master"]),
        remote_matches(&bookmarks, &["trunk"]),
        bookmarks
            .iter()
            .filter(|b| b.split('@').next().is_some_and(is_release_bookmark))
            .cloned()
            .collect(),
    ];
    for mut group in groups {
        dedup(&mut group);
        match group.as_slice() {
            [] => continue,
            [only] => return Ok(only.clone()),
            _ => bail!("could not infer integration bookmark; candidates:\n  {}\n\nSpecify one explicitly, for example:\n  jj ws add <name> --revision {}", group.join("\n  "), group[0]),
        }
    }
    bail!("could not infer integration bookmark.\n\nSpecify one explicitly, for example:\n  jj ws add <name> --revision main@origin")
}

pub(crate) fn remote_matches(bookmarks: &[String], names: &[&str]) -> Vec<String> {
    bookmarks
        .iter()
        .filter(|b| {
            b.split('@')
                .next()
                .is_some_and(|name| names.contains(&name))
        })
        .cloned()
        .collect()
}

pub(crate) fn copy_envrc_if_needed(src: &Path, dest: &Path, mode: &str) -> Result<bool> {
    let src_envrc = src.join(".envrc");
    let dest_envrc = dest.join(".envrc");
    if !src_envrc.exists() || dest_envrc.exists() {
        return Ok(false);
    }
    if mode == "untracked" && file_is_tracked(src, ".envrc")? {
        return Ok(false);
    }
    fs::copy(&src_envrc, &dest_envrc)
        .with_context(|| format!("failed to copy {}", src_envrc.display()))?;
    Ok(true)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum VenvAction {
    Copied,
    Linked,
}

impl VenvAction {
    fn past_tense(self) -> &'static str {
        match self {
            VenvAction::Copied => "copied",
            VenvAction::Linked => "linked",
        }
    }
}

pub(crate) fn setup_venv_if_needed(
    src: &Path,
    dest: &Path,
    mode: &str,
) -> Result<Option<VenvAction>> {
    let src_venv = src.join(".venv");
    let dest_venv = dest.join(".venv");
    match mode {
        "none" => Ok(None),
        "link" => {
            if !src_venv.exists()
                || dest_venv.exists()
                || file_is_tracked(src, ".venv")?
                || !source_venv_python_usable(&src_venv)
            {
                return Ok(None);
            }
            symlink_path(&src_venv, &dest_venv).with_context(|| {
                format!(
                    "failed to symlink {} to {}",
                    dest_venv.display(),
                    src_venv.display()
                )
            })?;
            Ok(Some(VenvAction::Linked))
        }
        "copy" => {
            if !src_venv.exists()
                || file_is_tracked(src, ".venv")?
                || !source_venv_python_usable(&src_venv)
            {
                return Ok(None);
            }
            // The generic artifact step usually cloned `.venv` already; only
            // clone here when it is missing from the configured artifact list.
            if !dest_venv.exists() {
                clone_dir_strict(&src_venv, &dest_venv);
            }
            repair_venv_paths(&src_venv, &dest_venv)?;
            Ok(Some(VenvAction::Copied))
        }
        other => bail!("invalid venv mode {other:?}; expected copy, link, or none"),
    }
}

/// One unified decision for how `.venv` should be handled for a new
/// workspace. Both the artifact walker's clone list and the venv setup step
/// derive from this, so flags and config cannot disagree between the two
/// sites.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct VenvPlan {
    /// Include `.venv` in the generic artifact clone walk.
    pub(crate) clone_into_dest: bool,
    /// Run the venv setup step (link symlink, or copy fallback + repair).
    pub(crate) setup: bool,
}

pub(crate) fn effective_venv_plan(
    configured: &[String],
    venv_mode: &str,
    no_venv: bool,
    no_clone_artifacts: bool,
    venv_tracked: bool,
    src: &Path,
) -> VenvPlan {
    // `none` mode and `--no-venv` mean no venv anywhere in the destination.
    if no_venv || venv_mode == "none" {
        return VenvPlan {
            clone_into_dest: false,
            setup: false,
        };
    }
    let src_venv = src.join(".venv");
    let usable = source_venv_python_usable(&src_venv);
    match venv_mode {
        // Link mode symlinks regardless of the artifact list.
        "link" => VenvPlan {
            clone_into_dest: false,
            setup: src_venv.exists() && !venv_tracked && usable,
        },
        // Copy mode always yields a REPAIRED venv whenever one exists in the
        // destination by any path, but `--no-clone-artifacts` suppresses every
        // clone, including the copy fallback here.
        "copy" => {
            let eligible = src_venv.exists() && !venv_tracked && usable;
            VenvPlan {
                clone_into_dest: eligible
                    && !no_clone_artifacts
                    && configured.iter().any(|name| name == ".venv"),
                setup: eligible && !no_clone_artifacts,
            }
        }
        _ => VenvPlan {
            clone_into_dest: false,
            setup: false,
        },
    }
}

pub(crate) fn effective_clone_artifacts(configured: &[String], plan: VenvPlan) -> Vec<String> {
    configured
        .iter()
        .filter(|name| name.as_str() != ".venv" || plan.clone_into_dest)
        .cloned()
        .collect()
}

pub(crate) fn clone_artifact_dirs(src: &Path, dest: &Path, names: &[String]) -> usize {
    if names.is_empty() {
        return 0;
    }
    let mut cloned = 0;
    walk_artifact_dirs(src, src, dest, names, &mut cloned);
    cloned
}

pub(crate) fn walk_artifact_dirs(
    src_root: &Path,
    dir: &Path,
    dest_root: &Path,
    names: &[String],
    cloned: &mut usize,
) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(err) => {
            eprintln!(
                "Warning: cannot read directory {}: {err}; skipping it.",
                dir.display()
            );
            return;
        }
    };
    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            Err(err) => {
                eprintln!(
                    "Warning: cannot read an entry in {}: {err}; skipping it.",
                    dir.display()
                );
                continue;
            }
        };
        // Never follow symlinks during traversal: symlinked directories are
        // skipped entirely (even when their basename matches a configured
        // artifact) so cycles cannot cause infinite recursion and unrelated
        // trees are not pulled into the walk.
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if !file_type.is_dir() {
            continue;
        }
        let path = entry.path();
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        if name == ".jj" || name == ".git" {
            continue;
        }
        if names.iter().any(|candidate| candidate == name) {
            let Ok(rel) = path.strip_prefix(src_root) else {
                continue;
            };
            let target = dest_root.join(rel);
            if !target.exists() {
                if let Some(parent) = target.parent() {
                    let _ = fs::create_dir_all(parent);
                }
                if clone_dir_strict(&path, &target) {
                    *cloned += 1;
                }
            }
            // Do not descend into a selected artifact directory.
            continue;
        }
        walk_artifact_dirs(src_root, &path, dest_root, names, cloned);
    }
}

/// Strict CoW clone: no full-copy fallback. On failure the partial
/// destination is removed, a warning is printed, and `false` is returned.
pub(crate) fn clone_dir_strict(src: &Path, dest: &Path) -> bool {
    let clone_args: Vec<&str> = if cfg!(target_os = "macos") {
        vec!["-cR"]
    } else {
        vec!["-a", "--reflink=always"]
    };
    if run_cp(&clone_args, src, dest).unwrap_or(false) {
        return true;
    }
    let _ = fs::remove_dir_all(dest);
    eprintln!(
        "Warning: failed to clone {} to {}; continuing without it.",
        src.display(),
        dest.display()
    );
    false
}

pub(crate) fn source_venv_python_usable(src_venv: &Path) -> bool {
    src_venv.join("bin/python").exists()
}

pub(crate) fn run_cp(args: &[&str], src: &Path, dest: &Path) -> Result<bool> {
    let program = if cfg!(target_os = "macos") {
        "/bin/cp"
    } else {
        "cp"
    };
    let status = Command::new(program)
        .args(args)
        .arg(src)
        .arg(dest)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .with_context(|| format!("failed to execute {program}"))?;
    Ok(status.success())
}

pub(crate) fn repair_venv_paths(src_venv: &Path, dest_venv: &Path) -> Result<()> {
    let canon_src = fs::canonicalize(src_venv).unwrap_or_else(|_| src_venv.to_path_buf());
    let canon_dest = fs::canonicalize(dest_venv).unwrap_or_else(|_| dest_venv.to_path_buf());
    // venv files record whatever literal path was current when the venv was
    // created. On macOS, canonicalization resolves `/var` to `/private/var`
    // (and similar symlinked prefixes), so the spelling in pyvenv.cfg and bin
    // scripts can differ from BOTH the raw and the canonicalized argument
    // paths. Collect every old->new pair we can justify:
    //   1. raw arguments as passed,
    //   2. canonicalized arguments,
    //   3. the source path AS SPELLED in the copied files (discovered by
    //      scanning for absolute paths that canonicalize to the source venv),
    //      rewritten to the destination under the same prefix spelling.
    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut push_pair = |old: PathBuf, new: PathBuf| {
        let pair = (
            old.to_string_lossy().into_owned(),
            new.to_string_lossy().into_owned(),
        );
        if pair.0 != pair.1 && !pairs.contains(&pair) {
            pairs.push(pair);
        }
    };
    push_pair(src_venv.to_path_buf(), dest_venv.to_path_buf());
    push_pair(canon_src.clone(), canon_dest.clone());
    for spelled in discover_spelled_source_paths(&dest_venv, &canon_src) {
        if let (Some(spelled_base), Some(_)) = (spelled.parent(), canon_src.parent()) {
            if let Some(dest_name) = canon_dest.file_name() {
                push_pair(spelled.clone(), spelled_base.join(dest_name));
            }
        }
        push_pair(spelled, canon_dest.clone());
    }
    replace_paths_in_text_file(&dest_venv.join("pyvenv.cfg"), &pairs)?;
    let bin = dest_venv.join("bin");
    if bin.exists() {
        for entry in fs::read_dir(bin)? {
            let path = entry?.path();
            if path.is_file() {
                replace_paths_in_text_file(&path, &pairs)?;
            }
        }
    }
    Ok(())
}

/// Find spellings of `canon_src` actually written in the copied venv files:
/// any whitespace-delimited token that looks like an absolute path and whose
/// canonical form equals `canon_src`.
pub(crate) fn discover_spelled_source_paths(dest_venv: &Path, canon_src: &Path) -> Vec<PathBuf> {
    let mut files = vec![dest_venv.join("pyvenv.cfg")];
    let bin = dest_venv.join("bin");
    if bin.exists() {
        if let Ok(entries) = fs::read_dir(bin) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_file() {
                    files.push(path);
                }
            }
        }
    }
    let mut found: Vec<PathBuf> = Vec::new();
    for file in files {
        let Ok(bytes) = fs::read(&file) else {
            continue;
        };
        let Ok(text) = String::from_utf8(bytes) else {
            continue;
        };
        for token in text.split_whitespace() {
            let token = token.trim_start_matches('#');
            let token = token.trim_end_matches(|c: char| !c.is_ascii_graphic() || c == ':');
            if !token.starts_with('/') {
                continue;
            }
            let candidate = PathBuf::from(token);
            if fs::canonicalize(&candidate).is_ok_and(|p| p == canon_src)
                && !found.contains(&candidate)
            {
                found.push(candidate);
            }
        }
    }
    found
}

pub(crate) fn replace_paths_in_text_file(path: &Path, pairs: &[(String, String)]) -> Result<()> {
    let Ok(bytes) = fs::read(path) else {
        return Ok(());
    };
    let Ok(mut text) = String::from_utf8(bytes) else {
        return Ok(());
    };
    for (old, new) in pairs {
        if text.contains(old.as_str()) {
            text = text.replace(old.as_str(), new.as_str());
        }
    }
    if !text.is_empty() {
        fs::write(path, text)?;
    }
    Ok(())
}

#[cfg(unix)]
pub(crate) fn symlink_path(src: &Path, dest: &Path) -> std::io::Result<()> {
    unix_fs::symlink(src, dest)
}

pub(crate) fn file_is_tracked(repo: &Path, file: &str) -> Result<bool> {
    let output = Command::new("jj")
        .arg("file")
        .arg("show")
        .arg(file)
        .current_dir(repo)
        .output()?;
    Ok(output.status.success())
}

pub(crate) fn workspace_entries() -> Result<Vec<(String, String)>> {
    let config = ws_config()?;
    let ctx = current_context(&config, None)?;
    let output = run_jj_capture([
        "workspace",
        "list",
        "--color=never",
        "-T",
        "self.name() ++ \"\\n\"",
    ])?;
    let current_name = jj_config_string("workspace.name")?.unwrap_or_else(|| "default".to_string());
    let current_root = fs::canonicalize(run_jj_capture(["root", "--color=never"])?.stdout.trim())
        .unwrap_or(ctx.repo_root.clone());
    let entries = output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(|name| {
            let path = if name == current_name {
                current_root.clone()
            } else {
                ctx.workspace_root.join(name)
            };
            (name.to_string(), path.display().to_string())
        })
        .collect();
    Ok(entries)
}

pub(crate) fn ws_list(args: Vec<OsString>) -> Result<()> {
    let pick = parse_pick_only_args("jj ws list", args)?;
    let entries = workspace_entries()?;
    if pick {
        let lines: Vec<String> = entries.iter().map(|(n, p)| format!("{n}\t{p}")).collect();
        println!("{}", pick_lines("Workspace", &lines)?.unwrap_or_default());
    } else {
        println!("NAME\tPATH");
        for (name, path) in entries {
            println!("{name}\t{path}");
        }
    }
    Ok(())
}

pub(crate) fn parse_pick_only_args(command: &str, args: Vec<OsString>) -> Result<bool> {
    let mut pick = false;
    for arg in args {
        if arg == OsStr::new("--pick") {
            pick = true;
        } else if arg == OsStr::new("-h") || arg == OsStr::new("--help") {
            match command {
                "jj ws list" => print_ws_list_usage(),
                _ => print_ws_usage(),
            }
            return Ok(pick);
        } else {
            bail!(
                "{command} does not accept argument: {}\n\nRun `{command} --help` for usage.",
                arg.to_string_lossy()
            );
        }
    }
    Ok(pick)
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct WsPathArgs {
    pub(crate) name: Option<String>,
    pub(crate) pick: bool,
}

pub(crate) fn parse_ws_path_args(args: Vec<OsString>) -> Result<WsPathArgs> {
    let mut parsed = WsPathArgs::default();
    for arg in args {
        if arg == OsStr::new("--pick") {
            parsed.pick = true;
        } else if arg == OsStr::new("-h") || arg == OsStr::new("--help") {
            print_ws_path_usage();
        } else if arg.to_string_lossy().starts_with('-') {
            bail!("unknown option: {}", arg.to_string_lossy());
        } else if parsed.name.is_none() {
            parsed.name = Some(os_to_string(arg)?);
        } else {
            bail!("unexpected extra argument: {}", arg.to_string_lossy());
        }
    }
    if parsed.pick && parsed.name.is_some() {
        bail!("jj ws path accepts either <name> or --pick, not both\n\nUse `jj ws path <name>` for agents/noninteractive use, or `jj ws path --pick` in an interactive terminal.");
    }
    if !parsed.pick && parsed.name.is_none() {
        bail!("missing workspace name\n\nUsage: jj ws path <name>\n       jj ws path --pick");
    }
    Ok(parsed)
}

pub(crate) fn ws_path(args: Vec<OsString>) -> Result<()> {
    let parsed = parse_ws_path_args(args)?;
    let entries = workspace_entries()?;
    let selected = if parsed.pick {
        let lines: Vec<String> = entries.iter().map(|(n, p)| format!("{n}\t{p}")).collect();
        let line =
            pick_lines("Workspace", &lines)?.ok_or_else(|| anyhow!("no workspace selected"))?;
        line.split('\t').nth(1).unwrap_or(line.as_str()).to_string()
    } else {
        let name = parsed.name.expect("validated by parser");
        entries
            .into_iter()
            .find(|(n, _)| n == &name)
            .map(|(_, p)| p)
            .ok_or_else(|| anyhow!("workspace not found: {name}"))?
    };
    println!("{selected}");
    Ok(())
}

pub(crate) fn ws_root(args: Vec<OsString>) -> Result<()> {
    if !args.is_empty() {
        if args
            .iter()
            .any(|a| a == OsStr::new("-h") || a == OsStr::new("--help"))
        {
            print_ws_root_usage();
            return Ok(());
        }
        bail!("jj ws root does not accept arguments\n\nUsage: jj ws root");
    }
    let config = ws_config()?;
    let ctx = current_context(&config, None)?;
    println!("{}", ctx.workspace_root.display());
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct WsForgetArgs {
    pub(crate) name: Option<String>,
    pub(crate) pick: bool,
    pub(crate) force: bool,
    pub(crate) keep_dir: bool,
    pub(crate) purge: bool,
    pub(crate) no_docker: bool,
    pub(crate) no_hooks: bool,
    pub(crate) docker_volumes: bool,
    pub(crate) keep_docker_volumes: bool,
    pub(crate) dry_run: bool,
    pub(crate) quiet: bool,
}

pub(crate) fn parse_ws_forget_args(args: Vec<OsString>) -> Result<WsForgetArgs> {
    let mut parsed = WsForgetArgs::default();
    for arg in args {
        match arg.to_string_lossy().as_ref() {
            "--pick" => parsed.pick = true,
            "--force" => parsed.force = true,
            "--keep-dir" => parsed.keep_dir = true,
            "--purge" => parsed.purge = true,
            "--no-docker" => parsed.no_docker = true,
            "--no-hooks" => parsed.no_hooks = true,
            "--docker-volumes" => parsed.docker_volumes = true,
            "--keep-docker-volumes" => parsed.keep_docker_volumes = true,
            "--dry-run" => parsed.dry_run = true,
            "-q" | "--quiet" => parsed.quiet = true,
            "-h" | "--help" => print_ws_forget_usage(),
            other if other.starts_with('-') => bail!("unknown option: {other}"),
            _ if parsed.name.is_none() => parsed.name = Some(os_to_string(arg)?),
            _ => bail!("unexpected extra argument: {}", arg.to_string_lossy()),
        }
    }
    if parsed.pick && parsed.name.is_some() {
        bail!("jj ws forget accepts either <name> or --pick, not both\n\nUse `jj ws forget <name>` for agents/noninteractive use, or `jj ws forget --pick` in an interactive terminal.");
    }
    if !parsed.pick && parsed.name.is_none() {
        bail!("missing workspace name\n\nUsage: jj ws forget <name> [--force] [--dry-run]");
    }
    if parsed.docker_volumes && parsed.keep_docker_volumes {
        bail!("--docker-volumes and --keep-docker-volumes are mutually exclusive");
    }
    if parsed.purge && parsed.keep_dir {
        bail!("--purge and --keep-dir are mutually exclusive\n\n--purge deletes the workspace directory immediately; --keep-dir leaves it in place after forgetting.");
    }
    Ok(parsed)
}

pub(crate) fn validate_venv_mode(mode: &str) -> Result<()> {
    match mode {
        "copy" | "link" | "none" => Ok(()),
        other => bail!("invalid venv mode {other:?}; expected copy, link, or none"),
    }
}

pub(crate) fn ws_forget(args: Vec<OsString>) -> Result<()> {
    let parsed = parse_ws_forget_args(args)?;
    let entries = workspace_entries()?;
    let (name, path) = if parsed.pick {
        let lines: Vec<String> = entries.iter().map(|(n, p)| format!("{n}\t{p}")).collect();
        let line = pick_lines("Forget workspace", &lines)?
            .ok_or_else(|| anyhow!("no workspace selected"))?;
        let (n, p) = line
            .split_once('\t')
            .ok_or_else(|| anyhow!("invalid picker selection"))?;
        (n.to_string(), PathBuf::from(p))
    } else {
        let n = parsed.name.expect("validated by parser");
        let p = entries
            .iter()
            .find(|(en, _)| en == &n)
            .map(|(_, p)| PathBuf::from(p))
            .ok_or_else(|| anyhow!("workspace not found: {n}"))?;
        (n, p)
    };
    let current = fs::canonicalize(run_jj_capture(["root", "--color=never"])?.stdout.trim()).ok();
    let target = fs::canonicalize(&path).unwrap_or(path.clone());
    if current.as_ref() == Some(&target) {
        bail!("refusing to forget the current workspace: {}\n\nChange to another directory first, then run `jj ws forget {name}`.", target.display());
    }
    if !parsed.force && workspace_has_unpublished_work(&target)? {
        bail!("workspace {name} has unpublished work at {}\n\nReview it first with:\n  jj --repository {} status\n\nIf this workspace was already pushed or merged, fetch remote refs and retry:\n  jj --repository {} git fetch\n\nUse --force to forget and delete anyway.", target.display(), target.display(), target.display());
    }
    let config = ws_config()?;
    let ctx = current_context(&config, None)?;
    let repo_config =
        load_workspace_repo_config(&path.join(WORKSPACE_REPO_CONFIG_FILE)).map_err(|err| {
            anyhow!(
                "{err:#}\n\nRefusing to forget workspace {name}; fix {} first.",
                path.join(WORKSPACE_REPO_CONFIG_FILE).display()
            )
        })?;
    let repo_preforget = if parsed.no_hooks {
        None
    } else {
        repo_config.as_ref().and_then(|c| c.preforget())
    };
    let has_compose = has_compose_file(&path);
    let remove_docker_volumes =
        parsed.docker_volumes || (config.docker_remove_volumes && !parsed.keep_docker_volumes);
    let builtin_docker_cleanup =
        !parsed.no_hooks && !parsed.no_docker && config.docker_cleanup == "auto" && has_compose;
    if parsed.dry_run {
        println!("would forget {name} at {}", path.display());
        if !parsed.keep_dir {
            if parsed.purge {
                println!("would delete {}", path.display());
            } else {
                println!(
                    "would move {} into {}",
                    path.display(),
                    ws_trash_dir(&ctx.workspace_root).display()
                );
            }
        }
        if let Some(preforget) = repo_preforget {
            for command in preforget {
                println!("would run: sh -c {command}");
            }
        } else if builtin_docker_cleanup {
            if remove_docker_volumes {
                println!("would run: docker compose down --remove-orphans --volumes");
            } else {
                println!("would run: docker compose down --remove-orphans");
            }
        }
        return Ok(());
    }
    if let Some(preforget) = repo_preforget {
        let target_root = fs::canonicalize(&path).unwrap_or_else(|_| path.clone());
        run_workspace_hooks(
            preforget,
            "preforget",
            &path,
            HookEnv {
                source: &target_root,
                dest: &target_root,
                name: &name,
                repo_root: &target_root,
            },
        )?;
    } else if builtin_docker_cleanup {
        let mut cmd = Command::new("docker");
        cmd.arg("compose")
            .arg("down")
            .arg("--remove-orphans")
            .current_dir(&path);
        if remove_docker_volumes {
            cmd.arg("--volumes");
        }
        run_status(&mut cmd, "docker compose down")?;
    }
    run_jj_status(["workspace", "forget", name.as_str()])?;
    if !parsed.keep_dir && path.exists() {
        if parsed.purge {
            fs::remove_dir_all(&path)
                .with_context(|| format!("failed to remove {}", path.display()))?;
        } else {
            let trashed = move_to_trash(&path, &name, &ctx.workspace_root)?;
            if !parsed.quiet {
                println!("moved workspace to {}", trashed.display());
            }
        }
    }
    if let Some(parent) = path.parent() {
        let _ = fs::remove_dir(parent);
    }
    if !parsed.quiet {
        println!("forgot workspace {name}");
    }
    Ok(())
}

pub(crate) fn workspace_has_unpublished_work(repo: &Path) -> Result<bool> {
    // A workspace is safe to discard only when every non-empty commit in its
    // stack is already reachable from a remote ref. An empty `@` is not enough:
    // agents may create a new empty working copy after leaving unpublished work
    // in `@-`, and forgetting that workspace would otherwise delete the only
    // checkout pointing at the unpublished stack.
    let unpublished_revset = "(::@ ~ ::(remote_bookmarks() | remote_tags())) ~ empty()";
    Ok(revset_has_commits_in(repo, unpublished_revset)?)
}

pub(crate) fn revset_has_commits_in(repo: &Path, revset: &str) -> Result<bool> {
    let output = Command::new("jj")
        .args([
            "log",
            "-r",
            revset,
            "-n",
            "1",
            "--no-graph",
            "--color=never",
            "-T",
            "commit_id",
        ])
        .current_dir(repo)
        .output()?;
    if !output.status.success() {
        return Ok(true);
    }
    Ok(!String::from_utf8(output.stdout)?.trim().is_empty())
}

pub(crate) fn has_compose_file(path: &Path) -> bool {
    [
        "compose.yaml",
        "compose.yml",
        "docker-compose.yaml",
        "docker-compose.yml",
    ]
    .iter()
    .any(|f| path.join(f).exists())
}

pub(crate) fn ws_prune(args: Vec<OsString>) -> Result<()> {
    let parsed = parse_ws_prune_args(args)?;
    let config = ws_config()?;
    let ctx = current_context(&config, None)?;
    let registered: Vec<PathBuf> = workspace_entries()?
        .into_iter()
        .map(|(_, p)| fs::canonicalize(&p).unwrap_or(PathBuf::from(p)))
        .collect();
    let children = collect_workspace_children(&ctx.workspace_root);
    let mut stale = stale_workspace_dirs(&children, &registered);
    if parsed.pick {
        let lines: Vec<String> = stale.iter().map(|p| p.display().to_string()).collect();
        stale = pick_multi("Prune workspaces", &lines)?
            .into_iter()
            .map(PathBuf::from)
            .collect();
    }
    if parsed.delete && !parsed.dry_run {
        for p in &stale {
            let name = p
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "stale".to_string());
            move_to_trash(p, &name, &ctx.workspace_root)?;
        }
    } else {
        for p in &stale {
            println!("{}", p.display());
        }
    }
    Ok(())
}

pub(crate) fn collect_workspace_children(workspace_root: &Path) -> Vec<PathBuf> {
    let mut children = Vec::new();
    if workspace_root.exists() {
        if let Ok(entries) = fs::read_dir(workspace_root) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_dir() && p.file_name() != Some(OsStr::new(".trash")) {
                    children.push(p);
                }
            }
        }
    }
    children
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct WsGcArgs {
    pub(crate) older_than: Option<String>,
    pub(crate) dry_run: bool,
}

pub(crate) fn parse_ws_gc_args(args: Vec<OsString>) -> Result<WsGcArgs> {
    let mut parsed = WsGcArgs::default();
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        if arg == OsStr::new("--older-than") {
            parsed.older_than =
                Some(os_to_string(iter.next().ok_or_else(|| {
                    anyhow!("missing duration after --older-than")
                })?)?);
        } else if let Some(value) = take_value_after_prefix(&arg, "--older-than=")? {
            parsed.older_than = Some(value);
        } else if arg == OsStr::new("--dry-run") {
            parsed.dry_run = true;
        } else if arg == OsStr::new("-h") || arg == OsStr::new("--help") {
            print_ws_gc_usage();
            return Ok(parsed);
        } else {
            bail!(
                "unknown argument: {}\n\nUsage: jj ws gc [--older-than <duration>] [--dry-run]",
                arg.to_string_lossy()
            );
        }
    }
    Ok(parsed)
}

pub(crate) fn ws_gc(args: Vec<OsString>) -> Result<()> {
    let parsed = parse_ws_gc_args(args)?;
    let config = ws_config()?;
    let ctx = current_context(&config, None)?;
    let retention_raw = parsed.older_than.unwrap_or_else(|| {
        jj_config_string("dotfiles.workspaces.trash-retention")
            .ok()
            .flatten()
            .unwrap_or_else(|| DEFAULT_TRASH_RETENTION.to_string())
    });
    let retention_secs = parse_retention_seconds(&retention_raw)?;
    let trash = ws_trash_dir(&ctx.workspace_root);
    let now = unix_now_secs();
    let mut entries: Vec<PathBuf> = Vec::new();
    match fs::symlink_metadata(&trash) {
        Ok(metadata) if metadata.file_type().is_dir() => {
            for entry in fs::read_dir(&trash)? {
                entries.push(entry?.path());
            }
        }
        Ok(_) => {
            eprintln!(
                "skipping trash path that is not a directory: {}",
                trash.display()
            );
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(error).with_context(|| format!("failed to inspect {}", trash.display()));
        }
    }
    entries.sort();
    for path in entries {
        let Some(name) = path.file_name().map(|n| n.to_string_lossy().to_string()) else {
            continue;
        };
        let Some(timestamp) = parse_trash_entry_timestamp(&name) else {
            eprintln!("skipping unrecognized trash entry: {}", path.display());
            continue;
        };
        let age_secs = now.saturating_sub(timestamp);
        if !trash_entry_is_expired(age_secs, retention_secs) {
            continue;
        }
        if parsed.dry_run {
            println!(
                "would delete {} (age {})",
                path.display(),
                format_duration(age_secs)
            );
        } else {
            let result = match fs::symlink_metadata(&path) {
                Ok(metadata) if metadata.file_type().is_dir() => fs::remove_dir_all(&path),
                Ok(_) => fs::remove_file(&path),
                Err(error) => {
                    eprintln!(
                        "warning: failed to inspect trash entry {}: {}",
                        path.display(),
                        error
                    );
                    continue;
                }
            };
            if let Err(error) = result {
                eprintln!(
                    "warning: failed to delete trash entry {}: {}",
                    path.display(),
                    error
                );
                continue;
            }
            println!(
                "deleted {} (age {})",
                path.display(),
                format_duration(age_secs)
            );
        }
    }
    Ok(())
}

pub(crate) const DEFAULT_TRASH_RETENTION: &str = "7d";

pub(crate) fn ws_trash_dir(workspace_root: &Path) -> PathBuf {
    workspace_root.join(".trash")
}

pub(crate) fn unix_now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub(crate) fn parse_retention_seconds(raw: &str) -> Result<u64> {
    let raw = raw.trim();
    let invalid = || {
        anyhow!(
            "invalid duration {raw:?}; use a positive integer followed by h, d, or w (for example 12h, 7d, 2w)"
        )
    };
    if raw.len() < 2 {
        return Err(invalid());
    }
    let (digits, unit) = raw.split_at(raw.len() - 1);
    if !digits
        .bytes()
        .next()
        .is_some_and(|byte| byte.is_ascii_digit())
    {
        return Err(invalid());
    }
    let multiplier: u64 = match unit {
        "h" => 3600,
        "d" => 86_400,
        "w" => 604_800,
        _ => return Err(invalid()),
    };
    let value: u64 = digits.parse().map_err(|_| invalid())?;
    value.checked_mul(multiplier).ok_or_else(invalid)
}

/// Trash entries are named `<unix-seconds>-<name>` with an optional trailing
/// `-<n>` collision suffix; extract the leading timestamp.
pub(crate) fn parse_trash_entry_timestamp(entry: &str) -> Option<u64> {
    let (timestamp, _) = entry.split_once('-')?;
    timestamp.parse::<u64>().ok()
}

pub(crate) fn trash_entry_is_expired(age_secs: u64, retention_secs: u64) -> bool {
    age_secs >= retention_secs
}

pub(crate) fn format_duration(secs: u64) -> String {
    if secs >= 86_400 {
        format!("{}d", secs / 86_400)
    } else if secs >= 3600 {
        format!("{}h", secs / 3600)
    } else {
        format!("{}s", secs)
    }
}

pub(crate) fn move_to_trash(path: &Path, name: &str, workspace_root: &Path) -> Result<PathBuf> {
    let trash = ws_trash_dir(workspace_root);
    fs::create_dir_all(&trash).with_context(|| format!("failed to create {}", trash.display()))?;
    let secs = unix_now_secs();
    let mut candidate = trash.join(format!("{secs}-{name}"));
    let mut suffix: u32 = 0;
    while candidate.exists() {
        suffix += 1;
        candidate = trash.join(format!("{secs}-{name}-{suffix}"));
    }
    // Same-filesystem rename only; on failure the source directory stays in
    // place and no copy fallback is attempted.
    fs::rename(path, &candidate).with_context(|| {
        format!(
            "failed to move {} into trash at {}; the directory was left in place",
            path.display(),
            candidate.display()
        )
    })?;
    Ok(candidate)
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct WsPruneArgs {
    pub(crate) delete: bool,
    pub(crate) pick: bool,
    pub(crate) dry_run: bool,
    pub(crate) yes: bool,
}

pub(crate) fn parse_ws_prune_args(args: Vec<OsString>) -> Result<WsPruneArgs> {
    let mut parsed = WsPruneArgs::default();
    for arg in args {
        match arg.to_string_lossy().as_ref() {
            "--delete" => parsed.delete = true,
            "--pick" => parsed.pick = true,
            "--dry-run" => parsed.dry_run = true,
            "--yes" => parsed.yes = true,
            "-h" | "--help" => print_ws_prune_usage(),
            other if other.starts_with('-') => bail!("unknown option: {other}"),
            _ => bail!("unexpected argument: {}\n\nUsage: jj ws prune [--dry-run] [--delete] [--pick] [--yes]", arg.to_string_lossy()),
        }
    }
    Ok(parsed)
}

pub(crate) fn stale_workspace_dirs(children: &[PathBuf], registered: &[PathBuf]) -> Vec<PathBuf> {
    children
        .iter()
        .filter(|p| !registered.contains(&fs::canonicalize(p).unwrap_or_else(|_| (*p).clone())))
        .cloned()
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct WsDuArgs {
    pub(crate) help: bool,
}

pub(crate) fn parse_ws_du_args(args: Vec<OsString>) -> Result<WsDuArgs> {
    let mut parsed = WsDuArgs::default();
    for arg in args {
        match arg.to_string_lossy().as_ref() {
            "-h" | "--help" => parsed.help = true,
            other => bail!("unknown option: {other}\n\nUsage: jj ws du"),
        }
    }
    Ok(parsed)
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct WsSweepArgs {
    pub(crate) idle: Option<String>,
    pub(crate) dry_run: bool,
    pub(crate) help: bool,
}

pub(crate) fn parse_ws_sweep_args(args: Vec<OsString>) -> Result<WsSweepArgs> {
    let mut parsed = WsSweepArgs::default();
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.to_string_lossy().as_ref() {
            "--idle" => {
                parsed.idle = Some(os_to_string(
                    iter.next()
                        .ok_or_else(|| anyhow!("missing duration after --idle"))?,
                )?)
            }
            "--dry-run" => parsed.dry_run = true,
            "-h" | "--help" => parsed.help = true,
            _ => {
                if let Some(value) = take_value_after_prefix(&arg, "--idle=")? {
                    parsed.idle = Some(value);
                } else {
                    bail!(
                        "unknown option: {}\n\nUsage: jj ws sweep [--idle <duration>] [--dry-run]",
                        arg.to_string_lossy()
                    );
                }
            }
        }
    }
    Ok(parsed)
}

/// Parses durations like `12h`, `14d`, `2w`. Zero is allowed for smoke tests.
pub(crate) fn parse_idle_duration(raw: &str) -> Result<Duration> {
    let raw = raw.trim();
    let Some(split) = raw.char_indices().next_back() else {
        bail!("empty idle duration");
    };
    let (num, unit) = raw.split_at(split.0);
    if !num.starts_with(|c: char| c.is_ascii_digit()) {
        bail!("invalid idle duration {raw:?}; use a positive integer followed by h, d, or w");
    }
    let unit_multiplier: u64 = match unit {
        "h" => 3600,
        "d" => 24 * 3600,
        "w" => 7 * 24 * 3600,
        _ => bail!("invalid idle duration {raw:?}; use a positive integer followed by h, d, or w"),
    };
    let value: u64 = num
        .parse()
        .with_context(|| format!("invalid idle duration {raw:?}; expected integer + h/d/w"))?;
    let secs = value.checked_mul(unit_multiplier).with_context(|| {
        format!("idle duration {raw:?} overflows; use a smaller value with h, d, or w")
    })?;
    Ok(Duration::from_secs(secs))
}

/// A workspace is sweepable once it has been idle for at least the threshold;
/// exactly-at-threshold counts as idle.
pub(crate) fn sweepable(idle: Duration, threshold: Duration) -> bool {
    idle >= threshold
}

pub(crate) fn path_is_contained(path: &Path, root: &Path) -> bool {
    path != root && path.starts_with(root)
}

#[derive(Debug, Default)]
pub(crate) struct WorkspaceUsage {
    pub(crate) total: u64,
    pub(crate) other: u64,
    pub(crate) class: HashMap<String, u64>,
    pub(crate) last_touched: Option<SystemTime>,
    pub(crate) artifact_paths: Vec<(PathBuf, u64)>,
}

impl WorkspaceUsage {
    fn touch(&mut self, time: SystemTime) {
        self.last_touched = Some(match self.last_touched {
            Some(prev) if prev >= time => prev,
            _ => time,
        });
    }
}

/// Recursively measures apparent bytes under `dir`, charging directories whose
/// basename matches `artifacts` to their class and everything else to `other`.
/// Returns `(total_apparent_bytes, classified_bytes)`; callers attribute the
/// unclassified remainder so nested artifacts are never double-counted.
/// Symlinks are measured as links and never followed; `.jj` is measured but
/// excluded from last-touch tracking and artifact collection.
pub(crate) fn measure_tree(
    dir: &Path,
    artifacts: &[String],
    usage: &mut WorkspaceUsage,
    track_time: bool,
) -> (u64, u64) {
    let mut total = 0u64;
    let mut classified = 0u64;
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(err) => {
            eprintln!("warning: cannot read {}: {err}", dir.display());
            return (0, 0);
        }
    };
    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            Err(err) => {
                eprintln!("warning: skipping entry in {}: {err}", dir.display());
                continue;
            }
        };
        let path = entry.path();
        let metadata = match fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(err) => {
                eprintln!("warning: cannot stat {}: {err}", path.display());
                continue;
            }
        };
        if metadata.is_symlink() {
            if track_time {
                if let Ok(mtime) = metadata.modified() {
                    usage.touch(mtime);
                }
            }
            total += metadata.len();
        } else if metadata.is_dir() {
            let name = entry.file_name().to_string_lossy().to_string();
            let in_jj = name == ".jj";
            let child_track = track_time && !in_jj;
            if !in_jj && artifacts.iter().any(|a| a == &name) {
                // Artifact-internal mtimes never count toward last-touch;
                // freshly built artifacts must not keep a workspace non-idle.
                let (bytes, nested_classified) = measure_tree(&path, artifacts, usage, false);
                *usage.class.entry(name.clone()).or_default() += bytes - nested_classified;
                usage.artifact_paths.push((path.clone(), bytes));
                total += bytes;
                classified += bytes;
            } else {
                if child_track {
                    if let Ok(mtime) = metadata.modified() {
                        usage.touch(mtime);
                    }
                }
                let (bytes, nested_classified) = measure_tree(&path, artifacts, usage, child_track);
                total += bytes;
                classified += nested_classified;
            }
        } else {
            if track_time {
                if let Ok(mtime) = metadata.modified() {
                    usage.touch(mtime);
                }
            }
            total += metadata.len();
        }
    }
    (total, classified)
}

pub(crate) fn scan_workspace(
    root: &Path,
    artifacts: &[String],
) -> Result<(WorkspaceUsage, Option<SystemTime>)> {
    let mut usage = WorkspaceUsage::default();
    let (total, classified) = measure_tree(root, artifacts, &mut usage, true);
    usage.total = total;
    usage.other = total - classified;
    let fallback = fs::symlink_metadata(root)
        .and_then(|meta| meta.modified())
        .ok();
    let last_touched = usage.last_touched.or(fallback);
    Ok((usage, last_touched))
}

/// Registered managed workspaces as canonical paths under the workspace root,
/// including the current workspace. Paths that escape the canonical workspace
/// root are skipped with a warning.
pub(crate) fn managed_workspace_candidates(
    ctx: &WorkspaceContext,
) -> Result<Vec<(String, PathBuf)>> {
    let output = run_jj_capture([
        "workspace",
        "list",
        "--color=never",
        "-T",
        "self.name() ++ \"\\n\"",
    ])?;
    let canon_root =
        fs::canonicalize(&ctx.workspace_root).unwrap_or_else(|_| ctx.workspace_root.clone());
    let mut candidates = Vec::new();
    for name in output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|n| !n.is_empty())
    {
        let raw = ctx.workspace_root.join(name);
        let path = fs::canonicalize(&raw).unwrap_or(raw);
        if !path_is_contained(&path, &canon_root) {
            eprintln!(
                "warning: skipping {name}: {} is outside workspace root {}",
                path.display(),
                canon_root.display()
            );
            continue;
        }
        candidates.push((name.to_string(), path));
    }
    Ok(candidates)
}

/// Name and canonical root of the workspace the command runs in.
pub(crate) fn current_workspace_identity(ctx: &WorkspaceContext) -> Result<(String, PathBuf)> {
    let name = jj_config_string("workspace.name")?.unwrap_or_else(|| "default".to_string());
    let root = fs::canonicalize(run_jj_capture(["root", "--color=never"])?.stdout.trim())
        .unwrap_or(ctx.repo_root.clone());
    Ok((name, root))
}

pub(crate) fn unix_seconds(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub(crate) fn ws_du(args: Vec<OsString>) -> Result<()> {
    let parsed = parse_ws_du_args(args)?;
    if parsed.help {
        print_ws_du_usage();
        return Ok(());
    }
    let config = ws_config()?;
    let ctx = current_context(&config, None)?;
    let candidates = managed_workspace_candidates(&ctx)?;
    let mut header = vec![
        "NAME".to_string(),
        "PATH".to_string(),
        "TOTAL_BYTES".to_string(),
    ];
    header.extend(config.clone_artifacts.iter().cloned());
    header.push("OTHER_BYTES".to_string());
    header.push("LAST_TOUCHED".to_string());
    header.push("IDLE".to_string());
    println!("{}", header.join("\t"));
    let now = SystemTime::now();
    for (name, path) in candidates {
        let (usage, last_touched) = scan_workspace(&path, &config.clone_artifacts)?;
        let mut row = vec![name, path.display().to_string(), usage.total.to_string()];
        for artifact in &config.clone_artifacts {
            row.push(usage.class.get(artifact).copied().unwrap_or(0).to_string());
        }
        row.push(usage.other.to_string());
        row.push(
            last_touched
                .map(unix_seconds)
                .map(|s| s.to_string())
                .unwrap_or_else(|| "-".to_string()),
        );
        row.push(
            last_touched
                .map(|t| now.duration_since(t).map(|d| d.as_secs()).unwrap_or(0))
                .map(|s| s.to_string())
                .unwrap_or_else(|| "-".to_string()),
        );
        println!("{}", row.join("\t"));
    }
    Ok(())
}

/// Keeps only artifact paths not contained in another candidate; removing an
/// outer directory already removes anything nested inside it.
pub(crate) fn top_level_artifact_paths(paths: Vec<(PathBuf, u64)>) -> Vec<(PathBuf, u64)> {
    let mut kept: Vec<(PathBuf, u64)> = Vec::new();
    for (path, bytes) in paths {
        if kept
            .iter()
            .any(|(outer, _)| path_is_contained(&path, outer))
        {
            continue;
        }
        kept.retain(|(inner, _)| !path_is_contained(inner, &path));
        kept.push((path, bytes));
    }
    kept
}

pub(crate) fn ws_sweep(args: Vec<OsString>) -> Result<()> {
    let parsed = parse_ws_sweep_args(args)?;
    if parsed.help {
        print_ws_sweep_usage();
        return Ok(());
    }
    let config = ws_config()?;
    let threshold = match &parsed.idle {
        Some(raw) => parse_idle_duration(raw)?,
        None => parse_idle_duration(&config.sweep_idle)?,
    };
    let ctx = current_context(&config, None)?;
    let (current_name, current_root) = current_workspace_identity(&ctx)?;
    // Sweep never touches the workspace it runs in.
    let candidates: Vec<_> = managed_workspace_candidates(&ctx)?
        .into_iter()
        .filter(|(name, path)| name != &current_name && path != &current_root)
        .collect();
    let now = SystemTime::now();
    let mut total_bytes = 0u64;
    let mut total_removed = 0usize;
    for (_, path) in candidates {
        let (usage, last_touched) = scan_workspace(&path, &config.clone_artifacts)?;
        let Some(last_touched) = last_touched else {
            continue;
        };
        let idle = now.duration_since(last_touched).unwrap_or(Duration::ZERO);
        if !sweepable(idle, threshold) {
            continue;
        }
        for (artifact_path, bytes) in top_level_artifact_paths(usage.artifact_paths) {
            if parsed.dry_run {
                println!("would remove {}\t{bytes}", artifact_path.display());
            } else {
                match fs::remove_dir_all(&artifact_path) {
                    Ok(()) => {
                        println!("removed {}\t{bytes}", artifact_path.display());
                        total_bytes += bytes;
                        total_removed += 1;
                    }
                    Err(err) => {
                        eprintln!(
                            "warning: failed to remove {}: {err}",
                            artifact_path.display()
                        );
                    }
                }
            }
        }
    }
    if !parsed.dry_run {
        println!("swept {total_bytes} bytes from {total_removed} artifact directories");
    }
    Ok(())
}

pub(crate) fn pick_lines(prompt: &str, lines: &[String]) -> Result<Option<String>> {
    Ok(pick_multi(prompt, lines)?.into_iter().next())
}

pub(crate) fn pick_multi(prompt: &str, lines: &[String]) -> Result<Vec<String>> {
    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!("--pick requires an interactive terminal");
    }
    if which::which("fzf").is_err() {
        bail!("--pick requires fzf");
    }
    let mut child = Command::new("fzf")
        .arg("--multi")
        .arg("--prompt")
        .arg(format!("{prompt}> "))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;
    {
        let stdin = child
            .stdin
            .as_mut()
            .ok_or_else(|| anyhow!("failed to open fzf stdin"))?;
        for line in lines {
            writeln!(stdin, "{line}")?;
        }
    }
    let output = child.wait_with_output()?;
    if !output.status.success() {
        return Ok(Vec::new());
    }
    Ok(String::from_utf8(output.stdout)?
        .lines()
        .map(str::to_string)
        .collect())
}

use anyhow::{anyhow, bail, Context, Result};
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn main() {
    if let Err(err) = run() {
        eprintln!("Error: {err:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let mut args = env::args_os();
    let program = args.next().unwrap_or_else(|| OsString::from("jj-workflow"));

    let command = match args.next() {
        Some(command) => command,
        None => {
            print_usage(&program);
            bail!("missing subcommand");
        }
    };

    match command.to_string_lossy().as_ref() {
        "ship" => run_ship(parse_common_args(args.collect())?),
        "sync" => run_sync(parse_common_args(args.collect())?),
        "ws" | "workspace" => run_ws(args.collect()),
        "-h" | "--help" | "help" => {
            print_usage(&program);
            Ok(())
        }
        other => {
            print_usage(&program);
            bail!("unknown subcommand: {other}")
        }
    }
}

fn print_usage(program: &OsStr) {
    let name = program.to_string_lossy();
    eprintln!(
        "Usage:\n  {name} ship [-b|--bookmark <bookmark>] [--remote <remote>] [-- <jj git push args...>]\n  {name} sync [-b|--bookmark <bookmark>] [--remote <remote>] [--onto <revset>] [-- <jj rebase args...>]\n  {name} ws <add|list|path|forget|prune|root> ..."
    );
}

#[derive(Debug, Default, PartialEq, Eq)]
struct ParsedArgs {
    bookmark_input: Option<String>,
    remote_input: Option<String>,
    onto: Option<String>,
    help: bool,
    quiet: bool,
    json: bool,
    noninteractive: bool,
    fail_on_conflicts: bool,
    passthrough: Vec<OsString>,
}

fn parse_common_args(args: Vec<OsString>) -> Result<ParsedArgs> {
    let mut parsed = ParsedArgs::default();
    let mut iter = args.into_iter();

    while let Some(arg) = iter.next() {
        if arg == OsStr::new("--") {
            parsed.passthrough.extend(iter);
            break;
        }

        if arg == OsStr::new("-b") || arg == OsStr::new("--bookmark") {
            let value = iter
                .next()
                .ok_or_else(|| anyhow!("missing value for {}", arg.to_string_lossy()))?;
            parsed.bookmark_input = Some(os_to_string(value)?);
            continue;
        }

        if let Some(value) = take_value_after_prefix(&arg, "--bookmark=")? {
            parsed.bookmark_input = Some(value);
            continue;
        }

        if arg == OsStr::new("--remote") {
            let value = iter
                .next()
                .ok_or_else(|| anyhow!("missing value for {}", arg.to_string_lossy()))?;
            parsed.remote_input = Some(os_to_string(value)?);
            continue;
        }

        if arg == OsStr::new("--onto") {
            let value = iter
                .next()
                .ok_or_else(|| anyhow!("missing value for {}", arg.to_string_lossy()))?;
            parsed.onto = Some(os_to_string(value)?);
            continue;
        }

        if let Some(value) = take_value_after_prefix(&arg, "--onto=")? {
            parsed.onto = Some(value);
            continue;
        }

        if let Some(value) = take_value_after_prefix(&arg, "--remote=")? {
            parsed.remote_input = Some(value);
            continue;
        }

        if arg == OsStr::new("-h") || arg == OsStr::new("--help") {
            parsed.help = true;
            continue;
        }

        if arg == OsStr::new("-q") || arg == OsStr::new("--quiet") {
            parsed.quiet = true;
            continue;
        }

        if arg == OsStr::new("--json") {
            parsed.json = true;
            parsed.quiet = true;
            parsed.noninteractive = true;
            continue;
        }

        if arg == OsStr::new("--noninteractive") {
            parsed.noninteractive = true;
            continue;
        }

        if arg == OsStr::new("--fail-on-conflicts") {
            parsed.fail_on_conflicts = true;
            continue;
        }

        parsed.passthrough.push(arg);
    }

    Ok(parsed)
}

fn take_value_after_prefix(arg: &OsStr, prefix: &str) -> Result<Option<String>> {
    let arg = arg
        .to_str()
        .ok_or_else(|| anyhow!("argument contains invalid UTF-8"))?;
    Ok(arg
        .strip_prefix(prefix)
        .map(std::string::ToString::to_string))
}

fn os_to_string(value: OsString) -> Result<String> {
    value
        .into_string()
        .map_err(|_| anyhow!("argument contains invalid UTF-8"))
}

fn run_ship(mut args: ParsedArgs) -> Result<()> {
    if args.help {
        print_ship_usage();
        return Ok(());
    }

    // Run lints before changing bookmarks. The `jj push` alias also runs lints,
    // but doing it there means a lint failure can leave an integration bookmark
    // moved locally and then require manual recovery. Ship should fail early
    // while the repo graph is still untouched.
    run_jj_status(["lint"])?;

    let plan = ship_plan(has_working_copy_changes()?);

    if plan.create_new_working_copy {
        run_jj_status(["new"])?;
    }

    let target = plan.target_rev.to_string();

    let bookmark = if let Some(bookmark_input) = args.bookmark_input.take() {
        if let Some((bookmark, remote)) = split_bookmark_remote(&bookmark_input) {
            if args.remote_input.is_none() {
                args.remote_input = Some(remote.to_string());
            }
            bookmark.to_string()
        } else {
            bookmark_input
        }
    } else {
        resolve_ship_bookmark(&target)?
    };

    if bookmark.is_empty() {
        bail!("bookmark cannot be empty");
    }

    let target_id = commit_id(&target)?
        .ok_or_else(|| anyhow!("no parent change to ship from the current working copy"))?;

    if commit_is_empty(&target)? {
        bail!(
            "refusing to ship empty target {target}. Create or select a non-empty change, or pass --bookmark <name> for the intended change"
        );
    }

    let remote = resolve_bookmark_remote(&bookmark, args.remote_input.as_deref())?;
    let bookmark_id = commit_id(&bookmark)?;

    let bookmark_changed = bookmark_id.as_deref() != Some(target_id.as_str());
    if bookmark_changed {
        run_jj_status(["bookmark", "set", bookmark.as_str(), "-r", target.as_str()])?;
    }

    let mut push_args = vec![
        OsString::from("git"),
        OsString::from("push"),
        OsString::from("--bookmark"),
        OsString::from(&bookmark),
        OsString::from("--remote"),
        OsString::from(&remote),
    ];
    push_args.extend(args.passthrough);

    if let Err(push_err) = run_jj_status_os(push_args) {
        if bookmark_changed {
            if let Err(rollback_err) = rollback_bookmark(&bookmark, bookmark_id.as_deref()) {
                let recovery_hint = bookmark_id
                    .as_deref()
                    .map(|target| format!("jj bookmark set {bookmark} -r {target}"))
                    .unwrap_or_else(|| format!("jj bookmark forget {bookmark}"));
                bail!(
                    "{push_err}\nAlso failed to restore bookmark {bookmark}: {rollback_err:#}\nManual recovery: {recovery_hint}"
                );
            }

            bail!(
                "{push_err}\nRolled back local bookmark {bookmark} to its previous target after the failed push."
            );
        }

        return Err(push_err);
    }

    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ShipPlan {
    create_new_working_copy: bool,
    target_rev: &'static str,
}

fn ship_plan(has_working_copy_changes: bool) -> ShipPlan {
    // `jj ship` should always ship the parent of the working copy. If the working
    // copy still has file changes, create a fresh empty working copy first so the
    // finished change moves to `@-`. If the working copy is already empty (for
    // example after `jj new`), ship `@-` directly instead of pushing an empty
    // working-copy commit to an integration bookmark.
    ShipPlan {
        create_new_working_copy: has_working_copy_changes,
        target_rev: "@-",
    }
}

fn run_sync(mut args: ParsedArgs) -> Result<()> {
    if args.help {
        print_sync_usage();
        return Ok(());
    }

    let configured_remote = jj_config_string("dotfiles.sync.remote")?;
    let mut remote_for_fetch = args.remote_input.clone().or(configured_remote);

    let base_rev = if let Some(onto) = args.onto.take() {
        onto
    } else if let Some(bookmark_input) = args.bookmark_input.take() {
        if let Some((_bookmark, remote)) = split_bookmark_remote(&bookmark_input) {
            if args.remote_input.is_none() {
                remote_for_fetch = Some(remote.to_string());
            }
        }
        bookmark_input
    } else {
        resolve_sync_base(remote_for_fetch.as_deref(), args.noninteractive)?
    };

    if remote_for_fetch.is_none() {
        if let Some((_bookmark, remote)) = split_bookmark_remote(&base_rev) {
            remote_for_fetch = Some(remote.to_string());
        }
    }

    if !args.quiet && !args.json {
        if let Some(remote) = remote_for_fetch.as_deref() {
            eprintln!("Sync base: {base_rev}; fetching remote: {remote}");
        } else {
            eprintln!("Sync base: {base_rev}; fetching all remotes");
        }
    }

    if let Some(remote) = remote_for_fetch.as_deref() {
        if args.quiet || args.json {
            run_jj_capture(["git", "fetch", "--remote", remote])?;
        } else {
            run_jj_status(["git", "fetch", "--remote", remote])?;
        }
    } else if args.quiet || args.json {
        run_jj_capture(["git", "fetch"])?;
    } else {
        run_jj_status(["git", "fetch"])?;
    }

    if base_rev != "trunk()" && commit_id(&base_rev)?.is_none() {
        bail!("sync base '{base_rev}' not found after fetch")
    }

    let mut rebase_args = vec![
        OsString::from("rebase"),
        OsString::from("-d"),
        OsString::from(&base_rev),
    ];
    rebase_args.extend(args.passthrough);
    if args.quiet || args.json {
        run_jj_capture_os(rebase_args)?;
    } else {
        run_jj_status_os(rebase_args)?;
    }

    let conflicts = conflicted_changes()?;
    if args.json {
        print_sync_json(&base_rev, remote_for_fetch.as_deref(), &conflicts);
    } else if conflicts.is_empty() {
        if args.quiet {
            println!("{base_rev}");
        } else {
            eprintln!("Sync complete: rebased current branch/stack onto {base_rev}");
        }
    } else {
        eprintln!("Warning: sync completed with conflicts.");
        eprintln!("Conflicted changes:");
        for conflict in &conflicts {
            eprintln!(" - {conflict}");
        }
        eprintln!("Next: load jj-conflict-resolution, then run `jj resolve --list`.");
    }

    if args.fail_on_conflicts && !conflicts.is_empty() {
        bail!("sync completed with conflicts")
    }

    Ok(())
}

#[derive(Debug, Clone)]
struct ProjectGroup {
    path: PathBuf,
    workspace_dir: String,
}

#[derive(Debug, Clone)]
struct WsConfig {
    project_groups: Vec<ProjectGroup>,
    copy_envrc: String,
    direnv_allow: bool,
    docker_cleanup: String,
    docker_remove_volumes: bool,
    fetch_remote: Option<String>,
}

#[derive(Debug, Clone)]
struct WorkspaceContext {
    repo_root: PathBuf,
    workspace_root: PathBuf,
    managed_workspace: bool,
}

fn run_ws(args: Vec<OsString>) -> Result<()> {
    let mut iter = args.into_iter();
    let Some(sub) = iter.next() else {
        print_ws_usage();
        return Ok(());
    };
    let rest: Vec<_> = iter.collect();
    match sub.to_string_lossy().as_ref() {
        "add" => ws_add(rest),
        "list" => ws_list(rest),
        "path" => ws_path(rest),
        "forget" | "rm" => ws_forget(rest),
        "prune" => ws_prune(rest),
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

fn print_ws_usage() {
    eprintln!("Usage:\n  jj ws add <name> [-r <revset>] [-q]\n  jj ws list [--pick]\n  jj ws path <name>|--pick\n  jj ws forget <name>|--pick [--force] [--dry-run] [-q]\n  jj ws prune [--delete] [--pick]\n  jj ws root\n\nExamples:\n  jj ws add feature-x -q\n  cd \"$(jj ws path feature-x)\"\n  jj ws forget feature-x\n\nPath: <project-group>/<workspace-dir>/<repo>/<workspace>\nHelp: jj ws <command> --help");
}

fn print_ws_add_usage() {
    eprintln!("Usage:\n  jj ws add <name> [-r <revset>] [--project-group <path>] [--no-envrc] [--no-direnv] [-q]\n\nCreates <project-group>/<workspace-dir>/<repo>/<name>.\nDefault base: main checkout -> inferred remote bookmark; workspace -> @.\n\nExamples:\n  jj ws add feature-x -q\n  jj ws add followup -r @\n  jj ws add hotfix --revision main@origin");
}

fn print_ws_list_usage() {
    eprintln!("Usage:\n  jj ws list [--pick]\n\nLists workspaces for this repo. --pick requires an interactive terminal.");
}

fn print_ws_path_usage() {
    eprintln!("Usage:\n  jj ws path <name>\n  jj ws path --pick\n\nPrints only the workspace path. --pick requires an interactive terminal.");
}

fn print_ws_forget_usage() {
    eprintln!("Usage:\n  jj ws forget <name> [--force] [--keep-dir] [--no-docker] [--docker-volumes] [--dry-run] [-q]\n  jj ws forget --pick [options]\n\nForgets and deletes a workspace. Refuses current/non-empty work unless --force.\n\nExamples:\n  jj ws forget feature-x --dry-run\n  jj ws forget feature-x\n  jj ws forget scratch --force -q");
}

fn print_ws_prune_usage() {
    eprintln!("Usage:\n  jj ws prune [--dry-run] [--delete] [--pick] [--yes]\n\nPrints stale workspace dirs. Use --delete to remove them. --pick requires a terminal.");
}

fn print_ws_root_usage() {
    eprintln!("Usage:\n  jj ws root\n\nPrints this repo's managed workspace root.");
}

fn ws_config() -> Result<WsConfig> {
    let copy_envrc = jj_config_string("dotfiles.workspaces.copy-envrc")?
        .unwrap_or_else(|| "untracked".to_string());
    let direnv_allow = jj_config_bool("dotfiles.workspaces.direnv-allow")?.unwrap_or(true);
    let docker_cleanup = jj_config_string("dotfiles.workspaces.docker-cleanup")?
        .unwrap_or_else(|| "auto".to_string());
    let docker_remove_volumes =
        jj_config_bool("dotfiles.workspaces.docker-remove-volumes")?.unwrap_or(false);
    let fetch_remote = jj_config_string("dotfiles.workspaces.fetch-remote")?;
    let groups = jj_config_project_groups()?;
    Ok(WsConfig {
        project_groups: groups,
        copy_envrc,
        direnv_allow,
        docker_cleanup,
        docker_remove_volumes,
        fetch_remote,
    })
}

fn jj_config_string(key: &str) -> Result<Option<String>> {
    let output = run_jj_capture_allow_failure(["config", "get", key])?;
    if !output.status.success() {
        return Ok(None);
    }
    let value = output.stdout.trim().trim_matches('"').to_string();
    Ok((!value.is_empty()).then_some(value))
}

fn jj_config_bool(key: &str) -> Result<Option<bool>> {
    Ok(
        jj_config_string(key)?.and_then(|value| match value.as_str() {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        }),
    )
}

fn jj_config_project_groups() -> Result<Vec<ProjectGroup>> {
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

fn parse_toml_string_array(raw: &str) -> Vec<String> {
    raw.trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .split(',')
        .map(|part| part.trim().trim_matches('"').trim_matches('\''))
        .filter(|part| !part.is_empty())
        .map(std::string::ToString::to_string)
        .collect()
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}

fn current_context(config: &WsConfig, override_group: Option<PathBuf>) -> Result<WorkspaceContext> {
    let repo_root = PathBuf::from(run_jj_capture(["root", "--color=never"])?.stdout.trim());
    let repo_root = fs::canonicalize(&repo_root).unwrap_or(repo_root);
    workspace_context_for_repo(&repo_root, config, override_group)
}

fn workspace_context_for_repo(
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
            .filter(|group| repo_root.starts_with(&group.path))
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

fn validate_ws_name(name: &str) -> Result<()> {
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
struct WsAddArgs {
    name: String,
    revision: Option<String>,
    project_group: Option<PathBuf>,
    quiet: bool,
    no_envrc: bool,
    no_direnv: bool,
    help: bool,
}

fn parse_ws_add_args(args: Vec<OsString>) -> Result<WsAddArgs> {
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
        } else if arg == OsStr::new("--no-direnv") {
            parsed.no_direnv = true;
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
    Ok(parsed)
}

fn ws_add(args: Vec<OsString>) -> Result<()> {
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
    run_jj_status_os(vec![
        OsString::from("workspace"),
        OsString::from("add"),
        OsString::from("--name"),
        OsString::from(&name),
        OsString::from("--revision"),
        OsString::from(&base),
        dest.clone().into_os_string(),
    ])?;
    let mut copied_envrc = false;
    let mut direnv_allowed = false;
    if !parsed.no_envrc && config.copy_envrc != "never" {
        copied_envrc = copy_envrc_if_needed(&ctx.repo_root, &dest, &config.copy_envrc)?;
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
    if parsed.quiet {
        println!("{}", dest.display());
    } else {
        println!("created workspace {name} at {}", dest.display());
        println!("base: {base}");
        if copied_envrc {
            println!("copied untracked .envrc");
        }
        if direnv_allowed {
            println!("direnv allowed");
        }
    }
    Ok(())
}

fn fetch_for_workspace(config: &WsConfig) -> Result<()> {
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
enum FetchChoice {
    None,
    Fetch(String),
    SkipAmbiguous(Vec<String>),
}

fn fetch_remote_choice(remotes: &[String], configured: Option<&str>) -> FetchChoice {
    match remotes {
        [] => FetchChoice::None,
        [remote] => FetchChoice::Fetch(remote.clone()),
        many => configured
            .map(|remote| FetchChoice::Fetch(remote.to_string()))
            .unwrap_or_else(|| FetchChoice::SkipAmbiguous(many.to_vec())),
    }
}

fn infer_remote_integration_bookmark() -> Result<String> {
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

fn infer_remote_integration_bookmark_from(bookmarks: &[String]) -> Result<String> {
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

fn remote_matches(bookmarks: &[String], names: &[&str]) -> Vec<String> {
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

fn copy_envrc_if_needed(src: &Path, dest: &Path, mode: &str) -> Result<bool> {
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

fn file_is_tracked(repo: &Path, file: &str) -> Result<bool> {
    let output = Command::new("jj")
        .arg("file")
        .arg("show")
        .arg(file)
        .current_dir(repo)
        .output()?;
    Ok(output.status.success())
}

fn workspace_entries() -> Result<Vec<(String, String)>> {
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

fn ws_list(args: Vec<OsString>) -> Result<()> {
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

fn parse_pick_only_args(command: &str, args: Vec<OsString>) -> Result<bool> {
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
struct WsPathArgs {
    name: Option<String>,
    pick: bool,
}

fn parse_ws_path_args(args: Vec<OsString>) -> Result<WsPathArgs> {
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

fn ws_path(args: Vec<OsString>) -> Result<()> {
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

fn ws_root(args: Vec<OsString>) -> Result<()> {
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
struct WsForgetArgs {
    name: Option<String>,
    pick: bool,
    force: bool,
    keep_dir: bool,
    no_docker: bool,
    docker_volumes: bool,
    dry_run: bool,
    quiet: bool,
}

fn parse_ws_forget_args(args: Vec<OsString>) -> Result<WsForgetArgs> {
    let mut parsed = WsForgetArgs::default();
    for arg in args {
        match arg.to_string_lossy().as_ref() {
            "--pick" => parsed.pick = true,
            "--force" => parsed.force = true,
            "--keep-dir" => parsed.keep_dir = true,
            "--no-docker" => parsed.no_docker = true,
            "--docker-volumes" => parsed.docker_volumes = true,
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
    Ok(parsed)
}

fn ws_forget(args: Vec<OsString>) -> Result<()> {
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
    if !parsed.force && !commit_is_empty_in(&target, "@")? {
        bail!("workspace {name} has non-empty work at {}\n\nReview it first with:\n  jj --repository {} status\n\nUse --force to forget and delete anyway.", target.display(), target.display());
    }
    let config = ws_config()?;
    if parsed.dry_run {
        println!("would forget {name} at {}", path.display());
        return Ok(());
    }
    if !parsed.no_docker && config.docker_cleanup == "auto" && has_compose_file(&path) {
        let mut cmd = Command::new("docker");
        cmd.arg("compose")
            .arg("down")
            .arg("--remove-orphans")
            .current_dir(&path);
        if parsed.docker_volumes || config.docker_remove_volumes {
            cmd.arg("--volumes");
        }
        run_status(&mut cmd, "docker compose down")?;
    }
    run_jj_status(["workspace", "forget", name.as_str()])?;
    if !parsed.keep_dir && path.exists() {
        fs::remove_dir_all(&path)
            .with_context(|| format!("failed to remove {}", path.display()))?;
    }
    if let Some(parent) = path.parent() {
        let _ = fs::remove_dir(parent);
    }
    if !parsed.quiet {
        println!("forgot workspace {name}");
    }
    Ok(())
}

fn commit_is_empty_in(repo: &Path, revset: &str) -> Result<bool> {
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
            "empty",
        ])
        .current_dir(repo)
        .output()?;
    if !output.status.success() {
        return Ok(false);
    }
    Ok(String::from_utf8(output.stdout)?.trim() == "true")
}

fn has_compose_file(path: &Path) -> bool {
    [
        "compose.yaml",
        "compose.yml",
        "docker-compose.yaml",
        "docker-compose.yml",
    ]
    .iter()
    .any(|f| path.join(f).exists())
}

fn ws_prune(args: Vec<OsString>) -> Result<()> {
    let parsed = parse_ws_prune_args(args)?;
    let config = ws_config()?;
    let ctx = current_context(&config, None)?;
    let registered: Vec<PathBuf> = workspace_entries()?
        .into_iter()
        .map(|(_, p)| fs::canonicalize(&p).unwrap_or(PathBuf::from(p)))
        .collect();
    let mut children = Vec::new();
    if ctx.workspace_root.exists() {
        for entry in fs::read_dir(&ctx.workspace_root)? {
            let p = entry?.path();
            if p.is_dir() {
                children.push(p);
            }
        }
    }
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
            fs::remove_dir_all(p)?;
        }
    } else {
        for p in &stale {
            println!("{}", p.display());
        }
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct WsPruneArgs {
    delete: bool,
    pick: bool,
    dry_run: bool,
    yes: bool,
}

fn parse_ws_prune_args(args: Vec<OsString>) -> Result<WsPruneArgs> {
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

fn stale_workspace_dirs(children: &[PathBuf], registered: &[PathBuf]) -> Vec<PathBuf> {
    children
        .iter()
        .filter(|p| !registered.contains(&fs::canonicalize(p).unwrap_or_else(|_| (*p).clone())))
        .cloned()
        .collect()
}

fn pick_lines(prompt: &str, lines: &[String]) -> Result<Option<String>> {
    Ok(pick_multi(prompt, lines)?.into_iter().next())
}

fn pick_multi(prompt: &str, lines: &[String]) -> Result<Vec<String>> {
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

fn run_status(cmd: &mut Command, label: &str) -> Result<()> {
    let status = cmd
        .status()
        .with_context(|| format!("failed to execute {label}"))?;
    if status.success() {
        Ok(())
    } else {
        bail!("{label} failed with status {status}")
    }
}

fn has_working_copy_changes() -> Result<bool> {
    let output = run_jj_capture(["diff", "--summary", "--color=never"])?;
    Ok(!output.stdout.trim().is_empty())
}

fn resolve_ship_bookmark(target_rev: &str) -> Result<String> {
    let revset = format!("heads(ancestors({target_rev}) & bookmarks())");
    let candidates = bookmark_names_for_revset(&revset)?;

    choose_ship_bookmark(candidates, target_rev)
}

fn choose_ship_bookmark(candidates: Vec<String>, target_rev: &str) -> Result<String> {
    if candidates.is_empty() {
        bail!(
            "no ancestor bookmark found. Use --bookmark <name> or create one with: jj bookmark set <name> -r {target_rev}"
        );
    }

    let (feature_candidates, integration_candidates): (Vec<_>, Vec<_>) = candidates
        .into_iter()
        .partition(|candidate| !is_integration_bookmark(candidate));

    if !feature_candidates.is_empty() {
        return pick_option(
            "Ship bookmark",
            &feature_candidates,
            "Re-run with --bookmark <name> or --remote <name>.",
        );
    }

    if integration_candidates.is_empty() {
        bail!(
            "no ship bookmark candidates found near {target_rev}. Use --bookmark <name> to ship an explicit bookmark."
        );
    }

    bail!(
        "no nearby feature bookmark found for {target_rev}; refusing to fall back to integration bookmarks {}. Re-run with --bookmark <name> if you really want to ship one of them.",
        integration_candidates.join(", ")
    );
}

fn resolve_bookmark_remote(bookmark: &str, explicit_remote: Option<&str>) -> Result<String> {
    if let Some(remote) = explicit_remote {
        return Ok(remote.to_string());
    }

    let mut bookmark_remotes = bookmark_remotes(bookmark)?;
    dedup(&mut bookmark_remotes);

    if bookmark_remotes.len() == 1 {
        return Ok(bookmark_remotes.remove(0));
    }

    if !bookmark_remotes.is_empty() {
        return pick_option(
            &format!("Ship remote for {bookmark}"),
            &bookmark_remotes,
            "Re-run with --bookmark <name> or --remote <name>.",
        );
    }

    let mut remotes = git_remotes()?;
    dedup(&mut remotes);

    if remotes.is_empty() {
        bail!("no Git remotes configured");
    }

    pick_option(
        &format!("Ship remote for {bookmark}"),
        &remotes,
        "Re-run with --bookmark <name> or --remote <name>.",
    )
}

fn resolve_sync_base(configured_remote: Option<&str>, noninteractive: bool) -> Result<String> {
    let bookmarks = all_bookmarks()?;

    if let Some(candidates) = sync_base_candidates(&bookmarks) {
        return choose_sync_base(&candidates, configured_remote, noninteractive);
    }

    if commit_id("trunk()")?.is_some() {
        eprintln!("Warning: no integration bookmark found; falling back to trunk().");
        Ok("trunk()".to_string())
    } else {
        bail!("couldn't determine a sync base. Use --bookmark <name> or --onto <revset>.")
    }
}

fn all_bookmarks() -> Result<Vec<String>> {
    let output = run_jj_capture([
        "bookmark",
        "list",
        "--all-remotes",
        "--color=never",
        "-T",
        "self.name() ++ if(self.remote(), \"@\" ++ self.remote(), \"\") ++ \"\\n\"",
    ])?;
    Ok(output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.ends_with("@git"))
        .map(std::string::ToString::to_string)
        .collect())
}

fn choose_sync_base(
    candidates: &[String],
    configured_remote: Option<&str>,
    noninteractive: bool,
) -> Result<String> {
    let remote_candidates: Vec<String> = candidates
        .iter()
        .filter(|candidate| split_bookmark_remote(candidate).is_some())
        .cloned()
        .collect();

    if !remote_candidates.is_empty() {
        let filtered = if let Some(remote) = configured_remote {
            remote_candidates
                .iter()
                .filter(|candidate| {
                    split_bookmark_remote(candidate)
                        .map(|(_, candidate_remote)| candidate_remote == remote)
                        .unwrap_or(false)
                })
                .cloned()
                .collect::<Vec<_>>()
        } else {
            remote_candidates.clone()
        };

        if filtered.len() == 1 {
            return Ok(filtered[0].clone());
        }

        if filtered.len() > 1 {
            let remotes = unique_remotes(&filtered);
            if remotes.len() > 1 && configured_remote.is_none() {
                bail!("multiple remote integration bookmarks found: {}. Re-run with --remote <remote>, --bookmark <bookmark>@<remote>, --onto <revset>, or configure per-repo jj config dotfiles.sync.remote.", filtered.join(", "));
            }

            return pick_option_maybe(
                "Sync base",
                &filtered,
                "Re-run with --bookmark <name>@<remote> or --onto <revset>.",
                noninteractive,
            );
        }

        if let Some(remote) = configured_remote {
            bail!("no integration bookmark found for configured remote '{remote}'. Re-run with --remote <remote>, --bookmark <bookmark>@<remote>, --onto <revset>, or update per-repo jj config dotfiles.sync.remote.");
        }
    }

    pick_option_maybe(
        "Sync base",
        candidates,
        "Re-run with --bookmark <name> or --onto <revset>.",
        noninteractive,
    )
}

fn bookmark_names_for_revset(revset: &str) -> Result<Vec<String>> {
    let output = run_jj_capture([
        "bookmark",
        "list",
        "-r",
        revset,
        "-T",
        "self.name() ++ \"\\n\"",
        "--color=never",
    ])?;
    let mut bookmarks: Vec<String> = output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(std::string::ToString::to_string)
        .collect();
    dedup(&mut bookmarks);
    Ok(bookmarks)
}

fn bookmark_remotes(bookmark: &str) -> Result<Vec<String>> {
    let output = run_jj_capture([
        "bookmark",
        "list",
        "--all-remotes",
        bookmark,
        "--color=never",
        "-T",
        "if(self.remote(), self.remote() ++ \"\\n\", \"\")",
    ])?;
    Ok(output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|remote| !remote.is_empty() && *remote != "git")
        .map(std::string::ToString::to_string)
        .collect())
}

fn git_remotes() -> Result<Vec<String>> {
    let output = run_jj_capture(["git", "remote", "list", "--color=never"])?;
    Ok(output
        .stdout
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .map(std::string::ToString::to_string)
        .collect())
}

fn commit_id(revset: &str) -> Result<Option<String>> {
    let output = run_jj_capture_allow_failure([
        "log",
        "-r",
        revset,
        "-n",
        "1",
        "--no-graph",
        "--color=never",
        "-T",
        "commit_id",
    ])?;

    if !output.status.success() {
        return Ok(None);
    }

    let commit_id = output.stdout.trim();
    if commit_id.is_empty() {
        Ok(None)
    } else {
        Ok(Some(commit_id.to_string()))
    }
}

fn commit_is_empty(revset: &str) -> Result<bool> {
    let output = run_jj_capture_allow_failure([
        "log",
        "-r",
        revset,
        "-n",
        "1",
        "--no-graph",
        "--color=never",
        "-T",
        "empty",
    ])?;

    if !output.status.success() {
        return Ok(false);
    }

    match output.stdout.trim() {
        "true" => Ok(true),
        "false" | "" => Ok(false),
        other => bail!("unexpected empty-state output for {revset}: {other}"),
    }
}

fn rollback_bookmark(bookmark: &str, previous_target: Option<&str>) -> Result<()> {
    match previous_target {
        Some(target) => run_jj_status([
            "bookmark",
            "set",
            bookmark,
            "-r",
            target,
            "--allow-backwards",
        ]),
        None => run_jj_status(["bookmark", "forget", bookmark]),
    }
}

fn split_bookmark_remote(bookmark: &str) -> Option<(&str, &str)> {
    let (bookmark, remote) = bookmark.split_once('@')?;
    if bookmark.is_empty() || remote.is_empty() {
        None
    } else {
        Some((bookmark, remote))
    }
}

fn is_integration_bookmark(bookmark: &str) -> bool {
    matches!(bookmark, "develop" | "dev" | "main" | "master" | "trunk")
        || is_release_bookmark(bookmark)
}

fn is_release_bookmark(bookmark: &str) -> bool {
    bookmark == "release" || bookmark.starts_with("release/") || bookmark.starts_with("release-")
}

fn print_ship_usage() {
    eprintln!(
        "Usage:\n  jj ship [-b|--bookmark <bookmark>] [--remote <remote>] [-- <jj git push args...>]\n\nRuns jj lint, then ships the parent of the working copy. Refuses empty targets and will not fall back to integration bookmarks unless you choose one explicitly with --bookmark."
    );
}

fn print_sync_usage() {
    eprintln!(
        "Usage:\n  jj sync [-b|--bookmark <bookmark>] [--remote <remote>] [--onto <revset>] [-q|--quiet] [--json] [--noninteractive] [--fail-on-conflicts] [-- <jj rebase args...>]\n\nFetches, then rebases the current branch/stack onto one inferred integration base. Prefers remote integration bookmarks like main@origin. If multiple remote integration bookmarks exist, pass --remote/--bookmark/--onto or configure per-repo jj config dotfiles.sync.remote.\n\nAgent examples:\n  jj sync -q --fail-on-conflicts\n  jj sync --json --fail-on-conflicts\n  jj sync --json --fail-on-conflicts | jq -r '.base'\n  jj sync --bookmark main@origin -q --fail-on-conflicts"
    );
}

fn sync_base_candidates(bookmarks: &[String]) -> Option<Vec<String>> {
    let priority_groups: &[&[&str]] = &[
        ["develop", "dev"].as_slice(),
        ["main", "master", "trunk"].as_slice(),
    ];

    for group in priority_groups {
        let mut matches = filter_bookmarks(bookmarks, |bookmark| group.contains(&bookmark));
        dedup(&mut matches);
        if !matches.is_empty() {
            return Some(matches);
        }
    }

    let mut release_matches = filter_bookmarks(bookmarks, is_release_bookmark);
    dedup(&mut release_matches);
    if !release_matches.is_empty() {
        return Some(release_matches);
    }

    None
}

fn sync_bookmark_name(bookmark: &str) -> &str {
    split_bookmark_remote(bookmark)
        .map(|(name, _)| name)
        .unwrap_or(bookmark)
}

fn filter_bookmarks<F>(bookmarks: &[String], predicate: F) -> Vec<String>
where
    F: Fn(&str) -> bool,
{
    bookmarks
        .iter()
        .filter(|bookmark| predicate(sync_bookmark_name(bookmark)))
        .cloned()
        .collect()
}

fn pick_option(prompt: &str, options: &[String], rerun_hint: &str) -> Result<String> {
    pick_option_maybe(prompt, options, rerun_hint, false)
}

fn pick_option_maybe(
    prompt: &str,
    options: &[String],
    rerun_hint: &str,
    noninteractive: bool,
) -> Result<String> {
    match options {
        [] => bail!("no options available for {prompt}"),
        [only] => Ok(only.clone()),
        _ => {
            eprintln!("Warning: {prompt} is ambiguous.");

            if !noninteractive
                && io::stdin().is_terminal()
                && io::stdout().is_terminal()
                && which::which("fzf").is_ok()
            {
                let mut child = Command::new("fzf")
                    .arg("--prompt")
                    .arg(format!("{prompt}> "))
                    .arg("--height")
                    .arg("10")
                    .arg("--reverse")
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .spawn()
                    .with_context(|| format!("failed to launch fzf for {prompt}"))?;

                {
                    let stdin = child
                        .stdin
                        .as_mut()
                        .ok_or_else(|| anyhow!("failed to open fzf stdin"))?;
                    for option in options {
                        writeln!(stdin, "{option}")?;
                    }
                }

                let output = child.wait_with_output()?;
                if output.status.success() {
                    let selection = String::from_utf8(output.stdout)
                        .context("failed to decode fzf selection")?
                        .trim()
                        .to_string();

                    if !selection.is_empty() {
                        return Ok(selection);
                    }
                }

                bail!("no selection made for {prompt}");
            }

            for option in options {
                eprintln!(" - {option}");
            }
            bail!("{rerun_hint}")
        }
    }
}

fn unique_remotes(bookmarks: &[String]) -> Vec<String> {
    let mut remotes: Vec<String> = bookmarks
        .iter()
        .filter_map(|bookmark| {
            split_bookmark_remote(bookmark).map(|(_, remote)| remote.to_string())
        })
        .collect();
    dedup(&mut remotes);
    remotes
}

fn dedup(values: &mut Vec<String>) {
    values.sort();
    values.dedup();
}

fn run_jj_capture<const N: usize>(args: [&str; N]) -> Result<JjOutput> {
    let output = run_jj_capture_allow_failure(args)?;
    if output.status.success() {
        Ok(output)
    } else {
        bail!(format_jj_error(&args, &output))
    }
}

fn run_jj_capture_allow_failure<const N: usize>(args: [&str; N]) -> Result<JjOutput> {
    let output = Command::new("jj")
        .args(args)
        .output()
        .with_context(|| format!("failed to execute jj {}", args.join(" ")))?;

    Ok(JjOutput {
        status: output.status,
        stdout: String::from_utf8(output.stdout).context("failed to decode jj stdout")?,
        stderr: String::from_utf8(output.stderr).context("failed to decode jj stderr")?,
    })
}

fn run_jj_capture_os(args: Vec<OsString>) -> Result<JjOutput> {
    let output = run_jj_capture_os_allow_failure(&args)?;
    if output.status.success() {
        Ok(output)
    } else {
        bail!(format_jj_error_os(&args, &output))
    }
}

fn run_jj_capture_os_allow_failure(args: &[OsString]) -> Result<JjOutput> {
    let output = Command::new("jj")
        .args(args)
        .output()
        .with_context(|| format!("failed to execute jj {}", render_args(args)))?;

    Ok(JjOutput {
        status: output.status,
        stdout: String::from_utf8(output.stdout).context("failed to decode jj stdout")?,
        stderr: String::from_utf8(output.stderr).context("failed to decode jj stderr")?,
    })
}

fn run_jj_status<const N: usize>(args: [&str; N]) -> Result<()> {
    let args: Vec<OsString> = args.into_iter().map(OsString::from).collect();
    run_jj_status_os(args)
}

fn run_jj_status_os(args: Vec<OsString>) -> Result<()> {
    let status = Command::new("jj")
        .args(&args)
        .status()
        .with_context(|| format!("failed to execute jj {}", render_args(&args)))?;

    if status.success() {
        Ok(())
    } else {
        bail!("jj {} failed with status {status}", render_args(&args))
    }
}

fn render_args(args: &[OsString]) -> String {
    args.iter()
        .map(|arg| arg.to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join(" ")
}

fn format_jj_error<const N: usize>(args: &[&str; N], output: &JjOutput) -> String {
    let mut message = format!("jj {} failed", args.join(" "));
    let stderr = output.stderr.trim();
    if !stderr.is_empty() {
        message.push_str(": ");
        message.push_str(stderr);
    }
    message
}

fn format_jj_error_os(args: &[OsString], output: &JjOutput) -> String {
    let mut message = format!("jj {} failed", render_args(args));
    let stderr = output.stderr.trim();
    if !stderr.is_empty() {
        message.push_str(": ");
        message.push_str(stderr);
    }
    message
}

fn conflicted_changes() -> Result<Vec<String>> {
    let output = run_jj_capture([
        "log",
        "-r",
        "conflicts()",
        "--no-graph",
        "--color=never",
        "-T",
        "change_id.short() ++ \" \" ++ description.first_line() ++ \"\\n\"",
    ])?;
    Ok(output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(std::string::ToString::to_string)
        .collect())
}

fn print_sync_json(base: &str, remote: Option<&str>, conflicts: &[String]) {
    let remote_json = remote
        .map(|remote| format!("\"{}\"", json_escape(remote)))
        .unwrap_or_else(|| "null".to_string());
    let conflicts_json = conflicts
        .iter()
        .map(|conflict| format!("\"{}\"", json_escape(conflict)))
        .collect::<Vec<_>>()
        .join(",");
    println!(
        "{{\"action\":\"sync\",\"base\":\"{}\",\"remote\":{},\"conflicts\":[{}]}}",
        json_escape(base),
        remote_json,
        conflicts_json
    );
}

fn json_escape(value: &str) -> String {
    value
        .chars()
        .flat_map(|ch| match ch {
            '\\' => "\\\\".chars().collect::<Vec<_>>(),
            '"' => "\\\"".chars().collect::<Vec<_>>(),
            '\n' => "\\n".chars().collect::<Vec<_>>(),
            '\r' => "\\r".chars().collect::<Vec<_>>(),
            '\t' => "\\t".chars().collect::<Vec<_>>(),
            other => vec![other],
        })
        .collect()
}

struct JjOutput {
    status: std::process::ExitStatus,
    stdout: String,
    stderr: String,
}

#[cfg(test)]
mod tests {
    use super::{
        choose_ship_bookmark, choose_sync_base, fetch_remote_choice,
        infer_remote_integration_bookmark_from, is_integration_bookmark, parse_common_args,
        parse_toml_string_array, parse_ws_add_args, parse_ws_forget_args, parse_ws_path_args,
        parse_ws_prune_args, run_sync, run_ws, ship_plan, stale_workspace_dirs,
        sync_base_candidates, validate_ws_name, workspace_context_for_repo, FetchChoice,
        ParsedArgs, ProjectGroup, ShipPlan, WsAddArgs, WsConfig, WsForgetArgs, WsPathArgs,
        WsPruneArgs,
    };
    use std::env;
    use std::ffi::OsString;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::process::Command;
    use std::sync::Mutex;

    static INTEGRATION_LOCK: Mutex<()> = Mutex::new(());

    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| (*value).to_string()).collect()
    }

    fn test_config(group: &Path) -> WsConfig {
        WsConfig {
            project_groups: vec![ProjectGroup {
                path: group.to_path_buf(),
                workspace_dir: "ws".to_string(),
            }],
            copy_envrc: "untracked".to_string(),
            direnv_allow: true,
            docker_cleanup: "auto".to_string(),
            docker_remove_volumes: false,
            fetch_remote: None,
        }
    }

    fn named_tempdir(name: &str) -> PathBuf {
        let path = env::temp_dir().join(format!("jj-workflow-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn run(command: &mut Command) {
        let output = command.output().unwrap();
        assert!(
            output.status.success(),
            "command failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn jj(repo: &Path, args: &[&str]) {
        let mut command = Command::new("jj");
        command.current_dir(repo).args(args);
        run(&mut command);
    }

    fn jj_stdout(repo: &Path, args: &[&str]) -> String {
        let output = Command::new("jj")
            .current_dir(repo)
            .args(args)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "command failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap()
    }

    #[test]
    fn sync_prefers_develop_by_default() {
        let bookmarks = strings(&["develop", "main"]);
        assert_eq!(
            sync_base_candidates(&bookmarks),
            Some(strings(&["develop"]))
        );
    }

    #[test]
    fn sync_prefers_remote_integration_bookmark() {
        let candidates = strings(&["main", "main@origin"]);
        assert_eq!(
            choose_sync_base(&candidates, None, true).unwrap(),
            "main@origin"
        );
    }

    #[test]
    fn sync_uses_configured_remote_to_choose_bookmark() {
        let candidates = strings(&["main@origin", "main@upstream"]);
        assert_eq!(
            choose_sync_base(&candidates, Some("upstream"), true).unwrap(),
            "main@upstream"
        );
    }

    #[test]
    fn sync_rejects_ambiguous_remote_bookmarks() {
        let candidates = strings(&["main@origin", "main@upstream"]);
        let err = choose_sync_base(&candidates, None, true).unwrap_err();
        assert!(
            err.to_string().contains("dotfiles.sync.remote"),
            "unexpected error: {err:#}"
        );
    }

    #[test]
    fn sync_returns_all_candidates_within_priority_group() {
        let bookmarks = strings(&["dev", "develop", "main"]);
        assert_eq!(
            sync_base_candidates(&bookmarks),
            Some(strings(&["dev", "develop"]))
        );
    }

    #[test]
    fn sync_uses_release_branches_after_primary_groups() {
        let bookmarks = strings(&["release/2.0", "feature/foo", "release/1.0"]);
        assert_eq!(
            sync_base_candidates(&bookmarks),
            Some(strings(&["release/1.0", "release/2.0"]))
        );
    }

    #[test]
    fn integration_bookmark_detection_includes_release_trunk_and_dev() {
        for bookmark in ["develop", "dev", "main", "master", "trunk", "release/1.0"] {
            assert!(
                is_integration_bookmark(bookmark),
                "{bookmark} should be integration"
            );
        }

        assert!(!is_integration_bookmark("feature/foo"));
    }

    #[test]
    fn ship_parsing_recognizes_help_without_passthrough() {
        let parsed = parse_common_args(vec![OsString::from("--help")]).unwrap();
        assert_eq!(
            parsed,
            ParsedArgs {
                help: true,
                ..ParsedArgs::default()
            }
        );
    }

    #[test]
    fn ship_bookmark_selection_refuses_integration_fallback() {
        let err = choose_ship_bookmark(strings(&["main"]), "@-").unwrap_err();
        assert!(
            err.to_string()
                .contains("refusing to fall back to integration bookmarks main"),
            "unexpected error: {err:#}"
        );
    }

    #[test]
    fn ship_bookmark_selection_prefers_feature_bookmarks() {
        assert_eq!(
            choose_ship_bookmark(strings(&["main", "feature/foo"]), "@-").unwrap(),
            "feature/foo"
        );
    }

    #[test]
    fn ship_creates_new_working_copy_before_shipping_current_change() {
        assert_eq!(
            ship_plan(true),
            ShipPlan {
                create_new_working_copy: true,
                target_rev: "@-",
            }
        );
    }

    #[test]
    fn ship_uses_parent_change_when_working_copy_is_already_empty() {
        assert_eq!(
            ship_plan(false),
            ShipPlan {
                create_new_working_copy: false,
                target_rev: "@-",
            }
        );
    }

    #[test]
    fn workspace_name_validation_accepts_safe_names() {
        for name in ["feature-x", "bug.fix", "agent_123", "A1.b_c-d"] {
            validate_ws_name(name).unwrap();
        }
    }

    #[test]
    fn workspace_name_validation_rejects_unsafe_names() {
        for name in ["", "feature/x", "two words", "..", "foo..bar", "semi;colon"] {
            assert!(
                validate_ws_name(name).is_err(),
                "{name:?} should be rejected"
            );
        }
    }

    #[test]
    fn ws_add_parser_accepts_flags_and_equals_forms() {
        assert_eq!(
            parse_ws_add_args(vec![
                "feature".into(),
                "--revision=@".into(),
                "--project-group=/tmp/projects".into(),
                "--no-envrc".into(),
                "--no-direnv".into(),
                "-q".into(),
            ])
            .unwrap(),
            WsAddArgs {
                name: "feature".to_string(),
                revision: Some("@".to_string()),
                project_group: Some(PathBuf::from("/tmp/projects")),
                quiet: true,
                no_envrc: true,
                no_direnv: true,
                help: false,
            }
        );
    }

    #[test]
    fn ws_add_parser_rejects_missing_values_and_extra_positionals() {
        assert!(parse_ws_add_args(vec!["feature".into(), "extra".into()]).is_err());
        assert!(parse_ws_add_args(vec!["feature".into(), "-r".into()]).is_err());
        assert!(parse_ws_add_args(vec!["--unknown".into(), "feature".into()]).is_err());
    }

    #[test]
    fn ws_path_parser_requires_name_or_picker_exclusively() {
        assert_eq!(
            parse_ws_path_args(vec!["feature".into()]).unwrap(),
            WsPathArgs {
                name: Some("feature".to_string()),
                pick: false,
            }
        );
        assert_eq!(
            parse_ws_path_args(vec!["--pick".into()]).unwrap(),
            WsPathArgs {
                name: None,
                pick: true
            }
        );
        assert!(parse_ws_path_args(vec!["feature".into(), "--pick".into()]).is_err());
        assert!(parse_ws_path_args(vec![]).is_err());
    }

    #[test]
    fn ws_forget_parser_covers_flags_and_exclusive_picker() {
        assert_eq!(
            parse_ws_forget_args(vec![
                "feature".into(),
                "--force".into(),
                "--keep-dir".into(),
                "--no-docker".into(),
                "--docker-volumes".into(),
                "--dry-run".into(),
                "--quiet".into(),
            ])
            .unwrap(),
            WsForgetArgs {
                name: Some("feature".to_string()),
                pick: false,
                force: true,
                keep_dir: true,
                no_docker: true,
                docker_volumes: true,
                dry_run: true,
                quiet: true,
            }
        );
        assert!(parse_ws_forget_args(vec!["feature".into(), "--pick".into()]).is_err());
        assert!(parse_ws_forget_args(vec![]).is_err());
    }

    #[test]
    fn ws_prune_parser_rejects_positionals() {
        assert_eq!(
            parse_ws_prune_args(vec![
                "--delete".into(),
                "--pick".into(),
                "--dry-run".into(),
                "--yes".into(),
            ])
            .unwrap(),
            WsPruneArgs {
                delete: true,
                pick: true,
                dry_run: true,
                yes: true,
            }
        );
        assert!(parse_ws_prune_args(vec!["stale".into()]).is_err());
    }

    #[test]
    fn parses_flat_project_group_config() {
        assert_eq!(
            parse_toml_string_array("[\"~/projects:ws\", \"~/sureapp:workspaces\"]"),
            strings(&["~/projects:ws", "~/sureapp:workspaces"])
        );
    }

    #[test]
    fn workspace_context_detects_main_checkout() {
        let group = PathBuf::from("/tmp/projects");
        let repo = group.join("dotfiles");
        let ctx = workspace_context_for_repo(&repo, &test_config(&group), None).unwrap();
        assert!(!ctx.managed_workspace);
        assert_eq!(ctx.workspace_root, group.join("ws/dotfiles"));
    }

    #[test]
    fn workspace_context_detects_managed_workspace() {
        let group = PathBuf::from("/tmp/projects");
        let repo = group.join("ws/dotfiles/feature-x");
        let ctx = workspace_context_for_repo(&repo, &test_config(&group), None).unwrap();
        assert!(ctx.managed_workspace);
        assert_eq!(ctx.workspace_root, group.join("ws/dotfiles"));
    }

    #[test]
    fn workspace_context_prefers_most_specific_group() {
        let outer = PathBuf::from("/tmp/projects");
        let inner = PathBuf::from("/tmp/projects/sureapp");
        let config = WsConfig {
            project_groups: vec![
                ProjectGroup {
                    path: outer.clone(),
                    workspace_dir: "ws".to_string(),
                },
                ProjectGroup {
                    path: inner.clone(),
                    workspace_dir: "work".to_string(),
                },
            ],
            ..test_config(&outer)
        };
        let ctx = workspace_context_for_repo(&inner.join("api"), &config, None).unwrap();
        assert_eq!(ctx.workspace_root, inner.join("work/api"));
    }

    #[test]
    fn fetch_choice_handles_remote_counts() {
        assert_eq!(fetch_remote_choice(&[], None), FetchChoice::None);
        assert_eq!(
            fetch_remote_choice(&strings(&["origin"]), None),
            FetchChoice::Fetch("origin".to_string())
        );
        assert_eq!(
            fetch_remote_choice(&strings(&["origin", "upstream"]), Some("origin")),
            FetchChoice::Fetch("origin".to_string())
        );
        assert_eq!(
            fetch_remote_choice(&strings(&["origin", "upstream"]), None),
            FetchChoice::SkipAmbiguous(strings(&["origin", "upstream"]))
        );
    }

    #[test]
    fn remote_integration_inference_uses_priority_order() {
        assert_eq!(
            infer_remote_integration_bookmark_from(&strings(&["main@origin", "develop@origin"]))
                .unwrap(),
            "develop@origin"
        );
        assert_eq!(
            infer_remote_integration_bookmark_from(&strings(&[
                "feature@origin",
                "release/1@origin"
            ]))
            .unwrap(),
            "release/1@origin"
        );
    }

    #[test]
    fn remote_integration_inference_rejects_ambiguity() {
        let err =
            infer_remote_integration_bookmark_from(&strings(&["main@origin", "main@upstream"]))
                .unwrap_err();
        assert!(err
            .to_string()
            .contains("could not infer integration bookmark"));
    }

    #[test]
    fn stale_workspace_detection_filters_registered_dirs() {
        let children = vec![
            PathBuf::from("/tmp/ws/repo/a"),
            PathBuf::from("/tmp/ws/repo/b"),
        ];
        let stale = stale_workspace_dirs(&children, &[PathBuf::from("/tmp/ws/repo/a")]);
        assert_eq!(stale, vec![PathBuf::from("/tmp/ws/repo/b")]);
    }

    #[test]
    fn integration_adds_managed_workspace_at_canonical_path() {
        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("add");
        let group = root.join("projects");
        let repo = group.join("demo");
        fs::create_dir_all(&group).unwrap();
        run(Command::new("jj").arg("git").arg("init").arg(&repo));
        jj(
            &repo,
            &[
                "config",
                "set",
                "--repo",
                "dotfiles.workspaces.project-groups",
                &format!("[\"{}:ws\"]", group.display()),
            ],
        );
        jj(
            &repo,
            &[
                "config",
                "set",
                "--repo",
                "dotfiles.workspaces.direnv-allow",
                "false",
            ],
        );
        fs::write(repo.join("file.txt"), "hello\n").unwrap();
        jj(&repo, &["describe", "-m", "initial"]);

        let old = env::current_dir().unwrap();
        env::set_current_dir(&repo).unwrap();
        run_ws(vec![
            "add".into(),
            "feature-x".into(),
            "-r".into(),
            "@".into(),
            "-q".into(),
        ])
        .unwrap();
        env::set_current_dir(old).unwrap();

        assert!(group.join("ws/demo/feature-x/.jj").exists());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn integration_copies_untracked_envrc_and_forgets_workspace() {
        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("envrc-forget");
        let group = root.join("projects");
        let repo = group.join("demo");
        fs::create_dir_all(&group).unwrap();
        run(Command::new("jj").arg("git").arg("init").arg(&repo));
        jj(
            &repo,
            &[
                "config",
                "set",
                "--repo",
                "dotfiles.workspaces.project-groups",
                &format!("[\"{}:ws\"]", group.display()),
            ],
        );
        jj(
            &repo,
            &[
                "config",
                "set",
                "--repo",
                "dotfiles.workspaces.direnv-allow",
                "false",
            ],
        );
        fs::write(repo.join("tracked.txt"), "hello\n").unwrap();
        fs::write(repo.join(".envrc"), "use flake\n").unwrap();
        jj(&repo, &["describe", "-m", "initial"]);

        let old = env::current_dir().unwrap();
        env::set_current_dir(&repo).unwrap();
        run_ws(vec![
            "add".into(),
            "scratch".into(),
            "-r".into(),
            "@".into(),
            "-q".into(),
        ])
        .unwrap();
        let ws = group.join("ws/demo/scratch");
        assert_eq!(
            fs::read_to_string(ws.join(".envrc")).unwrap(),
            "use flake\n"
        );
        run_ws(vec![
            "forget".into(),
            "scratch".into(),
            "--force".into(),
            "-q".into(),
        ])
        .unwrap();
        env::set_current_dir(old).unwrap();

        assert!(!ws.exists());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn integration_sync_fetches_path_remote_and_rebases_to_remote_bookmark() {
        if which::which("git").is_err() {
            return;
        }

        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("sync-remote");
        let origin = root.join("origin.git");
        let seed = root.join("seed");
        let work = root.join("work");

        run(Command::new("git").arg("init").arg("--bare").arg(&origin));
        run(Command::new("jj").arg("git").arg("init").arg(&seed));
        jj(
            &seed,
            &["git", "remote", "add", "origin", origin.to_str().unwrap()],
        );
        fs::write(seed.join("file.txt"), "initial\n").unwrap();
        jj(&seed, &["describe", "-m", "initial"]);
        jj(&seed, &["bookmark", "set", "main", "-r", "@"]);
        jj(
            &seed,
            &["git", "push", "--bookmark", "main", "--remote", "origin"],
        );

        run(Command::new("jj")
            .arg("git")
            .arg("clone")
            .arg(&origin)
            .arg(&work));

        fs::write(seed.join("file.txt"), "upstream\n").unwrap();
        jj(&seed, &["describe", "-m", "upstream"]);
        jj(&seed, &["bookmark", "set", "main", "-r", "@"]);
        jj(
            &seed,
            &["git", "push", "--bookmark", "main", "--remote", "origin"],
        );

        fs::write(work.join("local.txt"), "local\n").unwrap();
        jj(&work, &["describe", "-m", "local"]);

        let old = env::current_dir().unwrap();
        env::set_current_dir(&work).unwrap();
        run_sync(parse_common_args(vec!["-q".into(), "--fail-on-conflicts".into()]).unwrap())
            .unwrap();
        env::set_current_dir(old).unwrap();

        let parent_is_remote_main = jj_stdout(
            &work,
            &[
                "log",
                "-r",
                "parents(@) & main@origin",
                "--no-graph",
                "--color=never",
                "-T",
                "change_id.short()",
            ],
        );
        assert!(
            !parent_is_remote_main.trim().is_empty(),
            "expected @ to be rebased onto main@origin"
        );

        let _ = fs::remove_dir_all(&root);
    }
}

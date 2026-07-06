use anyhow::{anyhow, bail, Context, Result};
use clap::{Args, Parser, Subcommand};
use serde_json::json;
use std::collections::HashMap;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, IsTerminal, Write};
#[cfg(unix)]
use std::os::unix::fs as unix_fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn main() {
    if let Err(err) = run() {
        eprintln!("Error: {err:#}");
        std::process::exit(1);
    }
}

#[derive(Debug, Parser)]
#[command(
    name = "jj-workflow",
    about = "Workflow helpers for jj lint, ship, sync, tags, PRs, and workspaces",
    arg_required_else_help = true,
    disable_version_flag = true
)]
struct Cli {
    #[command(subcommand)]
    command: CliCommand,
}

#[derive(Debug, Subcommand)]
enum CliCommand {
    /// Run repo-configured lints or lint onboarding helpers.
    Lint(ForwardArgs),
    /// Finish and publish the current change/stack.
    Ship(ShipCli),
    /// Fetch and rebase the current stack onto an integration base.
    Sync(SyncCli),
    /// Internal tag helper namespace.
    Tag(TagCli),
    /// Publish a human/agent-created release tag.
    #[command(name = "tag-push")]
    TagPush(TagPushCli),
    /// GitHub PR helper commands.
    Pr(ForwardArgs),
    /// Managed jj workspace commands.
    #[command(visible_alias = "workspace")]
    Ws(ForwardArgs),
}

#[derive(Debug, Args)]
struct ForwardArgs {
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    args: Vec<OsString>,
}

#[derive(Debug, Args)]
struct ShipCli {
    #[arg(short = 'b', long = "bookmark")]
    bookmark_input: Option<String>,
    #[arg(long)]
    remote: Option<String>,
    #[arg(long)]
    tag: Option<String>,
    #[command(flatten)]
    signing: TagSigningCli,
    #[arg(short, long)]
    quiet: bool,
    #[arg(last = true)]
    passthrough: Vec<OsString>,
}

#[derive(Debug, Args)]
struct SyncCli {
    #[arg(short = 'b', long = "bookmark")]
    bookmark_input: Option<String>,
    #[arg(long)]
    remote: Option<String>,
    #[arg(long)]
    onto: Option<String>,
    #[arg(short, long)]
    quiet: bool,
    #[arg(long)]
    json: bool,
    #[arg(long)]
    noninteractive: bool,
    #[arg(long)]
    fail_on_conflicts: bool,
    #[arg(last = true)]
    passthrough: Vec<OsString>,
}

#[derive(Debug, Args)]
struct TagCli {
    #[command(subcommand)]
    command: TagCommand,
}

#[derive(Debug, Subcommand)]
enum TagCommand {
    /// Publish a release tag.
    Push(TagPushCli),
}

#[derive(Debug, Args)]
struct TagPushCli {
    tag: String,
    #[arg(short = 'r', long = "revision")]
    revision: Option<String>,
    #[arg(long)]
    remote: Option<String>,
    #[arg(short = 'm', long = "message")]
    message: Option<String>,
    #[command(flatten)]
    signing: TagSigningCli,
    #[arg(long)]
    allow_dirty: bool,
    #[arg(long)]
    allow_move: bool,
    #[arg(long)]
    allow_non_semver: bool,
    #[arg(long)]
    dry_run: bool,
    #[arg(short, long)]
    quiet: bool,
    #[arg(long)]
    json: bool,
}

#[derive(Debug, Args)]
struct TagSigningCli {
    #[arg(long, conflicts_with = "no_sign")]
    sign: bool,
    #[arg(long)]
    no_sign: bool,
}

fn run() -> Result<()> {
    match Cli::parse().command {
        CliCommand::Lint(args) => run_lint(args.args),
        CliCommand::Ship(args) => run_ship(args.into()),
        CliCommand::Sync(args) => run_sync(args.into()),
        CliCommand::Tag(args) => match args.command {
            TagCommand::Push(args) => run_tag_push(args.into()),
        },
        CliCommand::TagPush(args) => run_tag_push(args.into()),
        CliCommand::Pr(args) => run_pr(args.args),
        CliCommand::Ws(args) => run_ws(args.args),
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
enum TagSigning {
    #[default]
    Auto,
    Sign,
    NoSign,
}

#[derive(Debug, Default, PartialEq, Eq)]
struct ParsedArgs {
    bookmark_input: Option<String>,
    remote_input: Option<String>,
    onto: Option<String>,
    help: bool,
    quiet: bool,
    json: bool,
    tag: Option<String>,
    tag_signing: TagSigning,
    noninteractive: bool,
    fail_on_conflicts: bool,
    passthrough: Vec<OsString>,
}

#[cfg(test)]
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

        if arg == OsStr::new("--tag") {
            let value = iter
                .next()
                .ok_or_else(|| anyhow!("missing value for {}", arg.to_string_lossy()))?;
            parsed.tag = Some(os_to_string(value)?);
            continue;
        }

        if let Some(value) = take_value_after_prefix(&arg, "--tag=")? {
            parsed.tag = Some(value);
            continue;
        }

        match arg.to_string_lossy().as_ref() {
            "--sign" => {
                set_tag_signing(&mut parsed.tag_signing, TagSigning::Sign)?;
                continue;
            }
            "--no-sign" => {
                set_tag_signing(&mut parsed.tag_signing, TagSigning::NoSign)?;
                continue;
            }
            _ => {}
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

#[cfg(test)]
fn set_tag_signing(current: &mut TagSigning, next: TagSigning) -> Result<()> {
    match (*current, next) {
        (TagSigning::Auto, _) | (_, TagSigning::Auto) => {
            *current = next;
            Ok(())
        }
        (left, right) if left == right => Ok(()),
        _ => bail!("pass only one of --sign or --no-sign"),
    }
}

impl From<TagSigningCli> for TagSigning {
    fn from(args: TagSigningCli) -> Self {
        if args.sign {
            TagSigning::Sign
        } else if args.no_sign {
            TagSigning::NoSign
        } else {
            TagSigning::Auto
        }
    }
}

impl From<ShipCli> for ParsedArgs {
    fn from(args: ShipCli) -> Self {
        ParsedArgs {
            bookmark_input: args.bookmark_input,
            remote_input: args.remote,
            quiet: args.quiet,
            tag: args.tag,
            tag_signing: args.signing.into(),
            passthrough: args.passthrough,
            ..ParsedArgs::default()
        }
    }
}

impl From<SyncCli> for ParsedArgs {
    fn from(args: SyncCli) -> Self {
        ParsedArgs {
            bookmark_input: args.bookmark_input,
            remote_input: args.remote,
            onto: args.onto,
            quiet: args.quiet || args.json,
            json: args.json,
            noninteractive: args.noninteractive || args.json,
            fail_on_conflicts: args.fail_on_conflicts,
            passthrough: args.passthrough,
            ..ParsedArgs::default()
        }
    }
}

impl From<TagPushCli> for TagPushArgs {
    fn from(args: TagPushCli) -> Self {
        TagPushArgs {
            tag: args.tag,
            revision: args.revision,
            remote: args.remote,
            message: args.message,
            signing: args.signing.into(),
            allow_dirty: args.allow_dirty,
            allow_move: args.allow_move,
            allow_non_semver: args.allow_non_semver,
            dry_run: args.dry_run,
            quiet: args.quiet || args.json,
            json: args.json,
            help: false,
        }
    }
}

fn run_ship(mut args: ParsedArgs) -> Result<()> {
    if args.help {
        print_ship_usage();
        return Ok(());
    }

    if args.tag.is_none() && args.tag_signing != TagSigning::Auto {
        bail!("jj ship --sign/--no-sign requires --tag <tag>")
    }

    // Run lints before changing bookmarks. The `jj push` alias also runs lints,
    // but doing it there means a lint failure can leave an integration bookmark
    // moved locally and then require manual recovery. Ship should fail early
    // while the repo graph is still untouched. Call the internal runner instead
    // of `jj lint` so derivation checks do not depend on user-installed aliases.
    run_lint(Vec::new())?;

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

    if let Some(tag) = args.tag.take() {
        let tag_args = TagPushArgs {
            tag,
            revision: Some(target_id.clone()),
            remote: Some(remote.clone()),
            message: None,
            signing: args.tag_signing,
            allow_dirty: false,
            allow_move: false,
            allow_non_semver: false,
            dry_run: false,
            quiet: args.quiet,
            json: false,
            help: false,
        };
        tag_push(tag_args)?;
    } else if let Err(err) = teach_unpushed_tags_at(&target_id, &remote) {
        eprintln!("warning: couldn't check for unpushed local tags: {err:#}");
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

fn run_lint(args: Vec<OsString>) -> Result<()> {
    if args.first().map(|arg| arg == "onboard").unwrap_or(false) {
        return run_lint_onboard(args.into_iter().skip(1).collect());
    }

    if args.iter().any(|arg| arg == "-h" || arg == "--help") {
        print_lint_usage();
        return Ok(());
    }

    let repo = jj_root()?;
    let commands = configured_lints(&repo)?;
    if commands.is_empty() {
        println!("No lints configured. Run: jj lint onboard --print");
        return Ok(());
    }

    let mut failures = Vec::new();
    for lint in commands {
        let name = lint_display_name(&lint);
        let command = lint.command;
        let output = Command::new("sh")
            .arg("-c")
            .arg(&command)
            .current_dir(&repo)
            .output()
            .with_context(|| format!("failed to run lint command: {command}"))?;
        if output.status.success() {
            println!("{name}...Passed");
        } else {
            println!("{name}...Failed");
            failures.push((command, output));
        }
    }

    if !failures.is_empty() {
        println!();
        for (command, output) in failures {
            println!("==> {command}");
            print!("{}", String::from_utf8_lossy(&output.stdout));
            eprint!("{}", String::from_utf8_lossy(&output.stderr));
            println!();
        }
        bail!("one or more lint commands failed");
    }

    Ok(())
}

fn run_lint_onboard(args: Vec<OsString>) -> Result<()> {
    let mut mode = "print";
    let mut selection: Option<Vec<usize>> = None;
    for arg in args {
        let arg = arg.to_string_lossy();
        match arg.as_ref() {
            "--print" => mode = "print",
            "--json" => mode = "json",
            "--write" => mode = "write",
            "--local" => mode = "local",
            "--preview" => mode = "preview",
            other if other.starts_with("--select=") => {
                selection = Some(parse_lint_selection(other.trim_start_matches("--select="))?);
            }
            "-h" | "--help" => {
                print_lint_onboard_usage();
                return Ok(());
            }
            other => bail!("unknown jj lint onboard option: {other}"),
        }
    }

    let repo = jj_root()?;
    let report = lint_onboard_report(&repo)?;
    match mode {
        "print" => print_lint_onboard_report(&report),
        "json" => println!("{}", lint_onboard_json(&report)),
        "preview" => preview_lint_config(&report, selection.as_deref())?,
        "write" => write_tracked_lint_config(&repo, &report, selection.as_deref())?,
        "local" => write_local_lint_config(&report, selection.as_deref())?,
        _ => unreachable!(),
    }
    Ok(())
}

fn run_sync(mut args: ParsedArgs) -> Result<()> {
    if args.help {
        print_sync_usage();
        return Ok(());
    }

    if args.tag.is_some() {
        bail!("jj sync does not support --tag; use `jj ship --tag <tag>` or `jj tag-push <tag> --revision <rev>`")
    }
    if args.tag_signing != TagSigning::Auto {
        bail!("jj sync does not support --sign/--no-sign; use `jj ship --tag <tag>` or `jj tag-push <tag> --revision <rev>`")
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

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct TagPushArgs {
    tag: String,
    revision: Option<String>,
    remote: Option<String>,
    message: Option<String>,
    signing: TagSigning,
    allow_dirty: bool,
    allow_move: bool,
    allow_non_semver: bool,
    dry_run: bool,
    quiet: bool,
    json: bool,
    help: bool,
}

#[cfg(test)]
fn parse_tag_push_args(args: Vec<OsString>) -> Result<TagPushArgs> {
    let mut parsed = TagPushArgs::default();
    let mut iter = args.into_iter();

    while let Some(arg) = iter.next() {
        if arg == OsStr::new("-h") || arg == OsStr::new("--help") {
            parsed.help = true;
            continue;
        }

        if arg == OsStr::new("-r") || arg == OsStr::new("--revision") {
            let value = iter
                .next()
                .ok_or_else(|| anyhow!("missing value for {}", arg.to_string_lossy()))?;
            parsed.revision = Some(os_to_string(value)?);
            continue;
        }

        if let Some(value) = take_value_after_prefix(&arg, "--revision=")? {
            parsed.revision = Some(value);
            continue;
        }

        if arg == OsStr::new("--remote") {
            let value = iter
                .next()
                .ok_or_else(|| anyhow!("missing value for {}", arg.to_string_lossy()))?;
            parsed.remote = Some(os_to_string(value)?);
            continue;
        }

        if let Some(value) = take_value_after_prefix(&arg, "--remote=")? {
            parsed.remote = Some(value);
            continue;
        }

        if arg == OsStr::new("-m") || arg == OsStr::new("--message") {
            let value = iter
                .next()
                .ok_or_else(|| anyhow!("missing value for {}", arg.to_string_lossy()))?;
            parsed.message = Some(os_to_string(value)?);
            continue;
        }

        if let Some(value) = take_value_after_prefix(&arg, "--message=")? {
            parsed.message = Some(value);
            continue;
        }

        match arg.to_string_lossy().as_ref() {
            "--sign" => set_tag_signing(&mut parsed.signing, TagSigning::Sign)?,
            "--no-sign" => set_tag_signing(&mut parsed.signing, TagSigning::NoSign)?,
            "--allow-dirty" => parsed.allow_dirty = true,
            "--allow-move" => parsed.allow_move = true,
            "--allow-non-semver" => parsed.allow_non_semver = true,
            "--dry-run" => parsed.dry_run = true,
            "-q" | "--quiet" => parsed.quiet = true,
            "--json" => {
                parsed.json = true;
                parsed.quiet = true;
            }
            other if other.starts_with('-') => bail!("unknown jj tag-push option: {other}"),
            other => {
                if parsed.tag.is_empty() {
                    parsed.tag = other.to_string();
                } else {
                    bail!("unexpected jj tag-push argument: {other}");
                }
            }
        }
    }

    Ok(parsed)
}

fn run_tag_push(args: TagPushArgs) -> Result<()> {
    if args.help {
        print_tag_push_usage();
        return Ok(());
    }
    tag_push(args)
}

fn tag_push(args: TagPushArgs) -> Result<()> {
    if args.tag.is_empty() {
        print_tag_push_usage();
        bail!("missing tag name");
    }

    if !args.allow_non_semver {
        validate_release_tag(&args.tag)?;
    }

    let working_copy_dirty = has_working_copy_changes()?;
    if working_copy_dirty && !args.allow_dirty {
        bail!("working copy has changes; commit or move them aside, or re-run with --allow-dirty")
    }

    let revision = match args.revision.as_deref() {
        Some(revision) => revision.to_string(),
        None if !working_copy_dirty => "@-".to_string(),
        None => bail!(
            "missing --revision <rev>; defaulting to @- is only allowed with a clean working copy"
        ),
    };

    ensure_no_conflicts_in(&revision)?;
    let target_id =
        commit_id(&revision)?.ok_or_else(|| anyhow!("revision not found: {revision}"))?;
    if commit_is_empty(&revision)? {
        bail!("refusing to tag empty revision {revision}")
    }
    let description = commit_description_first_line(&revision)?;
    let remote = resolve_tag_remote(args.remote.as_deref())?;
    let signing = resolve_tag_signing(args.signing)?;

    let remote_tag_before = remote_tag_ref(&remote, &args.tag)?;
    if let Some(remote_tag) = remote_tag_before.as_ref() {
        let remote_target = remote_tag.target();
        if remote_target == target_id {
            if !remote_tag.is_annotated() {
                bail!(
                    "remote tag {} already exists on {} at {} but is lightweight; release artifacts on hosts like sourcehut require an annotated tag. Re-create it as annotated on the same commit and force-push only refs/tags/{}.",
                    args.tag,
                    remote,
                    short_commit(remote_target),
                    args.tag
                );
            }
            if args.json {
                print_tag_push_json(&args.tag, &revision, &target_id, &remote, true, true);
            } else if !args.quiet {
                println!(
                    "remote annotated tag {} already exists on {} -> {}",
                    args.tag,
                    remote,
                    short_commit(&target_id)
                );
            }
            return Ok(());
        }
        bail!(
            "remote tag {} already exists on {} at {}; refusing to move it",
            args.tag,
            remote,
            short_commit(remote_target)
        );
    }

    let local_git_tag_before = local_git_tag_ref(&args.tag)?;
    let local_target_before = local_tag_target(&args.tag)?.or_else(|| {
        local_git_tag_before
            .as_ref()
            .map(|tag_ref| tag_ref.target().to_string())
    });
    let local_tag_is_annotated_at_target = matches!(
        local_git_tag_before.as_ref(),
        Some(tag_ref) if tag_ref.is_annotated() && tag_ref.target() == target_id
    );
    let needs_local_tag = match local_target_before.as_deref() {
        Some(local_target) if local_target == target_id && local_tag_is_annotated_at_target => {
            false
        }
        Some(local_target) if local_target == target_id => true,
        Some(local_target) if args.allow_move => {
            if !args.quiet && !args.json {
                println!(
                    "moving local tag {} from {} to {}",
                    args.tag,
                    short_commit(local_target),
                    short_commit(&target_id)
                );
            }
            true
        }
        Some(local_target) => bail!(
            "local tag {} already exists at {}; refusing to move it without --allow-move",
            args.tag,
            short_commit(local_target)
        ),
        None => true,
    };

    if args.dry_run {
        if args.json {
            print_tag_push_json(&args.tag, &revision, &target_id, &remote, false, false);
        } else {
            println!("would create/push tag {}", args.tag);
            println!("revision: {revision}");
            println!("commit: {} {}", short_commit(&target_id), description);
            println!("remote: {remote}");
            println!("signed: {}", signing.description());
        }
        return Ok(());
    }

    if !args.quiet && !args.json {
        println!("tag: {}", args.tag);
        println!("revision: {revision}");
        println!("commit: {} {}", short_commit(&target_id), description);
        println!("remote: {remote}");
        println!("signed: {}", signing.description());
        println!();
    }

    if needs_local_tag {
        let message = args
            .message
            .clone()
            .unwrap_or_else(|| default_tag_message(&args.tag));
        create_annotated_git_tag(
            &args.tag,
            &target_id,
            &message,
            local_target_before.is_some(),
            &signing,
        )?;
        if signing.sign {
            verify_signed_git_tag(&args.tag)?;
        }
        run_jj_status(["git", "import"])?;
    } else if !args.quiet && !args.json {
        println!(
            "local annotated tag {} already points to {}",
            args.tag,
            short_commit(&target_id)
        );
    }

    git_push_tag(&remote, &args.tag)?;
    let verified_tag = remote_tag_ref(&remote, &args.tag)?
        .ok_or_else(|| anyhow!("remote tag {} was not found after push", args.tag))?;
    if !verified_tag.is_annotated() {
        bail!(
            "remote tag {} on {} is lightweight after push; expected an annotated tag",
            args.tag,
            remote
        );
    }
    let verified_target = verified_tag.target().to_string();
    if verified_target != target_id {
        bail!(
            "remote tag {} points to {}, expected {}",
            args.tag,
            short_commit(&verified_target),
            short_commit(&target_id)
        )
    }
    let local_tag_after = local_git_tag_ref(&args.tag)?
        .ok_or_else(|| anyhow!("local tag {} was not found after push", args.tag))?;
    if local_tag_after.object_id != verified_tag.object_id {
        bail!(
            "remote tag {} object {} differs from local tag object {}",
            args.tag,
            short_commit(&verified_tag.object_id),
            short_commit(&local_tag_after.object_id)
        );
    }

    if args.json {
        print_tag_push_json(&args.tag, &revision, &target_id, &remote, true, true);
    } else if !args.quiet {
        println!(
            "verified {} -> {} on {}",
            args.tag,
            short_commit(&target_id),
            remote
        );
    }

    Ok(())
}

#[derive(Debug, Clone, Default)]
struct PrArgs {
    base: Option<String>,
    repo: Option<String>,
    remote: Option<String>,
    head: Option<String>,
    title: Option<String>,
    body: Option<String>,
    body_file: Option<String>,
    ticket: Option<String>,
    short_description: Option<String>,
    pr: Option<String>,
    sync: bool,
    run_lints: bool,
    run_cr: bool,
    draft: bool,
    push: bool,
    no_push: bool,
    dry_run: bool,
    json: bool,
    once: bool,
    ignore_comments: bool,
    required: bool,
    interval: Option<Duration>,
    timeout: Option<Duration>,
    help: bool,
}

#[derive(Debug, Clone)]
struct GithubRemote {
    name: String,
    url: String,
    owner: String,
    repo: String,
}

impl GithubRemote {
    fn slug(&self) -> String {
        format!("{}/{}", self.owner, self.repo)
    }
}

#[derive(Debug, Clone)]
struct PrBase {
    pr_base: String,
    sync_base: String,
    inferred: bool,
}

#[derive(Debug, Clone)]
struct PrHead {
    bookmark: String,
    inferred: bool,
    source: String,
}

#[derive(Debug, Clone)]
struct ExistingPr {
    number: u64,
    url: String,
    title: String,
    state: String,
}

#[derive(Debug, Clone)]
struct PrCheck {
    name: String,
    bucket: String,
    state: String,
    link: String,
}

#[derive(Debug, Clone)]
struct UnresolvedComment {
    author: String,
    path: String,
    line: Option<u64>,
    first_line: String,
    url: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WatchState {
    Success,
    Pending,
    Failed,
}

#[derive(Debug, Clone)]
struct PrWatchSnapshot {
    pr: ExistingPr,
    checks: Vec<PrCheck>,
    comments: Vec<UnresolvedComment>,
    review_decision: Option<String>,
    state: WatchState,
}

#[derive(Debug, Clone)]
struct ReviewStatePage {
    review_decision: String,
    comments: Vec<UnresolvedComment>,
    has_next_page: bool,
    end_cursor: Option<String>,
}

#[derive(Debug, Clone)]
struct PrHygieneArgs {
    search: Option<String>,
    limit: usize,
    json: bool,
    no_workspaces: bool,
    help: bool,
}

impl Default for PrHygieneArgs {
    fn default() -> Self {
        Self {
            search: None,
            limit: 50,
            json: false,
            no_workspaces: false,
            help: false,
        }
    }
}

#[derive(Debug, Clone)]
struct PrHygieneReport {
    query: String,
    limit: usize,
    total_count: u64,
    warnings: Vec<String>,
    prs: Vec<PrHygieneItem>,
}

#[derive(Debug, Clone)]
struct PrHygieneItem {
    repo_slug: String,
    repo_name: String,
    number: u64,
    url: String,
    title: String,
    state: String,
    is_draft: bool,
    review_decision: String,
    created_at: String,
    updated_at: String,
    head_ref_name: String,
    base_ref_name: String,
    additions: u64,
    deletions: u64,
    changed_files: u64,
    commits: u64,
    checks: Vec<PrCheck>,
    comments: Vec<UnresolvedComment>,
    checks_truncated: bool,
    review_threads_truncated: bool,
    workspaces: Vec<PrWorkspaceMatch>,
    status: String,
    priority: String,
    effort: String,
    follow_up: String,
}

#[derive(Debug, Clone)]
struct PrWorkspaceMatch {
    name: String,
    path: PathBuf,
    kind: String,
    relation: String,
}

#[derive(Debug, Clone)]
struct PrWorkspaceCandidate {
    name: String,
    path: PathBuf,
    kind: String,
}

fn run_pr(args: Vec<OsString>) -> Result<()> {
    let mut iter = args.into_iter();
    let command = match iter.next() {
        Some(command) => command,
        None => {
            print_pr_usage();
            bail!("missing pr subcommand");
        }
    };

    match command.to_string_lossy().as_ref() {
        "doctor" => pr_doctor(parse_pr_args(iter.collect(), false)?),
        "create" => pr_create(parse_pr_args(iter.collect(), true)?),
        "update" => pr_update(parse_pr_args(iter.collect(), false)?),
        "close" => pr_close(parse_pr_args(iter.collect(), false)?),
        "watch" => pr_watch(parse_pr_args(iter.collect(), false)?),
        "hygiene" | "report" | "dashboard" => pr_hygiene(parse_pr_hygiene_args(iter.collect())?),
        "-h" | "--help" | "help" => {
            print_pr_usage();
            Ok(())
        }
        other => {
            print_pr_usage();
            bail!("unknown pr subcommand: {other}")
        }
    }
}

fn parse_pr_args(args: Vec<OsString>, push_default: bool) -> Result<PrArgs> {
    let mut parsed = PrArgs {
        push: push_default,
        ..PrArgs::default()
    };
    let mut iter = args.into_iter();

    while let Some(arg) = iter.next() {
        let arg_str = arg
            .to_str()
            .ok_or_else(|| anyhow!("argument contains invalid UTF-8"))?;

        macro_rules! take_value {
            ($field:ident) => {{
                let value = iter
                    .next()
                    .ok_or_else(|| anyhow!("missing value for {arg_str}"))?;
                parsed.$field = Some(os_to_string(value)?);
            }};
        }

        match arg_str {
            "--base" => take_value!(base),
            "--repo" => take_value!(repo),
            "--remote" => take_value!(remote),
            "--head" => take_value!(head),
            "--title" => take_value!(title),
            "--body" => take_value!(body),
            "--body-file" => take_value!(body_file),
            "--ticket" => take_value!(ticket),
            "--short-description" => take_value!(short_description),
            "--pr" => take_value!(pr),
            "--interval" => {
                let value = iter
                    .next()
                    .ok_or_else(|| anyhow!("missing value for {arg_str}"))?;
                parsed.interval = Some(parse_duration_arg(&os_to_string(value)?)?);
            }
            "--timeout" => {
                let value = iter
                    .next()
                    .ok_or_else(|| anyhow!("missing value for {arg_str}"))?;
                parsed.timeout = Some(parse_duration_arg(&os_to_string(value)?)?);
            }
            "--sync" => parsed.sync = true,
            "--run-lints" => parsed.run_lints = true,
            "--run-cr" => parsed.run_cr = true,
            "--draft" => parsed.draft = true,
            "--once" => parsed.once = true,
            "--ignore-comments" => parsed.ignore_comments = true,
            "--required" => parsed.required = true,
            "--push" => {
                parsed.push = true;
                parsed.no_push = false;
            }
            "--no-push" => {
                parsed.push = false;
                parsed.no_push = true;
            }
            "--dry-run" => parsed.dry_run = true,
            "--json" => parsed.json = true,
            "-h" | "--help" => parsed.help = true,
            _ => {
                if let Some(value) = arg_str.strip_prefix("--base=") {
                    parsed.base = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--repo=") {
                    parsed.repo = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--remote=") {
                    parsed.remote = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--head=") {
                    parsed.head = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--title=") {
                    parsed.title = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--body=") {
                    parsed.body = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--body-file=") {
                    parsed.body_file = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--ticket=") {
                    parsed.ticket = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--short-description=") {
                    parsed.short_description = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--pr=") {
                    parsed.pr = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--interval=") {
                    parsed.interval = Some(parse_duration_arg(value)?);
                } else if let Some(value) = arg_str.strip_prefix("--timeout=") {
                    parsed.timeout = Some(parse_duration_arg(value)?);
                } else {
                    bail!("unknown pr argument: {arg_str}");
                }
            }
        }
    }

    Ok(parsed)
}

fn parse_pr_hygiene_args(args: Vec<OsString>) -> Result<PrHygieneArgs> {
    let mut parsed = PrHygieneArgs::default();
    let mut iter = args.into_iter();

    while let Some(arg) = iter.next() {
        let arg_str = arg
            .to_str()
            .ok_or_else(|| anyhow!("argument contains invalid UTF-8"))?;

        match arg_str {
            "--search" | "--query" => {
                let value = iter
                    .next()
                    .ok_or_else(|| anyhow!("missing value for {arg_str}"))?;
                parsed.search = Some(os_to_string(value)?);
            }
            "--limit" => {
                let value = iter
                    .next()
                    .ok_or_else(|| anyhow!("missing value for {arg_str}"))?;
                parsed.limit = parse_pr_hygiene_limit(&os_to_string(value)?)?;
            }
            "--json" => parsed.json = true,
            "--no-workspaces" => parsed.no_workspaces = true,
            "-h" | "--help" => parsed.help = true,
            _ => {
                if let Some(value) = arg_str.strip_prefix("--search=") {
                    parsed.search = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--query=") {
                    parsed.search = Some(value.to_string());
                } else if let Some(value) = arg_str.strip_prefix("--limit=") {
                    parsed.limit = parse_pr_hygiene_limit(value)?;
                } else {
                    bail!("unknown pr hygiene argument: {arg_str}");
                }
            }
        }
    }

    Ok(parsed)
}

fn parse_pr_hygiene_limit(value: &str) -> Result<usize> {
    let limit: usize = value
        .parse()
        .with_context(|| format!("invalid --limit value: {value}"))?;
    if !(1..=100).contains(&limit) {
        bail!("jj pr hygiene --limit must be between 1 and 100");
    }
    Ok(limit)
}

fn pr_doctor(args: PrArgs) -> Result<()> {
    if args.help {
        print_pr_doctor_usage();
        return Ok(());
    }
    validate_pr_doctor_args(&args)?;

    let mut blockers = Vec::new();
    let mut warnings = Vec::new();
    let repo = match resolve_github_remote(args.repo.as_deref(), args.remote.as_deref()) {
        Ok(repo) => Some(repo),
        Err(err) => {
            blockers.push(err.to_string());
            None
        }
    };
    let sync_remote = repo
        .as_ref()
        .and_then(|repo| sync_remote_for_repo(repo, &args).ok().flatten());
    let base = match resolve_pr_base(args.base.as_deref(), sync_remote.as_deref()) {
        Ok(base) => Some(base),
        Err(err) => {
            blockers.push(err.to_string());
            None
        }
    };
    let head = match resolve_pr_head(&args, true) {
        Ok(head) => Some(head),
        Err(err) => {
            blockers.push(err.to_string());
            None
        }
    };
    let scoped_conflicts = match &head {
        Some(head) => conflicted_changes_in(&format!("::bookmarks({:?})", head.bookmark))?,
        None => conflicted_changes_in("::@")?,
    };
    if !scoped_conflicts.is_empty() {
        blockers.push(format!(
            "PR-relevant changes have conflicts: {}",
            scoped_conflicts.join(", ")
        ));
    } else {
        let global_conflicts = conflicted_changes()?;
        if !global_conflicts.is_empty() {
            warnings.push(format!(
                "repository has unrelated conflicted changes outside the PR stack: {}",
                global_conflicts.join(", ")
            ));
        }
    }
    if which::which("gh").is_err() {
        blockers.push("gh CLI is not available on PATH".to_string());
    }
    if args.run_cr && which::which("cr").is_err() {
        warnings.push("cr CLI is not available on PATH".to_string());
    }

    let existing = match (&repo, &head) {
        (Some(repo), Some(head)) if which::which("gh").is_ok() => {
            match gh_prs_by_head(repo, &head.bookmark) {
                Ok(prs) => prs.into_iter().next(),
                Err(err) => {
                    warnings.push(format!("could not query existing PRs with gh: {err:#}"));
                    None
                }
            }
        }
        _ => None,
    };

    if args.json {
        print_pr_doctor_json(
            repo.as_ref(),
            base.as_ref(),
            head.as_ref(),
            existing.as_ref(),
            &blockers,
            &warnings,
        );
    } else {
        print_pr_doctor_human(
            repo.as_ref(),
            base.as_ref(),
            head.as_ref(),
            existing.as_ref(),
            &blockers,
            &warnings,
        );
    }

    Ok(())
}

fn pr_create(args: PrArgs) -> Result<()> {
    if args.help {
        print_pr_create_usage();
        return Ok(());
    }
    if args.title.is_none() {
        bail!("jj pr create requires --title");
    }
    validate_pr_create_args(&args)?;
    let repo = resolve_github_remote(args.repo.as_deref(), args.remote.as_deref())?;
    validate_body_source(&args, true)?;
    let sync_remote = sync_remote_for_repo(&repo, &args)?;
    let base = resolve_pr_base(args.base.as_deref(), sync_remote.as_deref())?;
    ensure_no_conflicts_in("::@")?;
    if !args.dry_run {
        ensure_current_change_described(args.title.as_deref())?;
    }
    let head = resolve_pr_head_for_create(&args, !args.dry_run)?;

    if args.dry_run {
        println!(
            "Would create PR: gh pr create --repo {} --base {} --head {} --title <title> {}{}",
            repo.slug(),
            base.pr_base,
            head.bookmark,
            if args.body_file.is_some() {
                "--body-file <file>"
            } else {
                "--body <body>"
            },
            if args.draft { " --draft" } else { "" }
        );
        return Ok(());
    }

    let existing = gh_prs_by_head(&repo, &head.bookmark)?;
    if !existing.is_empty() {
        let urls = existing
            .iter()
            .map(|pr| format!("#{} {}", pr.number, pr.url))
            .collect::<Vec<_>>()
            .join("\n  ");
        bail!(
            "existing PR found for head {head}:\n  {urls}\n\nUse `jj pr update` to edit it or `jj pr close` to close it.",
            head = head.bookmark
        );
    }

    if args.sync {
        run_sync(ParsedArgs {
            onto: Some(base.sync_base.clone()),
            quiet: false,
            noninteractive: true,
            fail_on_conflicts: true,
            ..ParsedArgs::default()
        })?;
        ensure_no_conflicts_in("::@")?;
    }
    if args.run_lints {
        run_lint(Vec::new())?;
    }
    if args.run_cr {
        run_cr_review(&base)?;
    }
    if args.push {
        let push_args = vec![
            OsString::from("git"),
            OsString::from("push"),
            OsString::from("--bookmark"),
            OsString::from(&head.bookmark),
            OsString::from("--remote"),
            OsString::from(resolve_push_remote(&repo, &args)?),
        ];
        if let Err(err) = run_jj_status_os(push_args) {
            bail!(
                "{err:#}\n\nPush failed. jj pr will not force/update remote bookmarks automatically. Resolve the remote bookmark state manually, then retry. Common next steps:\n  jj bookmark list {bookmark} --all-remotes\n  jj git push --bookmark {bookmark}",
                bookmark = head.bookmark
            );
        }
    }

    let url = gh_pr_create(&repo, &base, &head, &args)?;
    println!("{url}");
    Ok(())
}

fn pr_update(args: PrArgs) -> Result<()> {
    if args.help {
        print_pr_update_usage();
        return Ok(());
    }
    validate_body_source(&args, false)?;
    if args.title.is_none()
        && args.body.is_none()
        && args.body_file.is_none()
        && args.base.is_none()
    {
        bail!("jj pr update requires at least one of --title, --body, --body-file, or --base");
    }

    validate_pr_update_args(&args)?;
    let repo = resolve_github_remote(args.repo.as_deref(), args.remote.as_deref())?;
    let pr = resolve_existing_pr(&repo, &args)?;
    let mut gh_args = vec![
        "pr".to_string(),
        "edit".to_string(),
        pr.number.to_string(),
        "--repo".to_string(),
        repo.slug(),
    ];
    if let Some(title) = args.title.as_deref() {
        gh_args.push("--title".to_string());
        gh_args.push(title.to_string());
    }
    if let Some(body) = args.body.as_deref() {
        gh_args.push("--body".to_string());
        gh_args.push(body.to_string());
    }
    if let Some(body_file) = args.body_file.as_deref() {
        gh_args.push("--body-file".to_string());
        gh_args.push(body_file.to_string());
    }
    if let Some(base) = args.base.as_deref() {
        gh_args.push("--base".to_string());
        gh_args.push(sync_bookmark_name(base).to_string());
    }
    gh_status(&gh_args, "gh pr edit")?;
    println!("Updated PR #{}: {}", pr.number, pr.url);
    Ok(())
}

fn pr_close(args: PrArgs) -> Result<()> {
    if args.help {
        print_pr_close_usage();
        return Ok(());
    }
    validate_pr_close_args(&args)?;
    let repo = resolve_github_remote(args.repo.as_deref(), args.remote.as_deref())?;
    let pr = resolve_existing_pr(&repo, &args)?;
    let gh_args = vec![
        "pr".to_string(),
        "close".to_string(),
        pr.number.to_string(),
        "--repo".to_string(),
        repo.slug(),
    ];
    gh_status(&gh_args, "gh pr close")?;
    println!("Closed PR #{}: {}", pr.number, pr.url);
    Ok(())
}

fn pr_watch(args: PrArgs) -> Result<()> {
    if args.help {
        print_pr_watch_usage();
        return Ok(());
    }
    validate_pr_watch_args(&args)?;
    let repo = resolve_github_remote(args.repo.as_deref(), args.remote.as_deref())?;
    let pr = resolve_existing_pr(&repo, &args)?;
    if pr.state != "OPEN" {
        if args.json {
            print_closed_pr_json(&pr);
        } else {
            print_closed_pr_human(&pr);
        }
        bail!("PR #{} is {}", pr.number, pr.state);
    }
    let interval = args.interval.unwrap_or_else(|| Duration::from_secs(60));
    let timeout = args.timeout.unwrap_or_else(|| Duration::from_secs(30 * 60));
    let deadline = Instant::now() + timeout;

    loop {
        let snapshot = pr_watch_snapshot(&repo, &pr, &args)?;
        if args.json {
            print_pr_watch_json(&snapshot);
        } else {
            print_pr_watch_human(&snapshot);
        }

        match snapshot.state {
            WatchState::Success => return Ok(()),
            WatchState::Failed => bail!("PR checks or unresolved review comments need attention"),
            WatchState::Pending if args.once => bail!("PR checks are still pending"),
            WatchState::Pending => {
                if Instant::now() >= deadline {
                    bail!(
                        "timed out waiting for PR checks/comments after {}s",
                        timeout.as_secs()
                    );
                }
                thread::sleep(interval);
            }
        }
    }
}

fn pr_hygiene(args: PrHygieneArgs) -> Result<()> {
    if args.help {
        print_pr_hygiene_usage();
        return Ok(());
    }
    if which::which("gh").is_err() {
        bail!("gh CLI is not available on PATH");
    }

    let query = args
        .search
        .clone()
        .unwrap_or_else(|| "author:@me is:pr is:open archived:false".to_string());
    let mut report = gh_pr_hygiene_report(&query, args.limit)?;

    if !args.no_workspaces {
        match ws_config() {
            Ok(config) => {
                let mut workspace_cache: HashMap<String, Vec<PrWorkspaceCandidate>> =
                    HashMap::new();
                for pr in &mut report.prs {
                    let candidates =
                        workspace_cache
                            .entry(pr.repo_slug.clone())
                            .or_insert_with(|| {
                                discover_pr_workspace_candidates(pr, &config, &mut report.warnings)
                            });
                    pr.workspaces = match_pr_workspaces(pr, candidates, &mut report.warnings);
                }
            }
            Err(err) => report
                .warnings
                .push(format!("could not load jj workspace config: {err:#}")),
        }
    }

    for pr in &mut report.prs {
        apply_pr_hygiene_heuristics(pr);
    }
    report.prs.sort_by_key(pr_hygiene_sort_key);

    if args.json {
        print_pr_hygiene_json(&report);
    } else {
        print_pr_hygiene_human(&report);
    }

    Ok(())
}

fn pr_watch_snapshot(
    repo: &GithubRemote,
    pr: &ExistingPr,
    args: &PrArgs,
) -> Result<PrWatchSnapshot> {
    let checks = gh_pr_checks(repo, pr.number, args.required)?;
    let (review_decision, comments) = if args.ignore_comments {
        (None, Vec::new())
    } else {
        let (decision, comments) = gh_review_state(repo, pr.number)?;
        (Some(decision), comments)
    };
    let has_failures = checks
        .iter()
        .any(|check| matches!(check.bucket.as_str(), "fail" | "cancel"));
    let has_pending = checks.is_empty() || checks.iter().any(|check| check.bucket == "pending");
    let changes_requested = review_decision.as_deref() == Some("CHANGES_REQUESTED");
    let state = if has_failures || !comments.is_empty() || changes_requested {
        WatchState::Failed
    } else if has_pending {
        WatchState::Pending
    } else {
        WatchState::Success
    };
    Ok(PrWatchSnapshot {
        pr: pr.clone(),
        checks,
        comments,
        review_decision,
        state,
    })
}

fn resolve_existing_pr(repo: &GithubRemote, args: &PrArgs) -> Result<ExistingPr> {
    if let Some(pr) = args.pr.as_deref() {
        return gh_pr_view(repo, pr);
    }
    let head = resolve_pr_head(args, false)?;
    let prs = gh_prs_by_head(repo, &head.bookmark)?;
    match prs.as_slice() {
        [] => bail!(
            "no open PR found for head {} in {}",
            head.bookmark,
            repo.slug()
        ),
        [pr] => Ok(pr.clone()),
        many => bail!(
            "multiple open PRs found for head {} in {}: {}. Re-run with --pr <number>.",
            head.bookmark,
            repo.slug(),
            many.iter()
                .map(|pr| format!("#{}", pr.number))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

fn resolve_github_remote(
    explicit: Option<&str>,
    remote_override: Option<&str>,
) -> Result<GithubRemote> {
    if let Some(slug) = explicit {
        let (owner, repo) = parse_repo_slug(slug)?;
        return Ok(GithubRemote {
            name: "explicit".to_string(),
            url: format!("https://github.com/{owner}/{repo}"),
            owner,
            repo,
        });
    }

    let remotes = github_remotes()?;
    if let Some(remote_name) = remote_override {
        let matches: Vec<GithubRemote> = remotes
            .iter()
            .filter(|remote| remote.name == remote_name)
            .cloned()
            .collect();
        return match matches.as_slice() {
            [remote] => Ok(remote.clone()),
            [] => bail!("no GitHub remote named {remote_name} found; re-run with --repo <owner/repo> or another --remote"),
            _ => bail!("multiple GitHub remotes named {remote_name} found; re-run with --repo <owner/repo>"),
        };
    }

    let origin_matches: Vec<GithubRemote> = remotes
        .iter()
        .filter(|remote| remote.name == "origin")
        .cloned()
        .collect();
    match origin_matches.as_slice() {
        [remote] => return Ok(remote.clone()),
        many if many.len() > 1 => {
            bail!("multiple GitHub origin remotes found; re-run with --repo <owner/repo>")
        }
        _ => {}
    }
    match remotes.as_slice() {
        [remote] => Ok(remote.clone()),
        [] => bail!(
            "no github.com remotes found in `jj git remote list`; re-run with --repo <owner/repo>"
        ),
        many => bail!(
            "multiple GitHub remotes found: {}. Re-run with --repo <owner/repo>.",
            many.iter()
                .map(|remote| format!("{}={}", remote.name, remote.slug()))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

fn github_remotes() -> Result<Vec<GithubRemote>> {
    let output = run_jj_capture(["git", "remote", "list", "--color=never"])?;
    Ok(output
        .stdout
        .lines()
        .filter_map(parse_github_remote_line)
        .collect())
}

fn parse_github_remote_line(line: &str) -> Option<GithubRemote> {
    let mut parts = line.split_whitespace();
    let name = parts.next()?;
    let url = parts.next()?;
    let (owner, repo) = parse_github_remote_url(url)?;
    Some(GithubRemote {
        name: name.to_string(),
        url: url.to_string(),
        owner,
        repo,
    })
}

fn parse_github_remote_url(url: &str) -> Option<(String, String)> {
    let trimmed = url.trim().trim_end_matches(".git");
    let path = if let Some(rest) = trimmed.strip_prefix("git@github.com:") {
        rest
    } else if let Some(rest) = trimmed.strip_prefix("ssh://git@github.com/") {
        rest
    } else if let Some(rest) = trimmed.strip_prefix("https://github.com/") {
        rest
    } else if let Some(rest) = trimmed.strip_prefix("http://github.com/") {
        rest
    } else {
        return None;
    };
    parse_repo_slug(path).ok()
}

fn parse_repo_slug(slug: &str) -> Result<(String, String)> {
    let slug = slug.trim().trim_end_matches(".git").trim_matches('/');
    let mut parts = slug.split('/');
    let owner = parts.next().unwrap_or_default();
    let repo = parts.next().unwrap_or_default();
    if owner.is_empty() || repo.is_empty() || parts.next().is_some() {
        bail!("expected GitHub repo as <owner>/<repo>, got {slug}");
    }
    Ok((owner.to_string(), repo.to_string()))
}

fn sync_remote_for_repo(repo: &GithubRemote, args: &PrArgs) -> Result<Option<String>> {
    if let Some(remote) = args.remote.as_deref() {
        return Ok(Some(remote.to_string()));
    }
    if repo.name != "explicit" {
        return Ok(Some(repo.name.clone()));
    }
    if let Some(remote) = infer_remote_for_repo_slug(&repo.slug())? {
        return Ok(Some(remote));
    }
    Ok(jj_config_string("dotfiles.sync.remote")?)
}

fn resolve_push_remote(repo: &GithubRemote, args: &PrArgs) -> Result<String> {
    if let Some(remote) = args.remote.as_deref() {
        return Ok(remote.to_string());
    }
    if repo.name != "explicit" {
        return Ok(repo.name.clone());
    }
    infer_remote_for_repo_slug(&repo.slug())?.ok_or_else(|| {
        anyhow!(
            "could not infer a jj remote matching explicit repo {}. Re-run with --remote <remote> or --no-push and push manually.",
            repo.slug()
        )
    })
}

fn infer_remote_for_repo_slug(slug: &str) -> Result<Option<String>> {
    let mut matches: Vec<GithubRemote> = github_remotes()?
        .into_iter()
        .filter(|remote| remote.slug() == slug)
        .collect();
    dedup_github_remotes_by_name(&mut matches);
    match matches.as_slice() {
        [] => Ok(None),
        [remote] => Ok(Some(remote.name.clone())),
        many => bail!(
            "multiple jj remotes match GitHub repo {slug}: {}. Re-run with --remote <remote>.",
            many.iter()
                .map(|remote| remote.name.clone())
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

fn dedup_github_remotes_by_name(remotes: &mut Vec<GithubRemote>) {
    remotes.sort_by(|left, right| left.name.cmp(&right.name));
    remotes.dedup_by(|left, right| left.name == right.name);
}

fn resolve_pr_base(explicit: Option<&str>, sync_remote: Option<&str>) -> Result<PrBase> {
    if let Some(base) = explicit {
        if base == "trunk()" {
            bail!("`trunk()` is a jj revset, not a GitHub PR base branch. Re-run with --base <branch>.");
        }
        let pr_base = sync_bookmark_name(base).to_string();
        let sync_base = if split_bookmark_remote(base).is_some() || base == "trunk()" {
            base.to_string()
        } else {
            format!("{base}@{}", sync_remote.unwrap_or("origin"))
        };
        return Ok(PrBase {
            pr_base,
            sync_base,
            inferred: false,
        });
    }
    let sync_base = resolve_sync_base(sync_remote, true)?;
    if sync_base == "trunk()" {
        bail!("could not infer a GitHub PR base branch from jj sync fallback `trunk()`. Re-run with --base <branch>.");
    }
    Ok(PrBase {
        pr_base: sync_bookmark_name(&sync_base).to_string(),
        sync_base,
        inferred: true,
    })
}

fn resolve_pr_head(args: &PrArgs, allow_stack: bool) -> Result<PrHead> {
    if let Some(head) = args.head.as_deref() {
        return Ok(PrHead {
            bookmark: head.to_string(),
            inferred: false,
            source: "--head".to_string(),
        });
    }

    if let Some(bookmark) = one_non_integration_bookmark("@")? {
        return Ok(PrHead {
            bookmark,
            inferred: true,
            source: "current-change".to_string(),
        });
    }

    if allow_stack {
        if let Some(bookmark) = one_non_integration_bookmark("heads(::@ & bookmarks())")? {
            return Ok(PrHead {
                bookmark,
                inferred: true,
                source: "stack".to_string(),
            });
        }
    }

    bail!("no non-integration bookmark found for @ or its stack. Pass --head <bookmark>, create one with `jj bookmark set <name> -r @`, or enable auto-bookmarking and pass --ticket.")
}

fn resolve_pr_head_for_create(args: &PrArgs, create_bookmark: bool) -> Result<PrHead> {
    if let Some(head) = args.head.as_deref() {
        return Ok(PrHead {
            bookmark: head.to_string(),
            inferred: false,
            source: "--head".to_string(),
        });
    }

    if let Some(bookmark) = one_non_integration_bookmark("@")? {
        return Ok(PrHead {
            bookmark,
            inferred: true,
            source: "current-change".to_string(),
        });
    }

    if pr_auto_bookmark_enabled()? {
        let ticket = args.ticket.as_deref().ok_or_else(|| {
            anyhow!("no non-integration bookmark found at @; auto-bookmarking requires --ticket")
        })?;
        let short_description = args
            .short_description
            .clone()
            .or_else(|| args.title.as_deref().map(short_description_from_title))
            .ok_or_else(|| anyhow!("auto-bookmarking requires --short-description or --title"))?;
        let bookmark =
            render_bookmark_template(&pr_bookmark_template()?, ticket, &short_description)?;
        if create_bookmark {
            run_jj_status(["bookmark", "set", bookmark.as_str(), "-r", "@"])?;
        }
        return Ok(PrHead {
            bookmark,
            inferred: false,
            source: if create_bookmark {
                "auto-created".to_string()
            } else {
                "auto-create-plan".to_string()
            },
        });
    }

    bail!("jj pr create requires a non-integration bookmark at @. Pass --head <bookmark>, create one with `jj bookmark set <name> -r @`, or enable auto-bookmarking and pass --ticket.")
}

fn validate_body_source(args: &PrArgs, required: bool) -> Result<()> {
    match (args.body.is_some(), args.body_file.is_some(), required) {
        (true, true, _) => bail!("pass only one of --body or --body-file"),
        (false, false, true) => bail!("jj pr create requires --body or --body-file"),
        _ => Ok(()),
    }
}

fn reject_unsupported_pr_flags(command: &str, args: &PrArgs) -> Result<()> {
    if args.dry_run {
        bail!("jj pr {command} does not support --dry-run");
    }
    Ok(())
}

fn validate_pr_selector_args(args: &PrArgs) -> Result<()> {
    if args.head.is_some() && args.pr.is_some() {
        bail!("pass only one of --head or --pr");
    }
    Ok(())
}

fn validate_pr_doctor_args(args: &PrArgs) -> Result<()> {
    reject_unsupported_pr_flags("doctor", args)?;
    if let Some(flag) = first_unsupported_pr_flag(args, &["repo", "remote", "base", "head", "json"])
    {
        bail!("jj pr doctor does not support --{flag}");
    }
    Ok(())
}

fn validate_pr_create_args(args: &PrArgs) -> Result<()> {
    if let Some(flag) = first_unsupported_pr_flag(
        args,
        &[
            "base",
            "repo",
            "remote",
            "head",
            "title",
            "body",
            "body-file",
            "ticket",
            "short-description",
            "sync",
            "run-lints",
            "run-cr",
            "draft",
            "push",
            "no-push",
            "dry-run",
        ],
    ) {
        bail!("jj pr create does not support --{flag}");
    }
    Ok(())
}

fn validate_pr_update_args(args: &PrArgs) -> Result<()> {
    reject_unsupported_pr_flags("update", args)?;
    validate_pr_selector_args(args)?;
    if let Some(flag) = first_unsupported_pr_flag(
        args,
        &[
            "repo",
            "remote",
            "head",
            "pr",
            "title",
            "body",
            "body-file",
            "base",
        ],
    ) {
        bail!("jj pr update does not support --{flag}");
    }
    Ok(())
}

fn validate_pr_close_args(args: &PrArgs) -> Result<()> {
    reject_unsupported_pr_flags("close", args)?;
    validate_pr_selector_args(args)?;
    if let Some(flag) = first_unsupported_pr_flag(args, &["repo", "remote", "head", "pr"]) {
        bail!("jj pr close does not support --{flag}");
    }
    Ok(())
}

fn validate_pr_watch_args(args: &PrArgs) -> Result<()> {
    reject_unsupported_pr_flags("watch", args)?;
    validate_pr_selector_args(args)?;
    if let Some(flag) = first_unsupported_pr_flag(
        args,
        &[
            "repo",
            "remote",
            "head",
            "pr",
            "once",
            "json",
            "ignore-comments",
            "required",
            "interval",
            "timeout",
        ],
    ) {
        bail!("jj pr watch does not support --{flag}");
    }
    if !args.once
        && args
            .interval
            .unwrap_or_else(|| Duration::from_secs(60))
            .as_secs()
            < 5
    {
        bail!("jj pr watch requires --interval >= 5s unless --once is used");
    }
    Ok(())
}

fn first_unsupported_pr_flag(args: &PrArgs, allowed: &[&str]) -> Option<&'static str> {
    let candidates = [
        ("base", args.base.is_some()),
        ("repo", args.repo.is_some()),
        ("remote", args.remote.is_some()),
        ("head", args.head.is_some()),
        ("title", args.title.is_some()),
        ("body", args.body.is_some()),
        ("body-file", args.body_file.is_some()),
        ("ticket", args.ticket.is_some()),
        ("short-description", args.short_description.is_some()),
        ("pr", args.pr.is_some()),
        ("sync", args.sync),
        ("run-lints", args.run_lints),
        ("run-cr", args.run_cr),
        ("draft", args.draft),
        ("push", args.push),
        ("no-push", args.no_push),
        ("dry-run", args.dry_run),
        ("json", args.json),
        ("once", args.once),
        ("ignore-comments", args.ignore_comments),
        ("required", args.required),
        ("interval", args.interval.is_some()),
        ("timeout", args.timeout.is_some()),
    ];
    candidates
        .into_iter()
        .find(|(flag, present)| *present && !allowed.contains(flag))
        .map(|(flag, _)| flag)
}

fn one_non_integration_bookmark(revset: &str) -> Result<Option<String>> {
    let bookmarks: Vec<String> = bookmark_names_for_revset(revset)?
        .into_iter()
        .filter(|bookmark| !is_integration_bookmark(bookmark))
        .collect();
    match bookmarks.as_slice() {
        [] => Ok(None),
        [bookmark] => Ok(Some(bookmark.clone())),
        many => bail!(
            "multiple non-integration bookmarks found for {revset}: {}. Pass --head <bookmark>.",
            many.join(", ")
        ),
    }
}

fn pr_auto_bookmark_enabled() -> Result<bool> {
    Ok(jj_config_bool("dotfiles.pr.auto-bookmark")?.unwrap_or(false))
}

fn pr_bookmark_template() -> Result<String> {
    Ok(jj_config_string("dotfiles.pr.bookmark-template")?
        .unwrap_or_else(|| "{whoami}/{ticket-number}/{short-description}".to_string()))
}

fn render_bookmark_template(
    template: &str,
    ticket: &str,
    short_description: &str,
) -> Result<String> {
    validate_ticket(ticket)?;
    let whoami = env::var("USER").unwrap_or_else(|_| "chris".to_string());
    let rendered = template
        .replace("{whoami}", &slug_component(&whoami))
        .replace("{ticket-number}", ticket)
        .replace("{short-description}", &slug_component(short_description));
    if rendered.contains('{') || rendered.contains('}') {
        bail!("bookmark template contains unknown placeholders: {template}");
    }
    if rendered.trim().is_empty() || rendered.contains("//") {
        bail!("bookmark template rendered an invalid bookmark: {rendered}");
    }
    Ok(rendered)
}

fn validate_ticket(ticket: &str) -> Result<()> {
    let mut chars = ticket.chars();
    let Some(first) = chars.next() else {
        bail!("ticket number cannot be empty");
    };
    if !first.is_ascii_alphanumeric() {
        bail!("ticket number must start with a letter or number: {ticket}");
    }
    if !chars.all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-')) {
        bail!(
            "ticket number may only contain letters, numbers, dot, underscore, or hyphen: {ticket}"
        );
    }
    Ok(())
}

fn short_description_from_title(title: &str) -> String {
    let without_ticket = title
        .split_whitespace()
        .filter(|part| !(part.starts_with('[') && part.ends_with(']')))
        .collect::<Vec<_>>()
        .join(" ");
    let without_type = without_ticket
        .split_once(':')
        .map(|(_, rest)| rest.trim())
        .unwrap_or(without_ticket.trim());
    slug_component(without_type)
}

fn slug_component(value: &str) -> String {
    let mut out = String::new();
    let mut prev_dash = false;
    for ch in value.chars().flat_map(char::to_lowercase) {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            prev_dash = false;
        } else if !prev_dash {
            out.push('-');
            prev_dash = true;
        }
    }
    out.trim_matches('-').to_string()
}

fn ensure_no_conflicts_in(revset: &str) -> Result<()> {
    let conflicts = conflicted_changes_in(revset)?;
    if conflicts.is_empty() {
        Ok(())
    } else {
        bail!(
            "PR-relevant changes have conflicts: {}",
            conflicts.join(", ")
        )
    }
}

fn ensure_current_change_described(title: Option<&str>) -> Result<()> {
    if !commit_description_is_empty("@")? {
        return Ok(());
    }
    let hint = title
        .map(|title| format!("\nSuggested command:\n  jj describe -m {:?}", title))
        .unwrap_or_else(|| {
            "\nDescribe the current change with `jj describe -m <message>`.".to_string()
        });
    bail!("current change has no description and cannot be pushed.{hint}")
}

fn run_cr_review(base: &PrBase) -> Result<()> {
    let cr_base = cr_base_ref(&base.sync_base);
    eprintln!(
        "Running CodeRabbit against {cr_base} (from jj base {})",
        base.sync_base
    );
    let status = Command::new("cr")
        .args(["review", "--base"])
        .arg(&cr_base)
        .status()
        .context("failed to execute cr review")?;
    if status.success() {
        Ok(())
    } else {
        bail!("cr review --base {cr_base} failed with status {status}")
    }
}

fn cr_base_ref(sync_base: &str) -> String {
    split_bookmark_remote(sync_base)
        .map(|(bookmark, remote)| format!("{remote}/{bookmark}"))
        .unwrap_or_else(|| sync_base.to_string())
}

fn gh_prs_by_head(repo: &GithubRemote, head: &str) -> Result<Vec<ExistingPr>> {
    let args = vec![
        "pr".to_string(),
        "list".to_string(),
        "--repo".to_string(),
        repo.slug(),
        "--head".to_string(),
        head.to_string(),
        "--state".to_string(),
        "open".to_string(),
        "--json".to_string(),
        "number,url,title,state".to_string(),
    ];
    let stdout = gh_capture(&args, "gh pr list")?;
    parse_pr_list_json(&stdout)
}

fn gh_pr_view(repo: &GithubRemote, pr: &str) -> Result<ExistingPr> {
    let args = vec![
        "pr".to_string(),
        "view".to_string(),
        pr.to_string(),
        "--repo".to_string(),
        repo.slug(),
        "--json".to_string(),
        "number,url,title,state".to_string(),
    ];
    let stdout = gh_capture(&args, "gh pr view")?;
    parse_pr_json(&serde_json::from_str(&stdout).context("failed to parse gh pr view JSON")?)
}

fn gh_pr_create(
    repo: &GithubRemote,
    base: &PrBase,
    head: &PrHead,
    args: &PrArgs,
) -> Result<String> {
    let mut gh_args = vec![
        "pr".to_string(),
        "create".to_string(),
        "--repo".to_string(),
        repo.slug(),
        "--base".to_string(),
        base.pr_base.clone(),
        "--head".to_string(),
        head.bookmark.clone(),
        "--title".to_string(),
        args.title.clone().expect("title checked by caller"),
    ];
    if let Some(body) = args.body.as_deref() {
        gh_args.push("--body".to_string());
        gh_args.push(body.to_string());
    }
    if let Some(body_file) = args.body_file.as_deref() {
        gh_args.push("--body-file".to_string());
        gh_args.push(body_file.to_string());
    }
    if args.draft {
        gh_args.push("--draft".to_string());
    }
    Ok(gh_capture(&gh_args, "gh pr create")?.trim().to_string())
}

fn gh_pr_checks(repo: &GithubRemote, pr_number: u64, required: bool) -> Result<Vec<PrCheck>> {
    let mut args = vec![
        "pr".to_string(),
        "checks".to_string(),
        pr_number.to_string(),
        "--repo".to_string(),
        repo.slug(),
        "--json".to_string(),
        "name,bucket,state,link".to_string(),
    ];
    if required {
        args.push("--required".to_string());
    }
    let stdout = gh_capture_allow_exit_codes(&args, "gh pr checks", &[1, 8])?;
    parse_checks_json(&stdout)
}

fn gh_review_state(
    repo: &GithubRemote,
    pr_number: u64,
) -> Result<(String, Vec<UnresolvedComment>)> {
    let mut comments = Vec::new();
    let mut decision = String::new();
    let mut after: Option<String> = None;

    loop {
        let _first_page = decision.is_empty();
        let after_arg = after
            .as_deref()
            .map(|cursor| format!(", after: \"{}\"", json_escape(cursor)))
            .unwrap_or_default();
        let query = r#"
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewDecision
      reviewThreads(first: 100__AFTER__) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved
          isOutdated
          comments(last: 1) {
            nodes {
              author { login }
              bodyText
              path
              line
              url
            }
          }
        }
      }
    }
  }
}
"#
        .replace("__AFTER__", &after_arg);
        let args = vec![
            "api".to_string(),
            "graphql".to_string(),
            "-f".to_string(),
            format!("owner={}", repo.owner),
            "-f".to_string(),
            format!("repo={}", repo.repo),
            "-F".to_string(),
            format!("number={pr_number}"),
            "-f".to_string(),
            format!("query={query}"),
        ];
        let stdout = gh_capture(&args, "gh api graphql reviewThreads")?;
        let page = parse_review_state_json(&stdout)?;
        decision = page.review_decision;
        comments.extend(page.comments);
        if !page.has_next_page {
            break;
        }
        after = page.end_cursor;
        if after.is_none() {
            break;
        }
    }

    if decision.is_empty() {
        decision = "REVIEW_REQUIRED".to_string();
    }
    Ok((decision, comments))
}

fn gh_pr_hygiene_report(query: &str, limit: usize) -> Result<PrHygieneReport> {
    let graphql = r#"
query($searchQuery: String!, $first: Int!) {
  search(type: ISSUE, query: $searchQuery, first: $first) {
    issueCount
    nodes {
      ... on PullRequest {
        number
        title
        url
        state
        isDraft
        reviewDecision
        createdAt
        updatedAt
        headRefName
        baseRefName
        additions
        deletions
        changedFiles
        repository { nameWithOwner name owner { login } }
        commits { totalCount }
        statusCheckRollup {
          contexts(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              __typename
              ... on CheckRun { name status conclusion detailsUrl }
              ... on StatusContext { context state targetUrl }
            }
          }
        }
        reviewThreads(first: 50) {
          pageInfo { hasNextPage }
          nodes {
            isResolved
            isOutdated
            comments(last: 1) {
              nodes {
                author { login }
                bodyText
                path
                line
                url
              }
            }
          }
        }
      }
    }
  }
}
"#;
    let args = vec![
        "api".to_string(),
        "graphql".to_string(),
        "-f".to_string(),
        format!("query={graphql}"),
        "-f".to_string(),
        format!("searchQuery={query}"),
        "-F".to_string(),
        format!("first={limit}"),
    ];
    let stdout = gh_capture(&args, "gh api graphql PR hygiene search")?;
    parse_pr_hygiene_graphql(&stdout, query, limit)
}

fn parse_pr_hygiene_graphql(stdout: &str, query: &str, limit: usize) -> Result<PrHygieneReport> {
    let value: serde_json::Value =
        serde_json::from_str(stdout).context("failed to parse gh PR hygiene GraphQL JSON")?;
    if let Some(errors) = value.get("errors").and_then(serde_json::Value::as_array) {
        if !errors.is_empty() {
            bail!(
                "GitHub GraphQL returned errors: {}",
                summarize_graphql_errors(errors)
            );
        }
    }
    let search = value
        .pointer("/data/search")
        .ok_or_else(|| anyhow!("expected search data in GitHub GraphQL response"))?;
    let total_count = search
        .get("issueCount")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(0);
    let nodes = search
        .get("nodes")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| anyhow!("expected search nodes in GitHub GraphQL response"))?;
    let mut warnings = Vec::new();
    let prs = nodes
        .iter()
        .filter_map(|node| match parse_pr_hygiene_item(node) {
            Ok(pr) => Some(pr),
            Err(err) => {
                warnings.push(format!("skipped a PR search result: {err:#}"));
                None
            }
        })
        .collect();
    Ok(PrHygieneReport {
        query: query.to_string(),
        limit,
        total_count,
        warnings,
        prs,
    })
}

fn summarize_graphql_errors(errors: &[serde_json::Value]) -> String {
    errors
        .iter()
        .take(3)
        .map(|error| {
            error
                .get("message")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("unknown GraphQL error")
                .chars()
                .take(180)
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("; ")
}

fn parse_pr_hygiene_item(value: &serde_json::Value) -> Result<PrHygieneItem> {
    let repository = value
        .get("repository")
        .ok_or_else(|| anyhow!("PR JSON missing repository"))?;
    let repo_slug = repository
        .get("nameWithOwner")
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .or_else(|| {
            let owner = repository
                .pointer("/owner/login")
                .and_then(serde_json::Value::as_str)?;
            let name = repository.get("name").and_then(serde_json::Value::as_str)?;
            Some(format!("{owner}/{name}"))
        })
        .ok_or_else(|| anyhow!("PR JSON missing repository nameWithOwner"))?;
    let repo_name = repository
        .get("name")
        .and_then(serde_json::Value::as_str)
        .or_else(|| repo_slug.split('/').nth(1))
        .unwrap_or_default()
        .to_string();
    let review_decision = value
        .get("reviewDecision")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("REVIEW_REQUIRED")
        .to_string();
    Ok(PrHygieneItem {
        repo_slug,
        repo_name,
        number: required_u64(value, "number")?,
        url: string_field(value, "url"),
        title: string_field(value, "title"),
        state: string_field(value, "state"),
        is_draft: value
            .get("isDraft")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false),
        review_decision,
        created_at: string_field(value, "createdAt"),
        updated_at: string_field(value, "updatedAt"),
        head_ref_name: string_field(value, "headRefName"),
        base_ref_name: string_field(value, "baseRefName"),
        additions: u64_field(value, "additions"),
        deletions: u64_field(value, "deletions"),
        changed_files: u64_field(value, "changedFiles"),
        commits: value
            .pointer("/commits/totalCount")
            .and_then(serde_json::Value::as_u64)
            .unwrap_or(0),
        checks: parse_rollup_checks(value),
        comments: parse_unresolved_comments_from_threads(
            value
                .pointer("/reviewThreads/nodes")
                .and_then(serde_json::Value::as_array),
        ),
        checks_truncated: value
            .pointer("/statusCheckRollup/contexts/pageInfo/hasNextPage")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false),
        review_threads_truncated: value
            .pointer("/reviewThreads/pageInfo/hasNextPage")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false),
        workspaces: Vec::new(),
        status: String::new(),
        priority: String::new(),
        effort: String::new(),
        follow_up: String::new(),
    })
}

fn required_u64(value: &serde_json::Value, key: &str) -> Result<u64> {
    value
        .get(key)
        .and_then(serde_json::Value::as_u64)
        .ok_or_else(|| anyhow!("PR JSON missing {key}"))
}

fn u64_field(value: &serde_json::Value, key: &str) -> u64 {
    value
        .get(key)
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(0)
}

fn string_field(value: &serde_json::Value, key: &str) -> String {
    value
        .get(key)
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn parse_rollup_checks(pr: &serde_json::Value) -> Vec<PrCheck> {
    let Some(nodes) = pr
        .pointer("/statusCheckRollup/contexts/nodes")
        .and_then(serde_json::Value::as_array)
    else {
        return Vec::new();
    };
    nodes
        .iter()
        .map(|node| {
            let typename = node
                .get("__typename")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default();
            let name = if typename == "StatusContext" {
                string_field(node, "context")
            } else {
                string_field(node, "name")
            };
            let state = if typename == "StatusContext" {
                string_field(node, "state")
            } else {
                node.get("conclusion")
                    .and_then(serde_json::Value::as_str)
                    .or_else(|| node.get("status").and_then(serde_json::Value::as_str))
                    .unwrap_or_default()
                    .to_string()
            };
            let link = if typename == "StatusContext" {
                string_field(node, "targetUrl")
            } else {
                string_field(node, "detailsUrl")
            };
            PrCheck {
                name,
                bucket: bucket_for_rollup_check(&state),
                state,
                link,
            }
        })
        .collect()
}

fn bucket_for_rollup_check(state: &str) -> String {
    match state {
        "SUCCESS" => "pass",
        "NEUTRAL" | "SKIPPED" => "skipping",
        "FAILURE" | "ERROR" | "TIMED_OUT" | "ACTION_REQUIRED" | "STARTUP_FAILURE" | "STALE" => {
            "fail"
        }
        "CANCELLED" => "cancel",
        "COMPLETED" => "pass",
        "" => "pending",
        _ => "pending",
    }
    .to_string()
}

fn parse_unresolved_comments_from_threads(
    threads: Option<&Vec<serde_json::Value>>,
) -> Vec<UnresolvedComment> {
    let Some(threads) = threads else {
        return Vec::new();
    };
    let mut comments = Vec::new();
    for thread in threads {
        if thread
            .get("isResolved")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
            || thread
                .get("isOutdated")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false)
        {
            continue;
        }
        let Some(nodes) = thread
            .pointer("/comments/nodes")
            .and_then(serde_json::Value::as_array)
        else {
            continue;
        };
        let Some(comment) = nodes.last() else {
            continue;
        };
        comments.push(UnresolvedComment {
            author: comment
                .pointer("/author/login")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("unknown")
                .to_string(),
            path: string_field(comment, "path"),
            line: comment.get("line").and_then(serde_json::Value::as_u64),
            first_line: first_nonempty_line(
                comment
                    .get("bodyText")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or_default(),
            ),
            url: string_field(comment, "url"),
        });
    }
    comments
}

fn gh_capture(args: &[String], label: &str) -> Result<String> {
    gh_capture_allow_exit_codes(args, label, &[])
}

fn gh_capture_allow_exit_codes(
    args: &[String],
    label: &str,
    allowed_codes: &[i32],
) -> Result<String> {
    let output = Command::new("gh")
        .args(args)
        .env("GH_PROMPT_DISABLED", "1")
        .output()
        .with_context(|| format!("failed to execute {label}"))?;
    let allowed = output
        .status
        .code()
        .is_some_and(|code| allowed_codes.contains(&code));
    if !output.status.success() && !allowed {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!(
            "{label} failed with status {}: {}",
            output.status,
            stderr.trim()
        );
    }
    String::from_utf8(output.stdout).context("failed to decode gh stdout")
}

fn gh_status(args: &[String], label: &str) -> Result<()> {
    let status = Command::new("gh")
        .args(args)
        .env("GH_PROMPT_DISABLED", "1")
        .status()
        .with_context(|| format!("failed to execute {label}"))?;
    if status.success() {
        Ok(())
    } else {
        bail!("{label} failed with status {status}")
    }
}

fn parse_pr_list_json(stdout: &str) -> Result<Vec<ExistingPr>> {
    let value: serde_json::Value =
        serde_json::from_str(stdout).context("failed to parse gh pr list JSON")?;
    let array = value
        .as_array()
        .ok_or_else(|| anyhow!("expected gh pr list JSON array"))?;
    array.iter().map(parse_pr_json).collect()
}

fn parse_pr_json(value: &serde_json::Value) -> Result<ExistingPr> {
    Ok(ExistingPr {
        number: value
            .get("number")
            .and_then(serde_json::Value::as_u64)
            .ok_or_else(|| anyhow!("PR JSON missing number"))?,
        url: value
            .get("url")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string(),
        title: value
            .get("title")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string(),
        state: value
            .get("state")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string(),
    })
}

fn parse_checks_json(stdout: &str) -> Result<Vec<PrCheck>> {
    let value: serde_json::Value =
        serde_json::from_str(stdout).context("failed to parse gh pr checks JSON")?;
    let array = value
        .as_array()
        .ok_or_else(|| anyhow!("expected gh pr checks JSON array"))?;
    Ok(array
        .iter()
        .map(|check| PrCheck {
            name: check
                .get("name")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
            bucket: check
                .get("bucket")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
            state: check
                .get("state")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
            link: check
                .get("link")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
        })
        .collect())
}

fn parse_review_state_json(stdout: &str) -> Result<ReviewStatePage> {
    let value: serde_json::Value =
        serde_json::from_str(stdout).context("failed to parse gh reviewThreads JSON")?;
    let pr = value
        .pointer("/data/repository/pullRequest")
        .ok_or_else(|| anyhow!("expected pullRequest in GitHub GraphQL response"))?;
    let review_decision = pr
        .get("reviewDecision")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("REVIEW_REQUIRED")
        .to_string();
    let page_info = pr.pointer("/reviewThreads/pageInfo");
    let has_next_page = page_info
        .and_then(|page| page.get("hasNextPage"))
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);
    let end_cursor = page_info
        .and_then(|page| page.get("endCursor"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string);
    let threads = value
        .pointer("/data/repository/pullRequest/reviewThreads/nodes")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| anyhow!("expected reviewThreads nodes in GitHub GraphQL response"))?;
    let mut comments = Vec::new();
    for thread in threads {
        if thread
            .get("isResolved")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
            || thread
                .get("isOutdated")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false)
        {
            continue;
        }
        let Some(nodes) = thread
            .pointer("/comments/nodes")
            .and_then(serde_json::Value::as_array)
        else {
            continue;
        };
        let Some(comment) = nodes.last() else {
            continue;
        };
        comments.push(UnresolvedComment {
            author: comment
                .pointer("/author/login")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("unknown")
                .to_string(),
            path: comment
                .get("path")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
            line: comment.get("line").and_then(serde_json::Value::as_u64),
            first_line: first_nonempty_line(
                comment
                    .get("bodyText")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or_default(),
            ),
            url: comment
                .get("url")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default()
                .to_string(),
        });
    }
    Ok(ReviewStatePage {
        review_decision,
        comments,
        has_next_page,
        end_cursor,
    })
}

fn first_nonempty_line(body: &str) -> String {
    body.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("")
        .chars()
        .take(180)
        .collect()
}

fn parse_duration_arg(value: &str) -> Result<Duration> {
    let value = value.trim();
    if value.is_empty() {
        bail!("duration cannot be empty");
    }
    let (number, multiplier) = match value.chars().last().unwrap() {
        's' | 'S' => (&value[..value.len() - 1], 1),
        'm' | 'M' => (&value[..value.len() - 1], 60),
        'h' | 'H' => (&value[..value.len() - 1], 60 * 60),
        ch if ch.is_ascii_digit() => (value, 1),
        _ => bail!("duration must be seconds or use s/m/h suffix: {value}"),
    };
    let amount: u64 = number
        .parse()
        .with_context(|| format!("invalid duration: {value}"))?;
    if amount == 0 {
        bail!("duration must be greater than zero: {value}");
    }
    Ok(Duration::from_secs(amount.saturating_mul(multiplier)))
}

fn print_pr_doctor_json(
    repo: Option<&GithubRemote>,
    base: Option<&PrBase>,
    head: Option<&PrHead>,
    existing: Option<&ExistingPr>,
    blockers: &[String],
    warnings: &[String],
) {
    println!(
        "{}",
        json!({
            "version": 1,
            "repo": repo.map(|repo| json!({
                "owner": repo.owner,
                "name": repo.repo,
                "slug": repo.slug(),
                "remote": repo.name,
                "url": repo.url,
            })),
            "base": base.map(|base| json!({
                "pr": base.pr_base,
                "sync": base.sync_base,
                "inferred": base.inferred,
            })),
            "head": head.map(|head| json!({
                "bookmark": head.bookmark,
                "inferred": head.inferred,
                "source": head.source,
            })),
            "existingPr": existing.map(|pr| json!({
                "number": pr.number,
                "url": pr.url,
                "title": pr.title,
                "state": pr.state,
            })),
            "blockers": blockers,
            "warnings": warnings,
        })
    );
}

fn print_pr_doctor_human(
    repo: Option<&GithubRemote>,
    base: Option<&PrBase>,
    head: Option<&PrHead>,
    existing: Option<&ExistingPr>,
    blockers: &[String],
    warnings: &[String],
) {
    match repo {
        Some(repo) => println!("Repo: {} (remote {})", repo.slug(), repo.name),
        None => println!("Repo: unavailable"),
    }
    match base {
        Some(base) => println!("Base: {} (sync {})", base.pr_base, base.sync_base),
        None => println!("Base: unavailable"),
    }
    match head {
        Some(head) => println!("Head: {} ({})", head.bookmark, head.source),
        None => println!("Head: unavailable"),
    }
    match existing {
        Some(pr) => println!("Existing PR: #{} {}", pr.number, pr.url),
        None => println!("Existing PR: none detected"),
    }
    if warnings.is_empty() {
        println!("Warnings: none");
    } else {
        println!("Warnings:");
        for warning in warnings {
            println!(" - {warning}");
        }
    }
    if blockers.is_empty() {
        println!("Status: ready");
    } else {
        println!("Blockers:");
        for blocker in blockers {
            println!(" - {blocker}");
        }
    }
}

fn print_pr_watch_json(snapshot: &PrWatchSnapshot) {
    println!(
        "{}",
        json!({
            "version": 1,
            "pr": {
                "number": snapshot.pr.number,
                "url": snapshot.pr.url,
                "title": snapshot.pr.title,
                "state": snapshot.pr.state,
            },
            "state": match snapshot.state {
                WatchState::Success => "success",
                WatchState::Pending => "pending",
                WatchState::Failed => "failed",
            },
            "reviewDecision": snapshot.review_decision,
            "checks": snapshot.checks.iter().map(|check| json!({
                "name": check.name,
                "bucket": check.bucket,
                "state": check.state,
                "link": check.link,
            })).collect::<Vec<_>>(),
            "unresolvedComments": snapshot.comments.iter().map(|comment| json!({
                "author": comment.author,
                "path": comment.path,
                "line": comment.line,
                "firstLine": comment.first_line,
                "url": comment.url,
            })).collect::<Vec<_>>(),
        })
    );
}

fn print_closed_pr_json(pr: &ExistingPr) {
    println!(
        "{}",
        json!({
            "version": 1,
            "pr": {
                "number": pr.number,
                "url": pr.url,
                "title": pr.title,
                "state": pr.state,
            },
            "state": "closed",
            "checks": [],
            "unresolvedComments": [],
        })
    );
}

fn print_closed_pr_human(pr: &ExistingPr) {
    println!("PR #{}: {} {}", pr.number, pr.state, pr.url);
    println!("Status: closed; no active checks/review polling performed");
}

fn print_pr_watch_human(snapshot: &PrWatchSnapshot) {
    let pass = count_checks(&snapshot.checks, "pass");
    let fail = count_checks(&snapshot.checks, "fail") + count_checks(&snapshot.checks, "cancel");
    let pending = count_checks(&snapshot.checks, "pending");
    let skipping = count_checks(&snapshot.checks, "skipping");
    println!("PR #{}: {}", snapshot.pr.number, snapshot.pr.url);
    println!("Checks: {pass} pass, {pending} pending, {fail} fail/cancel, {skipping} skipped");
    if let Some(decision) = snapshot.review_decision.as_deref() {
        println!("Review decision: {decision}");
    }
    let failing: Vec<&PrCheck> = snapshot
        .checks
        .iter()
        .filter(|check| matches!(check.bucket.as_str(), "fail" | "cancel"))
        .collect();
    if !failing.is_empty() {
        println!("Failing checks:");
        for check in failing.iter().take(10) {
            println!(
                " - {}: {}{}",
                check.name,
                check.state,
                format_link(&check.link)
            );
        }
    }
    let pending_checks: Vec<&PrCheck> = snapshot
        .checks
        .iter()
        .filter(|check| check.bucket == "pending")
        .collect();
    if !pending_checks.is_empty() {
        println!("Pending checks:");
        for check in pending_checks.iter().take(10) {
            println!(" - {}: {}", check.name, check.state);
        }
        if pending_checks.len() > 10 {
            println!(" - ... {} more", pending_checks.len() - 10);
        }
    }
    if snapshot.comments.is_empty() {
        println!("Unresolved review comments: 0");
    } else {
        println!("Unresolved review comments: {}", snapshot.comments.len());
        for comment in snapshot.comments.iter().take(10) {
            let location = if comment.path.is_empty() {
                "PR".to_string()
            } else if let Some(line) = comment.line {
                format!("{}:{line}", comment.path)
            } else {
                comment.path.clone()
            };
            println!(
                " - {} {}: {}{}",
                comment.author,
                location,
                comment.first_line,
                format_link(&comment.url)
            );
        }
        if snapshot.comments.len() > 10 {
            println!(" - ... {} more", snapshot.comments.len() - 10);
        }
    }
    match snapshot.state {
        WatchState::Success => println!("Status: ready"),
        WatchState::Pending => println!("Status: pending"),
        WatchState::Failed => println!("Status: needs attention"),
    }
}

fn count_checks(checks: &[PrCheck], bucket: &str) -> usize {
    checks.iter().filter(|check| check.bucket == bucket).count()
}

fn format_link(link: &str) -> String {
    if link.is_empty() {
        String::new()
    } else {
        format!(" ({link})")
    }
}

fn discover_pr_workspace_candidates(
    pr: &PrHygieneItem,
    config: &WsConfig,
    warnings: &mut Vec<String>,
) -> Vec<PrWorkspaceCandidate> {
    let mut candidates = Vec::new();
    let mut seen = Vec::<PathBuf>::new();
    for (path, kind) in candidate_workspace_paths(config, &pr.repo_name) {
        let canonical = fs::canonicalize(&path).unwrap_or(path.clone());
        if seen.contains(&canonical) {
            continue;
        }
        seen.push(canonical.clone());
        match pr_workspace_candidate(&canonical, &kind, pr) {
            Ok(Some(workspace)) => candidates.push(workspace),
            Ok(None) => {}
            Err(err) => warnings.push(format!(
                "could not inspect workspace candidate {} for {}: {err:#}",
                canonical.display(),
                pr.repo_slug
            )),
        }
    }
    candidates.sort_by(|left, right| left.path.cmp(&right.path));
    candidates
}

fn match_pr_workspaces(
    pr: &PrHygieneItem,
    candidates: &[PrWorkspaceCandidate],
    warnings: &mut Vec<String>,
) -> Vec<PrWorkspaceMatch> {
    let mut matches = Vec::new();
    for candidate in candidates {
        match workspace_relation_to_pr_head(&candidate.path, &pr.head_ref_name) {
            Ok(Some(relation)) => matches.push(PrWorkspaceMatch {
                name: candidate.name.clone(),
                path: candidate.path.clone(),
                kind: candidate.kind.clone(),
                relation,
            }),
            Ok(None) => {}
            Err(err) => warnings.push(format!(
                "could not compare workspace {} to {}#{}: {err:#}",
                candidate.path.display(),
                pr.repo_slug,
                pr.number
            )),
        }
    }
    matches.sort_by(|left, right| left.path.cmp(&right.path));
    matches
}

fn candidate_workspace_paths(config: &WsConfig, repo_name: &str) -> Vec<(PathBuf, String)> {
    let mut paths = Vec::new();
    for group in &config.project_groups {
        let group_path = fs::canonicalize(&group.path).unwrap_or(group.path.clone());
        let main = group_path.join(repo_name);
        if main.is_dir() {
            paths.push((main, "main".to_string()));
        }
        let workspace_root = group_path.join(&group.workspace_dir).join(repo_name);
        if let Ok(entries) = fs::read_dir(&workspace_root) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    paths.push((path, "workspace".to_string()));
                }
            }
        }
    }
    paths
}

fn pr_workspace_candidate(
    path: &Path,
    kind: &str,
    pr: &PrHygieneItem,
) -> Result<Option<PrWorkspaceCandidate>> {
    let root_output = run_jj_capture_in_allow_failure(path, ["root", "--color=never"])?;
    if !root_output.status.success() {
        return Ok(None);
    }
    let root = fs::canonicalize(root_output.stdout.trim()).unwrap_or_else(|_| path.to_path_buf());
    let remotes = github_remotes_in(&root)?;
    if !remotes.iter().any(|remote| remote.slug() == pr.repo_slug) {
        return Ok(None);
    }
    let name = jj_config_string_in(&root, "workspace.name")?
        .or_else(|| {
            root.file_name()
                .map(|name| name.to_string_lossy().to_string())
        })
        .unwrap_or_else(|| "unknown".to_string());
    Ok(Some(PrWorkspaceCandidate {
        name,
        path: root,
        kind: kind.to_string(),
    }))
}

fn github_remotes_in(repo: &Path) -> Result<Vec<GithubRemote>> {
    let output = run_jj_capture_in_allow_failure(repo, ["git", "remote", "list", "--color=never"])?;
    if !output.status.success() {
        return Ok(Vec::new());
    }
    Ok(output
        .stdout
        .lines()
        .filter_map(parse_github_remote_line)
        .collect())
}

fn workspace_relation_to_pr_head(repo: &Path, head: &str) -> Result<Option<String>> {
    if head.trim().is_empty() {
        return Ok(None);
    }
    let revset = format!("(@ | @-) & (::bookmarks({head:?}) | bookmarks({head:?})::)");
    let output = run_jj_capture_in_allow_failure(
        repo,
        [
            "log",
            "--no-graph",
            "-r",
            &revset,
            "-T",
            "change_id.short() ++ \" \" ++ coalesce(description.first_line(), \"(no description set)\") ++ \"\\n\"",
            "--color=never",
            "--limit",
            "1",
        ],
    )?;
    if output.status.success() && !output.stdout.trim().is_empty() {
        Ok(Some(format!("current stack contains head `{head}`")))
    } else {
        Ok(None)
    }
}

fn jj_config_string_in(repo: &Path, key: &str) -> Result<Option<String>> {
    let output = run_jj_capture_in_allow_failure(repo, ["config", "get", key])?;
    if !output.status.success() {
        return Ok(None);
    }
    let value = output.stdout.trim().trim_matches('"').to_string();
    Ok((!value.is_empty()).then_some(value))
}

fn apply_pr_hygiene_heuristics(pr: &mut PrHygieneItem) {
    pr.effort = review_effort(pr.additions, pr.deletions, pr.changed_files, pr.commits);
    let fail = count_checks(&pr.checks, "fail") + count_checks(&pr.checks, "cancel");
    let pending = count_checks(&pr.checks, "pending");
    let checks_empty = pr.checks.is_empty();
    let updated_days = days_since_github_timestamp(&pr.updated_at);

    let needs_review = matches!(
        pr.review_decision.as_str(),
        "" | "REVIEW_REQUIRED" | "REVIEW_REQUIRED_BY_USER" | "REVIEW_REQUIRED_BY_OWNER"
    );
    let changes_requested = pr.review_decision == "CHANGES_REQUESTED";
    let approved = pr.review_decision == "APPROVED";

    if pr.is_draft {
        pr.status = "draft".to_string();
        pr.priority = "low".to_string();
        pr.follow_up = "finish the branch or mark it ready before asking reviewers".to_string();
    } else if fail > 0 {
        pr.status = "needs-fix".to_string();
        pr.priority = "high".to_string();
        pr.follow_up = "fix failing/cancelled checks before asking for more review".to_string();
    } else if changes_requested || !pr.comments.is_empty() {
        pr.status = "needs-fix".to_string();
        pr.priority = "high".to_string();
        pr.follow_up = "address review feedback, push, then re-request review".to_string();
    } else if pr.checks_truncated || pr.review_threads_truncated {
        pr.status = "unknown".to_string();
        pr.priority = "medium".to_string();
        pr.follow_up =
            "inspect the PR directly; GitHub returned truncated check/review data".to_string();
    } else if pending > 0 || checks_empty {
        pr.status = "waiting-ci".to_string();
        pr.priority = if updated_days.unwrap_or(0) >= 2 {
            "medium"
        } else {
            "low"
        }
        .to_string();
        pr.follow_up = "wait for checks; only nudge humans once CI is green".to_string();
    } else if approved {
        pr.status = "ready".to_string();
        pr.priority = "high".to_string();
        pr.follow_up = "merge or hand off the merge decision before it goes stale".to_string();
    } else if needs_review {
        pr.status = "needs-review".to_string();
        pr.priority = if updated_days.unwrap_or(0) >= 2 {
            "high"
        } else {
            "medium"
        }
        .to_string();
        pr.follow_up =
            "ask reviewers for eyes; include the PR size/effort in the nudge".to_string();
    } else {
        pr.status = "unknown".to_string();
        pr.priority = "medium".to_string();
        pr.follow_up = "inspect the PR; GitHub returned an uncommon review state".to_string();
    }
}

fn review_effort(additions: u64, deletions: u64, changed_files: u64, commits: u64) -> String {
    let changed_lines = additions.saturating_add(deletions);
    if changed_lines <= 80 && changed_files <= 4 && commits <= 3 {
        "XS (<10m)".to_string()
    } else if changed_lines <= 250 && changed_files <= 8 && commits <= 6 {
        "S (10-30m)".to_string()
    } else if changed_lines <= 750 && changed_files <= 20 && commits <= 12 {
        "M (30-60m)".to_string()
    } else if changed_lines <= 2000 && changed_files <= 40 {
        "L (1-2h)".to_string()
    } else {
        "XL (multi-hour)".to_string()
    }
}

fn pr_hygiene_sort_key(pr: &PrHygieneItem) -> (u8, u8, String, String, u64) {
    (
        match pr.priority.as_str() {
            "high" => 0,
            "medium" => 1,
            "low" => 2,
            _ => 3,
        },
        match pr.status.as_str() {
            "needs-fix" => 0,
            "ready" => 1,
            "needs-review" => 2,
            "waiting-ci" => 3,
            "draft" => 4,
            _ => 5,
        },
        pr.updated_at.clone(),
        pr.repo_slug.clone(),
        pr.number,
    )
}

fn days_since_github_timestamp(timestamp: &str) -> Option<u64> {
    let (year, month, day) = parse_github_ymd(timestamp)?;
    let then = days_from_civil(year, month, day);
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs() as i64 / 86_400;
    (now >= then).then_some((now - then) as u64)
}

fn parse_github_ymd(timestamp: &str) -> Option<(i32, u32, u32)> {
    if timestamp.len() < 10 {
        return None;
    }
    Some((
        timestamp.get(0..4)?.parse().ok()?,
        timestamp.get(5..7)?.parse().ok()?,
        timestamp.get(8..10)?.parse().ok()?,
    ))
}

fn days_from_civil(mut year: i32, month: u32, day: u32) -> i64 {
    year -= (month <= 2) as i32;
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let yoe = year - era * 400;
    let month = month as i32;
    let day = day as i32;
    let doy = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    (era * 146_097 + doe - 719_468) as i64
}

fn print_pr_hygiene_json(report: &PrHygieneReport) {
    println!(
        "{}",
        json!({
            "version": 1,
            "query": report.query,
            "limit": report.limit,
            "totalCount": report.total_count,
            "warnings": report.warnings,
            "prs": report.prs.iter().map(|pr| json!({
                "repo": pr.repo_slug,
                "number": pr.number,
                "url": pr.url,
                "title": pr.title,
                "state": pr.state,
                "isDraft": pr.is_draft,
                "reviewDecision": pr.review_decision,
                "createdAt": pr.created_at,
                "updatedAt": pr.updated_at,
                "headRefName": pr.head_ref_name,
                "baseRefName": pr.base_ref_name,
                "additions": pr.additions,
                "deletions": pr.deletions,
                "changedFiles": pr.changed_files,
                "commits": pr.commits,
                "dataTruncated": {
                    "checks": pr.checks_truncated,
                    "reviewThreads": pr.review_threads_truncated,
                },
                "status": pr.status,
                "priority": pr.priority,
                "reviewEffort": pr.effort,
                "followUp": pr.follow_up,
                "checks": pr.checks.iter().map(|check| json!({
                    "name": check.name,
                    "bucket": check.bucket,
                    "state": check.state,
                    "link": check.link,
                })).collect::<Vec<_>>(),
                "unresolvedComments": pr.comments.iter().map(|comment| json!({
                    "author": comment.author,
                    "path": comment.path,
                    "line": comment.line,
                    "firstLine": comment.first_line,
                    "url": comment.url,
                })).collect::<Vec<_>>(),
                "workspaces": pr.workspaces.iter().map(|workspace| json!({
                    "name": workspace.name,
                    "path": workspace.path.display().to_string(),
                    "kind": workspace.kind,
                    "relation": workspace.relation,
                })).collect::<Vec<_>>(),
            })).collect::<Vec<_>>(),
        })
    );
}

fn print_pr_hygiene_human(report: &PrHygieneReport) {
    println!(
        "Open PR hygiene: {} shown ({} total), query: {}",
        report.prs.len(),
        report.total_count,
        report.query
    );
    println!("Priority/effort are heuristic; use this to decide what to fix, merge, or nudge.\n");

    if report.prs.is_empty() {
        println!("No open PRs found.");
    }

    for (index, pr) in report.prs.iter().enumerate() {
        let pass = count_checks(&pr.checks, "pass");
        let fail = count_checks(&pr.checks, "fail") + count_checks(&pr.checks, "cancel");
        let pending = count_checks(&pr.checks, "pending");
        let updated_age = days_since_github_timestamp(&pr.updated_at)
            .map(|days| format!("{days}d ago"))
            .unwrap_or_else(|| pr.updated_at.clone());
        println!(
            "{}. {} · {} · {} · {}#{}",
            index + 1,
            pr.priority.to_uppercase(),
            pr.status,
            pr.effort,
            pr.repo_slug,
            pr.number
        );
        println!("   {}", pr.title);
        println!("   {}", pr.url);
        println!(
            "   branch: {} -> {} | updated: {} | size: +{} -{}, {} files, {} commits",
            pr.head_ref_name,
            pr.base_ref_name,
            updated_age,
            pr.additions,
            pr.deletions,
            pr.changed_files,
            pr.commits
        );
        println!(
            "   checks: {pass} pass, {pending} pending, {fail} fail/cancel | review: {} | unresolved comments: {}",
            pr.review_decision,
            pr.comments.len()
        );
        if pr.checks_truncated || pr.review_threads_truncated {
            println!(
                "   warning: GitHub response truncated{}{}; inspect the PR directly before nudging/merging",
                if pr.checks_truncated { " checks" } else { "" },
                if pr.review_threads_truncated { " review threads" } else { "" }
            );
        }
        if pr.workspaces.is_empty() {
            println!("   workspace: not found in configured jj workspace roots");
        } else {
            for workspace in &pr.workspaces {
                println!(
                    "   workspace: {} [{}; {}]",
                    workspace.path.display(),
                    workspace.kind,
                    workspace.relation
                );
            }
        }
        println!("   follow-up: {}", pr.follow_up);
        if pr.status == "needs-review" {
            println!(
                "   nudge: Please review {}#{} ({}, +{} -{}, {} files): {}",
                pr.repo_slug,
                pr.number,
                pr.effort,
                pr.additions,
                pr.deletions,
                pr.changed_files,
                pr.url
            );
        }
        println!();
    }

    if !report.warnings.is_empty() {
        println!("Warnings:");
        for warning in &report.warnings {
            println!(" - {warning}");
        }
    }
}

fn print_pr_usage() {
    eprintln!("Usage:\n  jj pr doctor [--json] [--repo <owner/repo>] [--remote <remote>] [--base <branch>] [--head <bookmark>]\n  jj pr create --title <title> (--body <text>|--body-file <file>) [--base <branch>] [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>] [--ticket <id>] [--sync] [--run-lints] [--run-cr] [--draft] [--no-push] [--dry-run]\n  jj pr update [--title <title>] [--body <text>|--body-file <file>] [--base <branch>] [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>|--pr <number>]\n  jj pr close [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>|--pr <number>]\n  jj pr watch [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>|--pr <number>] [--interval 60s] [--timeout 30m] [--once] [--json] [--ignore-comments] [--required]\n  jj pr hygiene [--limit 50] [--search <github-search>] [--json] [--no-workspaces]");
}

fn print_pr_doctor_usage() {
    eprintln!("Usage:\n  jj pr doctor [--json] [--repo <owner/repo>] [--remote <remote>] [--base <branch>] [--head <bookmark>]");
}

fn print_pr_create_usage() {
    eprintln!("Usage:\n  jj pr create --title <title> (--body <text>|--body-file <file>) [--base <branch>] [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>] [--ticket <id>] [--short-description <slug>] [--sync] [--run-lints] [--run-cr] [--draft] [--no-push] [--dry-run]");
}

fn print_pr_update_usage() {
    eprintln!("Usage:\n  jj pr update [--title <title>] [--body <text>|--body-file <file>] [--base <branch>] [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>|--pr <number>]");
}

fn print_pr_close_usage() {
    eprintln!("Usage:\n  jj pr close [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>|--pr <number>]");
}

fn print_pr_watch_usage() {
    eprintln!("Usage:\n  jj pr watch [--repo <owner/repo>] [--remote <remote>] [--head <bookmark>|--pr <number>] [--interval 60s] [--timeout 30m] [--once] [--json] [--ignore-comments] [--required]\n\nPolls GitHub checks, review decision, and unresolved review threads. Exits 0 when checks pass and no unresolved comments/blocking review decision remains; exits nonzero with a compact summary on failed checks, pending --once, comments, or timeout.");
}

fn print_pr_hygiene_usage() {
    eprintln!("Usage:\n  jj pr hygiene [--limit 50] [--search <github-search>] [--json] [--no-workspaces]\n\nFinds open PRs authored by you with GitHub search, enriches them with checks/review/size data, tries to locate related jj workspaces under configured project groups, and prints a follow-up report. Default search: author:@me is:pr is:open archived:false");
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
    venv_mode: String,
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
    eprintln!("Usage:\n  jj ws add <name> [-r <revset>] [--project-group <path>] [--venv=<copy|link|none>] [--no-envrc] [--no-venv] [--no-direnv] [-q]\n\nCreates <project-group>/<workspace-dir>/<repo>/<name>.\nDefault base: main checkout -> inferred remote bookmark; workspace -> @.\n\nExamples:\n  jj ws add feature-x -q\n  jj ws add followup -r @\n  jj ws add hotfix --revision main@origin");
}

fn print_ws_list_usage() {
    eprintln!("Usage:\n  jj ws list [--pick]\n\nLists workspaces for this repo. --pick requires an interactive terminal.");
}

fn print_ws_path_usage() {
    eprintln!("Usage:\n  jj ws path <name>\n  jj ws path --pick\n\nPrints only the workspace path. --pick requires an interactive terminal.");
}

fn print_ws_forget_usage() {
    eprintln!("Usage:\n  jj ws forget <name> [--force] [--keep-dir] [--no-docker] [--docker-volumes|--keep-docker-volumes] [--dry-run] [-q]\n  jj ws forget --pick [options]\n\nForgets and deletes a workspace. Refuses current/non-empty work unless --force.\nDocker Compose cleanup removes volumes by default; use --keep-docker-volumes to keep them.\n\nExamples:\n  jj ws forget feature-x --dry-run\n  jj ws forget feature-x\n  jj ws forget scratch --force -q");
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
    let groups = jj_config_project_groups()?;
    Ok(WsConfig {
        project_groups: groups,
        copy_envrc,
        venv_mode,
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
    venv_mode: Option<String>,
    no_venv: bool,
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
    if let Some(mode) = parsed.venv_mode.as_deref() {
        validate_venv_mode(mode)?;
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
    if !parsed.no_venv {
        let venv_mode = parsed.venv_mode.as_deref().unwrap_or(&config.venv_mode);
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
        if direnv_allowed {
            println!("direnv allowed");
        }
    }
    Ok(())
}

fn copy_jj_lint_config_if_needed(src: &Path, dest: &Path) -> Result<bool> {
    let src_lint_config = src.join(".jj-lint.toml");
    let dest_lint_config = dest.join(".jj-lint.toml");
    if !src_lint_config.exists() || dest_lint_config.exists() {
        return Ok(false);
    }
    fs::copy(&src_lint_config, &dest_lint_config)
        .with_context(|| format!("failed to copy {}", src_lint_config.display()))?;
    Ok(true)
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VenvAction {
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

fn setup_venv_if_needed(src: &Path, dest: &Path, mode: &str) -> Result<Option<VenvAction>> {
    let src_venv = src.join(".venv");
    let dest_venv = dest.join(".venv");
    if !src_venv.exists()
        || dest_venv.exists()
        || file_is_tracked(src, ".venv")?
        || !source_venv_python_usable(&src_venv)
    {
        return Ok(None);
    }
    match mode {
        "none" => Ok(None),
        "link" => {
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
            clone_or_copy_dir(&src_venv, &dest_venv)?;
            repair_venv_paths(&src_venv, &dest_venv)?;
            Ok(Some(VenvAction::Copied))
        }
        other => bail!("invalid venv mode {other:?}; expected copy, link, or none"),
    }
}

fn source_venv_python_usable(src_venv: &Path) -> bool {
    src_venv.join("bin/python").exists()
}

fn clone_or_copy_dir(src: &Path, dest: &Path) -> Result<()> {
    let clone_args: Vec<&str> = if cfg!(target_os = "macos") {
        vec!["-cR"]
    } else {
        vec!["-a", "--reflink=auto"]
    };
    if run_cp(&clone_args, src, dest)? {
        return Ok(());
    }
    let _ = fs::remove_dir_all(dest);
    let copy_args: Vec<&str> = if cfg!(target_os = "macos") {
        vec!["-pR"]
    } else {
        vec!["-a"]
    };
    if run_cp(&copy_args, src, dest)? {
        return Ok(());
    }
    bail!("failed to copy {} to {}", src.display(), dest.display())
}

fn run_cp(args: &[&str], src: &Path, dest: &Path) -> Result<bool> {
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

fn repair_venv_paths(src_venv: &Path, dest_venv: &Path) -> Result<()> {
    let old = fs::canonicalize(src_venv).unwrap_or_else(|_| src_venv.to_path_buf());
    let new = fs::canonicalize(dest_venv).unwrap_or_else(|_| dest_venv.to_path_buf());
    let old = old.to_string_lossy();
    let new = new.to_string_lossy();
    replace_path_in_text_file(&dest_venv.join("pyvenv.cfg"), &old, &new)?;
    let bin = dest_venv.join("bin");
    if bin.exists() {
        for entry in fs::read_dir(bin)? {
            let path = entry?.path();
            if path.is_file() {
                replace_path_in_text_file(&path, &old, &new)?;
            }
        }
    }
    Ok(())
}

fn replace_path_in_text_file(path: &Path, old: &str, new: &str) -> Result<()> {
    let Ok(bytes) = fs::read(path) else {
        return Ok(());
    };
    let Ok(text) = String::from_utf8(bytes) else {
        return Ok(());
    };
    if text.contains(old) {
        fs::write(path, text.replace(old, new))?;
    }
    Ok(())
}

#[cfg(unix)]
fn symlink_path(src: &Path, dest: &Path) -> std::io::Result<()> {
    unix_fs::symlink(src, dest)
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
    keep_docker_volumes: bool,
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
    Ok(parsed)
}

fn validate_venv_mode(mode: &str) -> Result<()> {
    match mode {
        "copy" | "link" | "none" => Ok(()),
        other => bail!("invalid venv mode {other:?}; expected copy, link, or none"),
    }
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
    if !parsed.force && workspace_has_unpublished_work(&target)? {
        bail!("workspace {name} has unpublished work at {}\n\nReview it first with:\n  jj --repository {} status\n\nIf this workspace was already pushed or merged, fetch remote refs and retry:\n  jj --repository {} git fetch\n\nUse --force to forget and delete anyway.", target.display(), target.display(), target.display());
    }
    let config = ws_config()?;
    let has_compose = has_compose_file(&path);
    let remove_docker_volumes =
        parsed.docker_volumes || (config.docker_remove_volumes && !parsed.keep_docker_volumes);
    if parsed.dry_run {
        println!("would forget {name} at {}", path.display());
        if !parsed.no_docker && config.docker_cleanup == "auto" && has_compose {
            if remove_docker_volumes {
                println!("would run: docker compose down --remove-orphans --volumes");
            } else {
                println!("would run: docker compose down --remove-orphans");
            }
        }
        return Ok(());
    }
    if !parsed.no_docker && config.docker_cleanup == "auto" && has_compose {
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

fn workspace_has_unpublished_work(repo: &Path) -> Result<bool> {
    // A workspace is safe to discard only when every non-empty commit in its
    // stack is already reachable from a remote ref. An empty `@` is not enough:
    // agents may create a new empty working copy after leaving unpublished work
    // in `@-`, and forgetting that workspace would otherwise delete the only
    // checkout pointing at the unpublished stack.
    let unpublished_revset = "(::@ ~ ::(remote_bookmarks() | remote_tags())) ~ empty()";
    Ok(revset_has_commits_in(repo, unpublished_revset)?)
}

fn revset_has_commits_in(repo: &Path, revset: &str) -> Result<bool> {
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

#[derive(Debug, Clone)]
struct LintCommand {
    command: String,
    name: Option<String>,
}

#[derive(Debug, Clone)]
struct LintSuggestion {
    command: String,
    source: String,
    reason: String,
}

#[derive(Debug, Clone)]
struct LintOnboardReport {
    suggestions: Vec<LintSuggestion>,
    inspect: Vec<String>,
}

fn jj_root() -> Result<PathBuf> {
    let output = run_jj_capture(["root"])?;
    Ok(PathBuf::from(output.stdout.trim()))
}

fn configured_lints(repo: &Path) -> Result<Vec<LintCommand>> {
    let lint_file = repo.join(".jj-lint.toml");
    if lint_file.exists() {
        return Ok(parse_lints_toml(&fs::read_to_string(lint_file)?));
    }
    let output = run_jj_capture_in_allow_failure(repo, ["config", "get", "dotfiles.push-lints"])?;
    if output.status.success() {
        return Ok(parse_config_string_array(&output.stdout)
            .into_iter()
            .map(|command| LintCommand {
                command,
                name: None,
            })
            .collect());
    }
    Ok(Vec::new())
}

fn lint_display_name(lint: &LintCommand) -> String {
    lint.name
        .clone()
        .unwrap_or_else(|| infer_lint_name(&lint.command))
}

fn parse_lints_toml(input: &str) -> Vec<LintCommand> {
    let Some(array) = extract_toml_array(input, "lints") else {
        return Vec::new();
    };
    split_top_level_items(array)
        .into_iter()
        .filter_map(|item| parse_lint_config_item(&item))
        .collect()
}

fn extract_toml_array<'a>(input: &'a str, key: &str) -> Option<&'a str> {
    for (line_start, line) in input.lines().scan(0, |offset, line| {
        let start = *offset;
        *offset += line.len() + 1;
        Some((start, line))
    }) {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') || !trimmed.starts_with(key) {
            continue;
        }
        let rest = trimmed.strip_prefix(key)?.trim_start();
        let rest = rest.strip_prefix('=')?.trim_start();
        let bracket_in_line = rest.find('[')?;
        let start = line_start + line.find(rest).unwrap_or(0) + bracket_in_line;
        return matching_bracket_contents(input, start, '[', ']');
    }
    None
}

fn matching_bracket_contents(input: &str, start: usize, open: char, close: char) -> Option<&str> {
    let mut in_string = false;
    let mut escaped = false;
    let mut depth = 0usize;
    for (offset, ch) in input[start..].char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        match ch {
            '\\' if in_string => escaped = true,
            '"' => in_string = !in_string,
            _ if in_string => {}
            ch if ch == open => depth += 1,
            ch if ch == close => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    return Some(&input[start + 1..start + offset]);
                }
            }
            _ => {}
        }
    }
    None
}

fn split_top_level_items(input: &str) -> Vec<String> {
    let mut items = Vec::new();
    let mut in_string = false;
    let mut escaped = false;
    let mut in_comment = false;
    let mut brace_depth = 0usize;
    let mut bracket_depth = 0usize;
    let mut current = String::new();
    for ch in input.chars() {
        if in_comment {
            if ch == '\n' {
                in_comment = false;
            }
            continue;
        }
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        match ch {
            '\\' if in_string => {
                current.push(ch);
                escaped = true;
            }
            '"' => {
                current.push(ch);
                in_string = !in_string;
            }
            _ if in_string => current.push(ch),
            '#' => in_comment = true,
            '{' => {
                brace_depth += 1;
                current.push(ch);
            }
            '}' => {
                brace_depth = brace_depth.saturating_sub(1);
                current.push(ch);
            }
            '[' => {
                bracket_depth += 1;
                current.push(ch);
            }
            ']' => {
                bracket_depth = bracket_depth.saturating_sub(1);
                current.push(ch);
            }
            ',' if brace_depth == 0 && bracket_depth == 0 => {
                let item = current.trim();
                if !item.is_empty() {
                    items.push(item.to_string());
                }
                current.clear();
            }
            _ => current.push(ch),
        }
    }
    let item = current.trim();
    if !item.is_empty() {
        items.push(item.to_string());
    }
    items
}

fn parse_lint_config_item(item: &str) -> Option<LintCommand> {
    let trimmed = item.trim();
    if trimmed.starts_with('"') {
        return parse_toml_string(trimmed).map(|command| LintCommand {
            command,
            name: None,
        });
    }
    let table = trimmed.strip_prefix('{')?.strip_suffix('}')?;
    let mut command = None;
    let mut name = None;
    for field in split_top_level_items(table) {
        let Some((key, value)) = field.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        match key {
            "command" => command = parse_toml_string(value),
            "name" => name = parse_toml_string(value),
            _ => {}
        }
    }
    command.map(|command| LintCommand { command, name })
}

fn parse_toml_string(input: &str) -> Option<String> {
    parse_config_string_array(input).into_iter().next()
}

fn parse_config_string_array(input: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut in_string = false;
    let mut escaped = false;
    let mut current = String::new();
    for ch in input.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        match ch {
            '\\' if in_string => escaped = true,
            '"' => {
                if in_string {
                    out.push(current.clone());
                    current.clear();
                }
                in_string = !in_string;
            }
            _ if in_string => current.push(ch),
            _ => {}
        }
    }
    out
}

fn lint_onboard_report(repo: &Path) -> Result<LintOnboardReport> {
    let mut report = LintOnboardReport {
        suggestions: Vec::new(),
        inspect: Vec::new(),
    };
    detect_package_json(repo, &mut report)?;
    detect_python(repo, &mut report)?;
    if repo.join("Cargo.toml").exists() {
        add_lint(
            &mut report,
            "cargo fmt --check",
            "Cargo.toml",
            "Rust format check",
        );
        add_lint(
            &mut report,
            "cargo clippy --workspace --all-targets -- -D warnings",
            "Cargo.toml",
            "Rust clippy workspace check",
        );
        add_lint(
            &mut report,
            "cargo test --workspace",
            "Cargo.toml",
            "Rust workspace test suite",
        );
    }
    if repo.join("flake.nix").exists() {
        add_lint(
            &mut report,
            "nix flake check",
            "flake.nix",
            "Nix flake validation",
        );
    }
    add_inspect_if_exists(
        repo,
        &mut report,
        ".pre-commit-config.yaml",
        ".pre-commit-config.yaml -> consider pre-commit run --all-files or equivalent commands",
    );
    if repo.join(".husky").exists() {
        report.inspect.push(".husky/ -> inspect pre-commit/pre-push hooks; replace staged hooks with all-files commands".to_string());
    }
    if is_executable_file(&repo.join("lint")) {
        add_lint(
            &mut report,
            "./lint",
            "executable root lint script",
            "project-provided lint entrypoint",
        );
    }
    if is_executable_file(&repo.join("ci/check")) {
        add_lint(
            &mut report,
            "ci/check",
            "executable ci/check script",
            "project-provided CI check entrypoint",
        );
    }
    for script in [
        "scripts/check",
        "scripts/lint",
        "scripts/test",
        "scripts/coverage",
        "tools/check",
        "tools/lint",
        "bin/check",
        "bin/lint",
    ] {
        let path = repo.join(script);
        if path.is_file() {
            if script.ends_with("/lint") {
                report.inspect.push(format!(
                    "{script} -> inspect before adding; lint scripts may auto-fix"
                ));
            } else if script.ends_with("/coverage") {
                report.inspect.push(format!(
                    "{script} -> inspect before adding; coverage can be slower than normal tests"
                ));
            } else {
                add_lint(
                    &mut report,
                    script,
                    "project script entrypoint",
                    "project-provided validation entrypoint",
                );
            }
        }
    }
    if any_exists(repo, &["lefthook.yml", "lefthook.yaml"]) {
        report
            .inspect
            .push("lefthook config -> inspect lefthook run pre-commit/pre-push".to_string());
    }
    if any_exists(repo, &["Makefile", "makefile", "GNUmakefile"]) {
        detect_makefile(repo, &mut report)?;
        report.inspect.push(
            "Makefile -> inspect make help, make lint, make test, make check, make ci".to_string(),
        );
    }
    if any_exists(repo, &["justfile", "Justfile"]) {
        report
            .inspect
            .push("justfile -> inspect just --list, just lint, just test, just check".to_string());
    }
    if any_exists(
        repo,
        &[
            "compose.yaml",
            "compose.yml",
            "docker-compose.yaml",
            "docker-compose.yml",
        ],
    ) {
        report.inspect.push(
            "Docker Compose -> look for docker compose run --rm test/app/web ... commands"
                .to_string(),
        );
    }
    add_inspect_if_exists(
        repo,
        &mut report,
        "README.md",
        "README.md -> search for test/lint/check/typecheck/docker compose/make/just/before pushing",
    );
    add_inspect_if_exists(
        repo,
        &mut report,
        "CONTRIBUTING.md",
        "CONTRIBUTING.md -> search for local validation and pre-push commands",
    );
    add_inspect_if_exists(
        repo,
        &mut report,
        "CONTRIBUTING.rst",
        "CONTRIBUTING.rst -> search for local validation and pre-push commands",
    );
    add_inspect_if_exists(
        repo,
        &mut report,
        ".github/CONTRIBUTING.md",
        ".github/CONTRIBUTING.md -> search for local validation and pre-push commands",
    );
    if repo.join(".github/workflows").exists() {
        report.inspect.push(
            ".github/workflows/ -> inspect CI run commands for local equivalents".to_string(),
        );
    }
    if repo.join(".builds").exists() {
        report
            .inspect
            .push(".builds/ -> inspect SourceHut CI commands for local equivalents".to_string());
    }
    if any_exists(repo, &[".build.yml", ".build.yaml"]) {
        report.inspect.push(
            ".build.yml/.build.yaml -> inspect SourceHut CI commands for local equivalents"
                .to_string(),
        );
    }
    add_inspect_if_exists(
        repo,
        &mut report,
        ".gitlab-ci.yml",
        ".gitlab-ci.yml -> inspect CI script commands for local equivalents",
    );
    prefer_aggregate_lints(&mut report);
    Ok(report)
}

fn detect_makefile(repo: &Path, report: &mut LintOnboardReport) -> Result<()> {
    let Some(path) = ["Makefile", "makefile", "GNUmakefile"]
        .iter()
        .map(|name| repo.join(name))
        .find(|path| path.exists())
    else {
        return Ok(());
    };
    let contents = fs::read_to_string(path)?;
    for target in makefile_targets(&contents) {
        add_lint(
            report,
            &format!("make {target}"),
            "Makefile target",
            "project Makefile validation target",
        );
    }
    Ok(())
}

fn detect_package_json(repo: &Path, report: &mut LintOnboardReport) -> Result<()> {
    let path = repo.join("package.json");
    if !path.exists() {
        return Ok(());
    }
    let value: serde_json::Value = serde_json::from_str(&fs::read_to_string(path)?)?;
    let scripts = value.get("scripts").and_then(|v| v.as_object());
    let pm = if repo.join("pnpm-lock.yaml").exists() {
        "pnpm"
    } else if repo.join("yarn.lock").exists() {
        "yarn"
    } else if repo.join("bun.lock").exists() || repo.join("bun.lockb").exists() {
        "bun run"
    } else {
        "npm run"
    };
    if let Some(scripts) = scripts {
        for script in ["lint", "typecheck", "check", "test"] {
            if scripts.contains_key(script) {
                let command = if pm == "npm run" && script == "test" {
                    "npm test".to_string()
                } else {
                    format!("{pm} {script}")
                };
                add_lint(
                    report,
                    &command,
                    &format!("package.json scripts.{script}"),
                    &format!("standard {script} script"),
                );
            }
        }
        let format_check = ["format:check", "format-check", "format:ci"]
            .iter()
            .find(|script| scripts.contains_key(**script));
        if let Some(script) = format_check {
            add_lint(
                report,
                &format!("{pm} {script}"),
                &format!("package.json scripts.{script}"),
                "check-only format script",
            );
        } else if let Some(format) = scripts.get("format").and_then(|value| value.as_str()) {
            if is_check_only_format_script(format) {
                add_lint(
                    report,
                    &format!("{pm} format"),
                    "package.json scripts.format",
                    "check-only format script",
                );
            } else {
                report.inspect.push("package.json scripts.format -> inspect before adding; format scripts often mutate files. Prefer format:check/format-check/prettier --check/biome check when available".to_string());
            }
        }
        for (script, value) in scripts {
            if [
                "lint",
                "typecheck",
                "check",
                "test",
                "format",
                "format:check",
                "format-check",
                "format:ci",
                "build",
            ]
            .contains(&script.as_str())
            {
                continue;
            }
            let Some(body) = value.as_str() else {
                continue;
            };
            if is_safe_package_check_script(body) {
                add_lint(
                    report,
                    &format!("{pm} {script}"),
                    &format!("package.json scripts.{script}"),
                    "check-like package script body",
                );
            }
        }
        if scripts.contains_key("build") {
            report.inspect.push("package.json scripts.build -> inspect before adding; builds can be slow or require env".to_string());
        }
        if let Some(check) = scripts.get("check").and_then(|value| value.as_str()) {
            for included in ["lint", "format", "typecheck", "test"] {
                if check.contains(included) {
                    report.inspect.push(format!(
                        "package.json scripts.check includes {included}; avoid redundant jj lint entries if using the aggregate check script"
                    ));
                }
            }
        }
        for aggregate in ["check", "test"] {
            if let Some(value) = scripts.get(aggregate).and_then(|value| value.as_str()) {
                let included = ["lint", "format", "typecheck", "test"]
                    .into_iter()
                    .filter(|name| *name != aggregate && value.contains(name))
                    .collect::<Vec<_>>();
                if !included.is_empty() {
                    report.inspect.push(format!(
                        "package.json scripts.{aggregate} appears to include {}; avoid redundant jj lint entries if using the aggregate script",
                        included.join(", ")
                    ));
                }
            }
        }
    }
    if value.get("lint-staged").is_some() {
        report.inspect.push(
            "package.json lint-staged -> staged-file hook; prefer all-files equivalents for jj"
                .to_string(),
        );
    }
    Ok(())
}

fn detect_python(repo: &Path, report: &mut LintOnboardReport) -> Result<()> {
    let pyproject = repo.join("pyproject.toml");
    let tox_ini = repo.join("tox.ini");
    let noxfile = repo.join("noxfile.py");
    let is_python = pyproject.exists()
        || tox_ini.exists()
        || noxfile.exists()
        || any_exists(repo, &["uv.lock", "poetry.lock", "pdm.lock", "hatch.toml"]);
    if !is_python {
        return Ok(());
    }

    report.inspect.push("Python project -> inspect pyproject.toml/tox/nox/pre-commit for canonical lint, typecheck, and test commands".to_string());

    if pyproject.exists() {
        let contents = fs::read_to_string(&pyproject)?;
        let wrapper = python_runner(repo, &contents);
        let ruff_may_fix = toml_bool_in_section(&contents, "tool.ruff", "fix").unwrap_or(false)
            || toml_bool_in_section(&contents, "tool.ruff.lint", "fix").unwrap_or(false);
        if contents.contains("[tool.ruff") {
            if ruff_may_fix {
                report.inspect.push("pyproject.toml tool.ruff fix=true -> inspect before adding ruff check; prefer a non-mutating wrapper or override".to_string());
            } else {
                add_lint(
                    report,
                    &format!("{wrapper}ruff check ."),
                    "pyproject.toml tool.ruff",
                    "Python ruff lint check",
                );
            }
            add_lint(
                report,
                &format!("{wrapper}ruff format --check ."),
                "pyproject.toml tool.ruff",
                "Python ruff format check",
            );
        }
        if contents.contains("[tool.mypy") {
            add_lint(
                report,
                &format!("{wrapper}mypy"),
                "pyproject.toml tool.mypy",
                "Python mypy typecheck",
            );
        }
        if contents.contains("[tool.pyright") {
            add_lint(
                report,
                &format!("{wrapper}pyright"),
                "pyproject.toml tool.pyright",
                "Python pyright typecheck",
            );
        }
        if contents.contains("[tool.pytest") || contents.contains("[tool.pytest.ini_options") {
            add_lint(
                report,
                &format!("{wrapper}pytest"),
                "pyproject.toml tool.pytest",
                "Python pytest test suite",
            );
        }
        if contents.contains("[tool.tox") {
            report.inspect.push("pyproject.toml tool.tox -> inspect tox envs such as style, lint, linting, typing, typecheck, tests".to_string());
            for env in python_tox_like_envs(&contents) {
                add_lint(
                    report,
                    &format!("tox run -e {env}"),
                    "pyproject.toml tool.tox",
                    "Python tox validation env",
                );
            }
        }
        for group in [
            "linting",
            "typechecking",
            "testing",
            "tests",
            "test",
            "typecheck",
            "dev",
        ] {
            if contents.contains(&format!("{group} ="))
                || contents.contains(&format!("[dependency-groups.{group}]"))
            {
                report.inspect.push(format!("pyproject.toml dependency group '{group}' -> inspect for uv/pdm/poetry validation commands"));
            }
        }
    }

    if tox_ini.exists() {
        let contents = fs::read_to_string(&tox_ini)?;
        report.inspect.push(
            "tox.ini -> inspect envlist/testenv commands for canonical validation".to_string(),
        );
        for env in tox_ini_envs(&contents) {
            add_lint(
                report,
                &format!("tox run -e {env}"),
                "tox.ini",
                "Python tox validation env",
            );
        }
    }

    if noxfile.exists() {
        let contents = fs::read_to_string(&noxfile)?;
        report.inspect.push(
            "noxfile.py -> inspect nox sessions for lint/typecheck/test commands".to_string(),
        );
        for session in nox_sessions(&contents) {
            add_lint(
                report,
                &format!("nox -s {session}"),
                "noxfile.py",
                "Python nox validation session",
            );
        }
    }

    if any_exists(repo, &["uv.lock", "poetry.lock", "pdm.lock", "hatch.toml"]) {
        report.inspect.push("Python lock/tool files -> commands may need uv run, poetry run, pdm run, or hatch run wrappers".to_string());
    }

    Ok(())
}

fn tox_ini_envs(contents: &str) -> Vec<String> {
    let mut envs = Vec::new();
    for line in contents.lines() {
        let trimmed = line.trim();
        if let Some(env) = trimmed
            .strip_prefix("[testenv:")
            .and_then(|rest| rest.strip_suffix(']'))
        {
            if is_validation_name(env) {
                envs.push(env.to_string());
            }
        }
        if let Some(rest) = trimmed.strip_prefix("envlist") {
            if let Some((_, values)) = rest.split_once('=') {
                for env in values.split(',').map(str::trim) {
                    if is_validation_name(env) {
                        envs.push(env.to_string());
                    }
                }
            }
        }
    }
    dedup(&mut envs);
    envs
}

fn python_runner(repo: &Path, pyproject: &str) -> String {
    if repo.join("uv.lock").exists() || pyproject.contains("[tool.uv") {
        "uv run ".to_string()
    } else if repo.join("pdm.lock").exists() || pyproject.contains("[tool.pdm") {
        "pdm run ".to_string()
    } else if repo.join("poetry.lock").exists() || pyproject.contains("[tool.poetry") {
        "poetry run ".to_string()
    } else if repo.join("hatch.toml").exists() || pyproject.contains("[tool.hatch") {
        "hatch run ".to_string()
    } else {
        String::new()
    }
}

fn python_tox_like_envs(contents: &str) -> Vec<String> {
    let mut envs = Vec::new();
    for line in contents.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("[tool.tox.env.") {
            if let Some((env, _)) = rest.split_once(']') {
                if is_validation_name(env) {
                    envs.push(env.to_string());
                }
            }
        }
    }
    dedup(&mut envs);
    envs
}

fn nox_sessions(contents: &str) -> Vec<String> {
    let mut sessions = Vec::new();
    for line in contents.lines() {
        let trimmed = line.trim_start();
        if let Some(rest) = trimmed.strip_prefix("def ") {
            if let Some((name, _)) = rest.split_once('(') {
                if is_validation_name(name) {
                    sessions.push(name.to_string());
                }
            }
        }
    }
    dedup(&mut sessions);
    sessions
}

fn is_validation_name(name: &str) -> bool {
    matches!(
        name,
        "lint"
            | "linting"
            | "style"
            | "typing"
            | "typecheck"
            | "test"
            | "tests"
            | "py"
            | "black"
            | "flake8"
            | "isort"
            | "zizmor"
            | "pylint"
            | "pre-commit"
            | "docs"
    ) || name.starts_with("lint-")
        || name.starts_with("test-")
        || name.starts_with("typing-")
        || name.starts_with("py3")
}

fn makefile_targets(contents: &str) -> Vec<String> {
    let mut targets = Vec::new();
    for line in contents.lines() {
        if line.starts_with(char::is_whitespace) || line.starts_with('.') || line.starts_with('#') {
            continue;
        }
        let Some((target, rest)) = line.split_once(':') else {
            continue;
        };
        if rest.trim_start().starts_with('=') || target.contains('%') || target.contains('$') {
            continue;
        }
        for target in target.split_whitespace() {
            if matches!(
                target,
                "lint"
                    | "lint-python"
                    | "lint-py"
                    | "test"
                    | "tests"
                    | "typecheck"
                    | "type-check"
                    | "check"
                    | "ci"
            ) {
                targets.push(target.to_string());
            }
        }
    }
    dedup(&mut targets);
    targets
}

fn toml_bool_in_section(contents: &str, section: &str, key: &str) -> Option<bool> {
    let mut in_section = false;
    for line in contents.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            in_section = trimmed == format!("[{section}]");
            continue;
        }
        if in_section {
            if let Some((name, value)) = trimmed.split_once('=') {
                if name.trim() == key {
                    return match value.trim().split('#').next().unwrap_or("").trim() {
                        "true" => Some(true),
                        "false" => Some(false),
                        _ => None,
                    };
                }
            }
        }
    }
    None
}

fn prefer_aggregate_lints(report: &mut LintOnboardReport) {
    let has_aggregate = report.suggestions.iter().any(|lint| {
        lint.command == "scripts/check"
            || lint.command == "scripts/test"
            || lint.command.starts_with("tox run -e ")
            || lint.command.starts_with("nox -s ")
            || lint.command.starts_with("make ")
    });
    if !has_aggregate {
        return;
    }
    let primitive_suffixes = [
        "ruff check .",
        "ruff format --check .",
        "mypy",
        "pyright",
        "pytest",
    ];
    let mut removed = Vec::new();
    report.suggestions.retain(|lint| {
        let is_primitive = primitive_suffixes
            .iter()
            .any(|suffix| lint.command == *suffix || lint.command.ends_with(&format!(" {suffix}")));
        if is_primitive {
            removed.push(lint.command.clone());
        }
        !is_primitive
    });
    if !removed.is_empty() {
        dedup(&mut removed);
        report.inspect.push(format!(
            "Aggregate project commands found; demoted primitive Python tool commands to avoid redundant or mis-scoped lints: {}",
            removed.join(", ")
        ));
    }
}

fn parse_lint_selection(input: &str) -> Result<Vec<usize>> {
    let mut selected = Vec::new();
    for part in input.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        let index = part
            .parse::<usize>()
            .with_context(|| format!("invalid lint selection '{part}'"))?;
        if index == 0 {
            bail!("lint selections are 1-based; got 0");
        }
        selected.push(index);
    }
    if selected.is_empty() {
        bail!("empty lint selection");
    }
    selected.sort_unstable();
    selected.dedup();
    Ok(selected)
}

fn selected_lints(
    report: &LintOnboardReport,
    selection: Option<&[usize]>,
) -> Result<Vec<LintSuggestion>> {
    match selection {
        None => Ok(report.suggestions.clone()),
        Some(selection) => {
            let mut out = Vec::new();
            for index in selection {
                let Some(lint) = report.suggestions.get(index - 1) else {
                    bail!(
                        "lint selection {index} is out of range; run `jj lint onboard --print` to see numbered suggestions"
                    );
                };
                out.push(lint.clone());
            }
            Ok(out)
        }
    }
}

fn preview_lint_config(report: &LintOnboardReport, selection: Option<&[usize]>) -> Result<()> {
    let lints = selected_lints(report, selection)?;
    if lints.is_empty() {
        bail!("no suggested commands to preview. Inspect workflow hints first.");
    }
    print!("{}", lint_config_toml(&lints)?);
    Ok(())
}

fn lint_config_toml(lints: &[LintSuggestion]) -> Result<String> {
    let mut contents =
        String::from("# Generated by jj lint onboard. Review before committing.\nlints = [\n");
    for lint in lints {
        contents.push_str(&format!(
            "  {{ name = {}, command = {} }},\n",
            serde_json::to_string(&infer_lint_name(&lint.command))?,
            serde_json::to_string(&lint.command)?
        ));
    }
    contents.push_str("]\n");
    Ok(contents)
}

fn is_check_only_format_script(script: &str) -> bool {
    let lower = script.to_ascii_lowercase();
    (lower.contains("--check")
        || lower.contains("--dry-run")
        || lower.contains(" --list-different")
        || lower.contains("biome check")
        || lower.contains("format:check")
        || lower.contains("format-check"))
        && !lower.contains("--write")
        && !lower.contains(" --fix")
        && !lower.contains("--fix=")
}

fn is_safe_package_check_script(script: &str) -> bool {
    let lower = script.to_ascii_lowercase();
    let check_like = lower.contains("biome check")
        || lower.contains("prettier --check")
        || lower.contains("eslint") && !lower.contains("--fix")
        || lower.contains("tsc --noemit");
    let mutating = lower.contains("--write")
        || lower.contains(" --fix")
        || lower.contains("--fix=")
        || lower.contains(" dev")
        || lower.contains(" start")
        || lower.contains(" serve")
        || lower.contains(" deploy");
    check_like && !mutating
}

fn infer_lint_name(command: &str) -> String {
    let tokens = shell_words(command);
    if tokens.is_empty() {
        return command.trim().to_string();
    }

    if tokens.iter().any(|token| token == "shellcheck") {
        return "shellcheck".to_string();
    }

    let tokens = strip_env_assignments(&tokens);
    if tokens.is_empty() {
        return command.trim().to_string();
    }

    match tokens[0].as_str() {
        "uv" | "poetry" | "pdm" | "hatch" if tokens.get(1).map(String::as_str) == Some("run") => {
            infer_wrapped_tool(&tokens[2..]).unwrap_or_else(|| format_tool_args(&tokens, 2))
        }
        "cargo" => infer_cargo_name(&tokens),
        "npm" => infer_npm_name(&tokens),
        "pnpm" | "yarn" | "bun" => infer_package_manager_name(&tokens),
        "npx" => infer_wrapped_tool(&tokens[1..]).unwrap_or_else(|| format_tool_args(&tokens, 2)),
        "tox" if tokens.get(1).map(String::as_str) == Some("run") => env_flag_name("tox", &tokens),
        "nox" => env_flag_name("nox", &tokens),
        "make" | "just" => format_tool_args(&tokens, 2),
        "nix" if tokens.get(1).map(String::as_str) == Some("flake") => format_tool_args(&tokens, 3),
        "docker" if tokens.get(1).map(String::as_str) == Some("compose") => {
            infer_docker_compose_name(&tokens)
        }
        _ => infer_wrapped_tool(tokens).unwrap_or_else(|| format_tool_args(tokens, 2)),
    }
}

fn infer_cargo_name(tokens: &[String]) -> String {
    if tokens.get(1).map(String::as_str) == Some("nextest") {
        return format_tool_args(tokens, 3);
    }
    format_tool_args(tokens, 2)
}

fn infer_npm_name(tokens: &[String]) -> String {
    match tokens.get(1).map(String::as_str) {
        Some("run") | Some("run-script") => tokens
            .get(2)
            .map(|script| format!("npm {script}"))
            .unwrap_or_else(|| "npm run".to_string()),
        Some("test") | Some("t") => "npm test".to_string(),
        Some("exec") => infer_wrapped_tool(&tokens[2..]).unwrap_or_else(|| "npm exec".to_string()),
        _ => format_tool_args(tokens, 2),
    }
}

fn infer_package_manager_name(tokens: &[String]) -> String {
    let pm = tokens[0].as_str();
    match tokens.get(1).map(String::as_str) {
        Some("run") => tokens
            .get(2)
            .map(|script| format!("{pm} {script}"))
            .unwrap_or_else(|| format!("{pm} run")),
        Some("exec") | Some("dlx") => {
            infer_wrapped_tool(&tokens[2..]).unwrap_or_else(|| format!("{pm} exec"))
        }
        Some(script) if !script.starts_with('-') => format!("{pm} {script}"),
        _ => pm.to_string(),
    }
}

fn infer_wrapped_tool(tokens: &[String]) -> Option<String> {
    if tokens.is_empty() {
        return None;
    }
    let tokens = strip_leading_flags(tokens);
    if tokens.is_empty() {
        return None;
    }
    if tokens[0] == "python" || tokens[0] == "python3" {
        if tokens.get(1).map(String::as_str) == Some("-m") {
            return tokens
                .get(2)
                .map(|module| python_module_name(module, &tokens[3..]));
        }
    }
    Some(tool_specific_name(tokens))
}

fn tool_specific_name(tokens: &[String]) -> String {
    match tokens[0].as_str() {
        "ruff" => format_tool_args(tokens, 3),
        "eslint" | "prettier" | "biome" | "mypy" | "pyright" | "pytest" | "vitest" | "jest"
        | "tsc" | "zizmor" | "black" | "isort" | "flake8" | "pylint" | "alejandra" | "statix"
        | "shellcheck" => format_tool_args(tokens, 2),
        _ => format_tool_args(tokens, 2),
    }
}

fn python_module_name(module: &str, rest: &[String]) -> String {
    let mut tokens = vec![module.to_string()];
    tokens.extend(rest.iter().cloned());
    tool_specific_name(&tokens)
}

fn env_flag_name(prefix: &str, tokens: &[String]) -> String {
    if let Some(index) = tokens
        .iter()
        .position(|token| token == "-e" || token == "-s")
    {
        if let Some(env) = tokens.get(index + 1) {
            return format!("{prefix} {env}");
        }
    }
    format_tool_args(tokens, 2)
}

fn infer_docker_compose_name(tokens: &[String]) -> String {
    if let Some(index) = tokens
        .iter()
        .position(|token| matches!(token.as_str(), "run" | "exec"))
    {
        let mut idx = index + 1;
        while tokens
            .get(idx)
            .map(|token| token.starts_with('-'))
            .unwrap_or(false)
        {
            idx += 1;
        }
        if let Some(service) = tokens.get(idx) {
            if let Some(tool) = infer_wrapped_tool(&tokens[idx + 1..]) {
                return format!("compose {service} {tool}");
            }
            return format!("compose {service}");
        }
    }
    format_tool_args(tokens, 3)
}

fn strip_env_assignments(tokens: &[String]) -> &[String] {
    let mut index = 0;
    while tokens
        .get(index)
        .map(|token| token.contains('=') && !token.starts_with('-'))
        .unwrap_or(false)
    {
        index += 1;
    }
    &tokens[index..]
}

fn strip_leading_flags(tokens: &[String]) -> &[String] {
    let mut index = 0;
    while tokens
        .get(index)
        .map(|token| token.starts_with('-'))
        .unwrap_or(false)
    {
        index += 1;
    }
    &tokens[index..]
}

fn format_tool_args(tokens: &[String], max_tokens: usize) -> String {
    tokens
        .iter()
        .filter(|token| !token.starts_with('-') && *token != ".")
        .take(max_tokens)
        .cloned()
        .collect::<Vec<_>>()
        .join(" ")
}

fn shell_words(command: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;
    let mut escaped = false;
    for ch in command.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        match ch {
            '\\' if quote != Some('\'') => escaped = true,
            '\'' | '"' if quote == Some(ch) => quote = None,
            '\'' | '"' if quote.is_none() => quote = Some(ch),
            ch if ch.is_whitespace() && quote.is_none() => {
                if !current.is_empty() {
                    words.push(current.clone());
                    current.clear();
                }
            }
            _ => current.push(ch),
        }
    }
    if !current.is_empty() {
        words.push(current);
    }
    words
}

fn add_lint(report: &mut LintOnboardReport, command: &str, source: &str, reason: &str) {
    if report
        .suggestions
        .iter()
        .any(|lint| lint.command == command)
    {
        return;
    }
    report.suggestions.push(LintSuggestion {
        command: command.to_string(),
        source: source.to_string(),
        reason: reason.to_string(),
    });
}

fn any_exists(repo: &Path, paths: &[&str]) -> bool {
    paths.iter().any(|path| repo.join(path).exists())
}

fn is_executable_file(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        path.metadata()
            .map(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

fn add_inspect_if_exists(repo: &Path, report: &mut LintOnboardReport, path: &str, message: &str) {
    if repo.join(path).exists() {
        report.inspect.push(message.to_string());
    }
}

fn print_lint_onboard_report(report: &LintOnboardReport) {
    println!("jj lint onboarding\n");
    if report.suggestions.is_empty() {
        println!("No high-confidence lint commands found automatically.\n");
    } else {
        println!("Suggested lints to include:");
        for (index, lint) in report.suggestions.iter().enumerate() {
            println!(
                "  {}. {}\n      name: {}\n      source: {}\n      reason: {}",
                index + 1,
                lint.command,
                infer_lint_name(&lint.command),
                lint.source,
                lint.reason
            );
        }
        println!();
    }
    if !report.inspect.is_empty() {
        println!("Inspect these project workflow sources:");
        for item in &report.inspect {
            println!("  - {item}");
        }
        println!();
    }
    println!("What to look for:\n  - package scripts: lint, typecheck, test, check, build\n  - Makefile targets: make lint, make test, make check, make ci\n  - Just recipes: just --list, just lint, just test, just check\n  - Docker Compose commands: docker compose run --rm test/app/web ...\n  - docs/CI mentions: test, lint, typecheck, validate, before pushing\n  - pre-commit/husky/lint-staged hooks to replace with all-files equivalents\n");
    println!("Review before writing:\n  - Avoid watch/dev/server/deploy commands.\n  - Avoid staged-file-only hooks; jj has no staging area.\n  - Check whether tests require secrets, network, containers, or services.\n  - Decide whether config should be tracked (.jj-lint.toml) or local (.jj/repo/config.toml).\n");
    println!("Next:\n  jj lint onboard --preview --select=1,3 # preview selected .jj-lint.toml\n  jj lint onboard --write                # write all suggestions to tracked .jj-lint.toml\n  jj lint onboard --write --select=1,3   # write selected numbered suggestions\n  jj lint onboard --local --select=2     # set selected lints in local dotfiles.push-lints\n  jj lint onboard --json                 # structured discovery output");
}

fn lint_onboard_json(report: &LintOnboardReport) -> serde_json::Value {
    json!({
        "suggested": report.suggestions.iter().map(|lint| json!({"name": infer_lint_name(&lint.command), "command": lint.command, "source": lint.source, "reason": lint.reason})).collect::<Vec<_>>(),
        "inspect": report.inspect,
        "hints": [
            "Inspect Makefile/justfile/Docker Compose/docs/CI for project-specific checks",
            "Prefer deterministic all-files commands for jj lint",
            "Avoid watch/dev/server/deploy commands",
            "Use local config for personal/worktree-only setup"
        ]
    })
}

fn write_tracked_lint_config(
    repo: &Path,
    report: &LintOnboardReport,
    selection: Option<&[usize]>,
) -> Result<()> {
    let lints = selected_lints(report, selection)?;
    if lints.is_empty() {
        bail!("no suggested commands to write. Inspect workflow hints first.");
    }
    let path = repo.join(".jj-lint.toml");
    if path.exists() {
        bail!("{} already exists; refusing to overwrite", path.display());
    }
    let contents = lint_config_toml(&lints)?;
    fs::write(&path, contents)?;
    println!("Wrote {}", path.display());
    Ok(())
}

fn write_local_lint_config(report: &LintOnboardReport, selection: Option<&[usize]>) -> Result<()> {
    let lints = selected_lints(report, selection)?;
    if lints.is_empty() {
        bail!("no suggested commands to write. Inspect workflow hints first.");
    }
    let commands = report
        .suggestions
        .iter()
        .filter(|lint| {
            lints
                .iter()
                .any(|selected| selected.command == lint.command)
        })
        .map(|lint| lint.command.clone())
        .collect::<Vec<_>>();
    run_jj_status_os(vec![
        "config".into(),
        "set".into(),
        "--repo".into(),
        "dotfiles.push-lints".into(),
        serde_json::to_string(&commands)?.into(),
    ])?;
    println!("Set local repo config dotfiles.push-lints");
    Ok(())
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

fn resolve_tag_remote(explicit_remote: Option<&str>) -> Result<String> {
    if let Some(remote) = explicit_remote {
        return Ok(remote.to_string());
    }

    let mut remotes = git_remotes()?;
    dedup(&mut remotes);
    match remotes.as_slice() {
        [] => bail!("no Git remotes configured"),
        [remote] => Ok(remote.clone()),
        _ if remotes.iter().any(|remote| remote == "origin") => Ok("origin".to_string()),
        _ => pick_option("Tag push remote", &remotes, "Re-run with --remote <name>."),
    }
}

fn validate_release_tag(tag: &str) -> Result<()> {
    if tag.is_empty() {
        bail!("tag cannot be empty");
    }
    let Some(rest) = tag.strip_prefix('v') else {
        bail!("tag must look like vX.Y.Z; re-run with --allow-non-semver to override")
    };
    let parts: Vec<&str> = rest.split('.').collect();
    if parts.len() != 3
        || parts
            .iter()
            .any(|part| part.is_empty() || !part.chars().all(|ch| ch.is_ascii_digit()))
    {
        bail!("tag must look like vX.Y.Z; re-run with --allow-non-semver to override")
    }
    Ok(())
}

fn local_tag_target(tag: &str) -> Result<Option<String>> {
    let pattern = format!("exact:{tag}");
    let output = run_jj_capture([
        "tag",
        "list",
        pattern.as_str(),
        "--color=never",
        "-T",
        "if(!self.remote(), coalesce(self.normal_target().commit_id(), \"\") ++ \"\\n\", \"\")",
    ])?;

    Ok(output
        .stdout
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(std::string::ToString::to_string))
}

fn local_tags_at_revset(revset: &str) -> Result<Vec<String>> {
    let output = run_jj_capture([
        "tag",
        "list",
        "-r",
        revset,
        "--color=never",
        "-T",
        "if(!self.remote(), self.name() ++ \"\\n\", \"\")",
    ])?;
    let mut tags: Vec<String> = output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(std::string::ToString::to_string)
        .collect();
    dedup(&mut tags);
    Ok(tags)
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct TagRef {
    object_id: String,
    peeled_target: Option<String>,
}

impl TagRef {
    fn target(&self) -> &str {
        self.peeled_target.as_deref().unwrap_or(&self.object_id)
    }

    fn is_annotated(&self) -> bool {
        self.peeled_target.is_some()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ResolvedTagSigning {
    sign: bool,
    key: Option<String>,
    source: &'static str,
}

impl ResolvedTagSigning {
    fn description(&self) -> String {
        if self.sign {
            match self.key.as_deref() {
                Some(key) => format!("yes ({}, key {key})", self.source),
                None => format!("yes ({}, default GPG key)", self.source),
            }
        } else {
            format!("no ({})", self.source)
        }
    }
}

fn jj_git_root() -> Result<PathBuf> {
    let output = run_jj_capture(["git", "root"])?;
    Ok(PathBuf::from(output.stdout.trim()))
}

fn git_in_jj_repo() -> Result<Command> {
    let git_dir = jj_git_root()?;
    let mut command = Command::new("git");
    command.arg("--git-dir").arg(git_dir);
    Ok(command)
}

fn git_capture_in_jj_repo(args: &[&str]) -> Result<std::process::Output> {
    let mut command = git_in_jj_repo()?;
    command.args(args);
    command
        .output()
        .with_context(|| format!("failed to execute git {}", args.join(" ")))
}

fn git_config_string(key: &str) -> Result<Option<String>> {
    let output = git_capture_in_jj_repo(&["config", "--get", key])?;
    if !output.status.success() {
        return Ok(None);
    }
    let value = String::from_utf8(output.stdout)
        .context("failed to decode git config stdout")?
        .trim()
        .trim_matches('"')
        .to_string();
    Ok((!value.is_empty()).then_some(value))
}

fn jj_tag_signing_key() -> Result<Option<String>> {
    for key in ["signing.key", "user.signing-key"] {
        if let Some(value) = jj_config_string(key)? {
            return Ok(Some(value));
        }
    }
    git_config_string("user.signingkey")
}

fn jj_gpg_signing_enabled() -> Result<bool> {
    let backend = jj_config_string("signing.backend")?;
    if backend.as_deref() != Some("gpg") {
        return Ok(false);
    }

    let behavior = jj_config_string("signing.behavior")?;
    Ok(!matches!(
        behavior.as_deref(),
        Some("drop" | "never" | "none" | "disabled")
    ))
}

fn resolve_tag_signing(requested: TagSigning) -> Result<ResolvedTagSigning> {
    let key = jj_tag_signing_key()?;
    match requested {
        TagSigning::NoSign => Ok(ResolvedTagSigning {
            sign: false,
            key: None,
            source: "--no-sign",
        }),
        TagSigning::Sign => Ok(ResolvedTagSigning {
            sign: true,
            key,
            source: "--sign",
        }),
        TagSigning::Auto if jj_gpg_signing_enabled()? => Ok(ResolvedTagSigning {
            sign: true,
            key,
            source: "jj signing.backend=gpg",
        }),
        TagSigning::Auto => Ok(ResolvedTagSigning {
            sign: false,
            key: None,
            source: "jj gpg signing not configured",
        }),
    }
}

fn local_git_tag_ref(tag: &str) -> Result<Option<TagRef>> {
    let refname = format!("refs/tags/{tag}");
    let output = git_capture_in_jj_repo(&["rev-parse", "--verify", refname.as_str()])?;
    if !output.status.success() {
        return Ok(None);
    }
    let object_id = String::from_utf8(output.stdout)
        .context("failed to decode git rev-parse stdout")?
        .lines()
        .next()
        .unwrap_or_default()
        .trim()
        .to_string();
    if object_id.is_empty() {
        return Ok(None);
    }

    let object_type_output = git_capture_in_jj_repo(&["cat-file", "-t", object_id.as_str()])?;
    if !object_type_output.status.success() {
        let stderr = String::from_utf8_lossy(&object_type_output.stderr);
        bail!("git cat-file -t {object_id} failed: {}", stderr.trim())
    }
    let object_type = String::from_utf8(object_type_output.stdout)
        .context("failed to decode git cat-file stdout")?;
    let peeled_target = if object_type.trim() == "tag" {
        let peel = format!("{refname}^{{}}");
        let peel_output = git_capture_in_jj_repo(&["rev-parse", "--verify", peel.as_str()])?;
        if !peel_output.status.success() {
            let stderr = String::from_utf8_lossy(&peel_output.stderr);
            bail!("git rev-parse --verify {peel} failed: {}", stderr.trim())
        }
        Some(
            String::from_utf8(peel_output.stdout)
                .context("failed to decode git rev-parse peeled stdout")?
                .lines()
                .next()
                .unwrap_or_default()
                .trim()
                .to_string(),
        )
    } else {
        None
    };

    Ok(Some(TagRef {
        object_id,
        peeled_target,
    }))
}

fn remote_tag_ref(remote: &str, tag: &str) -> Result<Option<TagRef>> {
    let refname = format!("refs/tags/{tag}");
    let peel_refname = format!("{refname}^{{}}");
    let mut command = git_in_jj_repo()?;
    let output = command
        .args([
            "ls-remote",
            "--exit-code",
            "--tags",
            remote,
            refname.as_str(),
            peel_refname.as_str(),
        ])
        .output()
        .with_context(|| format!("failed to execute git ls-remote for {remote}/{tag}"))?;

    if !output.status.success() {
        if output.status.code() == Some(2) {
            return Ok(None);
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!(
            "git ls-remote --tags {remote} {refname} failed: {}",
            stderr.trim()
        )
    }

    let stdout =
        String::from_utf8(output.stdout).context("failed to decode git ls-remote stdout")?;
    let mut object_id = None;
    let mut peeled_target = None;
    for line in stdout.lines() {
        let mut fields = line.split_whitespace();
        let Some(id) = fields.next() else {
            continue;
        };
        let Some(remote_ref) = fields.next() else {
            continue;
        };
        if remote_ref == refname {
            object_id = Some(id.to_string());
        } else if remote_ref == peel_refname {
            peeled_target = Some(id.to_string());
        }
    }

    Ok(object_id.map(|object_id| TagRef {
        object_id,
        peeled_target,
    }))
}

fn remote_tag_target(remote: &str, tag: &str) -> Result<Option<String>> {
    Ok(remote_tag_ref(remote, tag)?.map(|tag_ref| tag_ref.target().to_string()))
}

fn default_tag_message(tag: &str) -> String {
    let repo_name = jj_root()
        .ok()
        .and_then(|root| {
            root.file_name()
                .map(|name| name.to_string_lossy().to_string())
        })
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "release".to_string());
    format!("{repo_name} {tag}")
}

fn create_annotated_git_tag(
    tag: &str,
    target_id: &str,
    message: &str,
    force: bool,
    signing: &ResolvedTagSigning,
) -> Result<()> {
    let mut command = git_in_jj_repo()?;
    if !signing.sign {
        command.arg("-c").arg("tag.gpgSign=false");
    }
    if let Some(name) = jj_config_string("user.name")? {
        command.arg("-c").arg(format!("user.name={name}"));
    }
    if let Some(email) = jj_config_string("user.email")? {
        command.arg("-c").arg(format!("user.email={email}"));
    }
    command.arg("tag");
    if force {
        command.arg("-f");
    }
    if signing.sign {
        command.arg("-s");
        if let Some(key) = signing.key.as_deref() {
            command.args(["-u", key]);
        }
    } else {
        command.arg("-a");
    }
    command.args(["-m", message, tag, target_id]);
    let output = command
        .output()
        .with_context(|| format!("failed to execute git tag for {tag}"))?;
    let status = output.status;
    if status.success() {
        Ok(())
    } else if signing.sign {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!(
            "failed to create signed tag {tag}{}\n\n{}\n\nChecks:\n  gpg --list-secret-keys{}\n  echo test | gpg --clearsign\n  gpg-agent-recover\n\nOr explicitly create an unsigned annotated tag:\n  jj tag-push {tag} --revision {target_id} --no-sign",
            signing
                .key
                .as_deref()
                .map(|key| format!(" with GPG key {key}"))
                .unwrap_or_default(),
            stderr.trim(),
            signing
                .key
                .as_deref()
                .map(|key| format!(" {key}"))
                .unwrap_or_default()
        )
    } else {
        bail!("git tag -a {tag} failed with status {status}")
    }
}

fn verify_signed_git_tag(tag: &str) -> Result<()> {
    let refname = format!("refs/tags/{tag}");
    let output = git_in_jj_repo()?
        .args(["verify-tag", refname.as_str()])
        .output()
        .with_context(|| format!("failed to execute git verify-tag {refname}"))?;
    if output.status.success() {
        Ok(())
    } else {
        bail!(
            "signed tag {tag} was created but git verify-tag failed:\n{}",
            String::from_utf8_lossy(&output.stderr).trim()
        )
    }
}

fn git_push_tag(remote: &str, tag: &str) -> Result<()> {
    let refspec = format!("refs/tags/{tag}");
    let status = git_in_jj_repo()?
        .args(["push", remote, refspec.as_str()])
        .status()
        .with_context(|| format!("failed to execute git push {remote} {refspec}"))?;
    if status.success() {
        Ok(())
    } else {
        bail!("git push {remote} {refspec} failed with status {status}")
    }
}

fn teach_unpushed_tags_at(revset: &str, remote: &str) -> Result<()> {
    let tags = local_tags_at_revset(revset)?;
    for tag in tags {
        if remote_tag_target(remote, &tag)?.is_none() {
            eprintln!(
                "note: local tag {tag} points at the shipped commit but is not on {remote}\npublish it with:\n  jj tag-push {tag} --revision {} --remote {remote}",
                short_commit(revset)
            );
        }
    }
    Ok(())
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

fn commit_description_first_line(revset: &str) -> Result<String> {
    let output = run_jj_capture([
        "log",
        "-r",
        revset,
        "-n",
        "1",
        "--no-graph",
        "--color=never",
        "-T",
        "description.first_line()",
    ])?;
    Ok(output.stdout.trim().to_string())
}

fn short_commit(commit_id: &str) -> &str {
    if commit_id.len() <= 12 {
        commit_id
    } else {
        &commit_id[..12]
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

fn commit_description_is_empty(revset: &str) -> Result<bool> {
    let output = run_jj_capture_allow_failure([
        "log",
        "-r",
        revset,
        "-n",
        "1",
        "--no-graph",
        "--color=never",
        "-T",
        "description",
    ])?;

    if !output.status.success() {
        bail!(format_jj_error(
            &[
                "log",
                "-r",
                revset,
                "-n",
                "1",
                "--no-graph",
                "--color=never",
                "-T",
                "description",
            ],
            &output
        ))
    }

    Ok(output.stdout.trim().is_empty())
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
        "Usage:\n  jj ship [-b|--bookmark <bookmark>] [--remote <remote>] [--tag <tag>] [--sign|--no-sign] [-- <jj git push args...>]\n\nRuns jj lint, then ships the parent of the working copy. Refuses empty targets and will not fall back to integration bookmarks unless you choose one explicitly with --bookmark. With --tag, creates an annotated Git tag for the exact shipped commit and publishes that tag to the remote. Tags are signed by default when jj GPG signing is configured; use --no-sign for an unsigned annotated tag."
    );
}

fn print_tag_push_usage() {
    eprintln!(
        "Usage:\n  jj tag-push <tag> [--revision <rev>] [--remote <remote>] [-m|--message <message>] [--sign|--no-sign] [--allow-dirty] [--allow-move] [--allow-non-semver] [--dry-run] [--json]\n\nCreates or reuses an annotated Git tag in the jj-backed Git store, imports it into jj, pushes the exact refs/tags/<tag> ref, and verifies that the remote tag is annotated and peels to the requested commit. Tags are signed by default when jj GPG signing is configured; use --no-sign for an unsigned annotated tag. If --revision is omitted with a clean working copy, @- is used. Tags must look like vX.Y.Z unless --allow-non-semver is passed."
    );
}

fn print_lint_usage() {
    eprintln!(
        "Usage:\n  jj lint\n  jj lint onboard [--print|--json|--preview|--write|--local] [--select=1,3]\n\nRuns configured lints from .jj-lint.toml or dotfiles.push-lints. .jj-lint.toml entries may be strings or {{ name, command }} tables; unnamed entries get inferred labels. Use `jj lint onboard --print` to discover candidate commands when none are configured. Use --select with --preview/--write/--local to preview or save only chosen numbered suggestions."
    );
}

fn print_lint_onboard_usage() {
    eprintln!(
        "Usage:\n  jj lint onboard [--print|--json|--preview|--write|--local] [--select=1,3]\n\nDiscovers package scripts, Python pyproject/tox/nox, Makefile/justfile/Docker Compose/docs/CI hooks, and pre-commit replacement hints. Default is --print. Suggestions are numbered; pass --select=1,3 with --preview, --write, or --local to preview or persist only those commands."
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

fn run_jj_capture_in_allow_failure<const N: usize>(
    repo: &Path,
    args: [&str; N],
) -> Result<JjOutput> {
    let output = Command::new("jj")
        .current_dir(repo)
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
    conflicted_changes_in("all()")
}

fn conflicted_changes_in(revset: &str) -> Result<Vec<String>> {
    let conflict_revset = format!("conflicts() & ({revset})");
    let output = run_jj_capture([
        "log",
        "-r",
        conflict_revset.as_str(),
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

fn print_tag_push_json(
    tag: &str,
    revision: &str,
    commit: &str,
    remote: &str,
    pushed: bool,
    verified: bool,
) {
    println!(
        "{{\"action\":\"tag-push\",\"tag\":\"{}\",\"revision\":\"{}\",\"commit\":\"{}\",\"remote\":\"{}\",\"pushed\":{},\"verified\":{}}}",
        json_escape(tag),
        json_escape(revision),
        json_escape(commit),
        json_escape(remote),
        pushed,
        verified
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
        choose_ship_bookmark, choose_sync_base, configured_lints, cr_base_ref, fetch_remote_choice,
        first_unsupported_pr_flag, infer_lint_name, infer_remote_integration_bookmark_from,
        is_check_only_format_script, is_integration_bookmark, is_safe_package_check_script,
        is_validation_name, lint_config_toml, lint_display_name, lint_onboard_json,
        lint_onboard_report, makefile_targets, parse_checks_json, parse_common_args,
        parse_config_string_array, parse_duration_arg, parse_github_remote_url,
        parse_lint_selection, parse_lints_toml, parse_pr_hygiene_args, parse_pr_hygiene_graphql,
        parse_review_state_json, parse_tag_push_args, parse_toml_string_array, parse_ws_add_args,
        parse_ws_forget_args, parse_ws_path_args, parse_ws_prune_args, python_runner,
        render_bookmark_template, resolve_pr_base, review_effort, run_lint, run_lint_onboard,
        run_ship, run_sync, run_ws, selected_lints, ship_plan, short_description_from_title,
        source_venv_python_usable, stale_workspace_dirs, sync_base_candidates, tag_push,
        validate_body_source, validate_pr_watch_args, validate_release_tag, validate_ticket,
        validate_ws_name, workspace_context_for_repo, workspace_has_unpublished_work,
        write_tracked_lint_config, Cli, CliCommand, FetchChoice, LintCommand, LintOnboardReport,
        LintSuggestion, ParsedArgs, PrArgs, ProjectGroup, ShipPlan, TagCommand, TagPushArgs,
        TagSigning, WsAddArgs, WsConfig, WsForgetArgs, WsPathArgs, WsPruneArgs,
    };
    use clap::Parser;
    use std::env;
    use std::ffi::OsString;
    use std::fs;
    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};
    use std::process::Command;
    use std::sync::Mutex;
    use std::time::Duration;

    static INTEGRATION_LOCK: Mutex<()> = Mutex::new(());

    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| (*value).to_string()).collect()
    }

    fn lint_commands(lints: &[super::LintCommand]) -> Vec<String> {
        lints.iter().map(|lint| lint.command.clone()).collect()
    }

    fn assert_remote_annotated_tag(origin: &Path, tag: &str, expected_target: &str) {
        let refname = format!("refs/tags/{tag}");
        let peel_refname = format!("{refname}^{{}}");
        let output = Command::new("git")
            .arg("ls-remote")
            .arg("--exit-code")
            .arg("--tags")
            .arg(origin)
            .arg(&refname)
            .arg(&peel_refname)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "tag missing\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );

        let stdout = String::from_utf8(output.stdout).unwrap();
        let mut tag_object = None;
        let mut peeled_target = None;
        for line in stdout.lines() {
            let mut fields = line.split_whitespace();
            let object_id = fields.next().unwrap_or_default();
            let remote_ref = fields.next().unwrap_or_default();
            if remote_ref == refname {
                tag_object = Some(object_id.to_string());
            } else if remote_ref == peel_refname {
                peeled_target = Some(object_id.to_string());
            }
        }

        let tag_object = tag_object.unwrap_or_else(|| panic!("missing tag object for {tag}"));
        let peeled_target = peeled_target.unwrap_or_else(|| panic!("missing peeled ref for {tag}"));
        assert_eq!(peeled_target, expected_target);
        assert_ne!(
            tag_object, expected_target,
            "{tag} should be annotated, not lightweight"
        );
    }

    #[test]
    fn github_remote_parsing_accepts_common_github_urls() {
        for url in [
            "git@github.com:sureapp/surecraft-core.git",
            "git@github.com:sureapp/surecraft-core",
            "ssh://git@github.com/sureapp/surecraft-core.git",
            "https://github.com/sureapp/surecraft-core.git",
            "https://github.com/sureapp/surecraft-core",
        ] {
            assert_eq!(
                parse_github_remote_url(url),
                Some(("sureapp".to_string(), "surecraft-core".to_string()))
            );
        }
        assert_eq!(
            parse_github_remote_url("git@example.com:sureapp/repo"),
            None
        );
    }

    #[test]
    fn pr_bookmark_template_renders_safe_bookmark() {
        let bookmark = render_bookmark_template(
            "{whoami}/{ticket-number}/{short-description}",
            "EPD-8719",
            "Stop Deterministic Scheduled MTA Retries!",
        )
        .unwrap();
        let suffix = "/EPD-8719/stop-deterministic-scheduled-mta-retries";
        assert!(bookmark.ends_with(suffix), "bookmark was {bookmark}");
    }

    #[test]
    fn pr_short_description_drops_conventional_prefix_and_ticket() {
        assert_eq!(
            short_description_from_title(
                "fix(policy): stop deterministic scheduled MTA retries [EPD-8719]"
            ),
            "stop-deterministic-scheduled-mta-retries"
        );
    }

    #[test]
    fn pr_explicit_base_uses_selected_sync_remote() {
        let base = resolve_pr_base(Some("develop"), Some("upstream")).unwrap();
        assert_eq!(base.pr_base, "develop");
        assert_eq!(base.sync_base, "develop@upstream");

        let remote_base = resolve_pr_base(Some("main@origin"), Some("upstream")).unwrap();
        assert_eq!(remote_base.pr_base, "main");
        assert_eq!(remote_base.sync_base, "main@origin");

        assert!(resolve_pr_base(Some("trunk()"), Some("origin")).is_err());
    }

    #[test]
    fn pr_cr_base_uses_git_remote_ref_for_jj_remote_bookmark() {
        assert_eq!(cr_base_ref("main@origin"), "origin/main");
        assert_eq!(
            cr_base_ref("release/2026.06@upstream"),
            "upstream/release/2026.06"
        );
        assert_eq!(cr_base_ref("origin/main"), "origin/main");
        assert_eq!(cr_base_ref("main"), "main");
    }

    #[test]
    fn pr_body_source_validation_rejects_ambiguous_inputs() {
        let both = PrArgs {
            body: Some("body".to_string()),
            body_file: Some("/tmp/body.md".to_string()),
            ..PrArgs::default()
        };
        assert!(validate_body_source(&both, true).is_err());

        let missing = PrArgs::default();
        assert!(validate_body_source(&missing, true).is_err());
        assert!(validate_body_source(&missing, false).is_ok());
    }

    #[test]
    fn pr_ticket_validation_is_conservative() {
        for ticket in ["EPD-8719", "ABC_123", "A.1"] {
            validate_ticket(ticket).unwrap();
        }
        for ticket in ["", " EPD-1", "EPD 1", "EPD/1", "EPD@1"] {
            assert!(
                validate_ticket(ticket).is_err(),
                "ticket {ticket:?} should fail"
            );
        }
    }

    #[test]
    fn pr_watch_parses_duration_suffixes() {
        assert_eq!(parse_duration_arg("30").unwrap().as_secs(), 30);
        assert_eq!(parse_duration_arg("60s").unwrap().as_secs(), 60);
        assert_eq!(parse_duration_arg("30m").unwrap().as_secs(), 1800);
        assert_eq!(parse_duration_arg("1h").unwrap().as_secs(), 3600);
        assert!(parse_duration_arg("0").is_err());
        assert!(parse_duration_arg("1d").is_err());
    }

    #[test]
    fn pr_watch_validation_rejects_ambiguous_or_ignored_flags() {
        let ambiguous = PrArgs {
            head: Some("feature".to_string()),
            pr: Some("123".to_string()),
            once: true,
            ..PrArgs::default()
        };
        assert!(validate_pr_watch_args(&ambiguous).is_err());

        let ignored = PrArgs {
            title: Some("unused".to_string()),
            once: true,
            ..PrArgs::default()
        };
        assert!(validate_pr_watch_args(&ignored).is_err());

        let tight_loop = PrArgs {
            interval: Some(Duration::from_secs(1)),
            ..PrArgs::default()
        };
        assert!(validate_pr_watch_args(&tight_loop).is_err());

        assert_eq!(
            first_unsupported_pr_flag(&ignored, &["repo", "remote", "head", "pr"]),
            Some("title")
        );
    }

    #[test]
    fn pr_watch_parses_checks_json() {
        let checks = parse_checks_json(
            r#"[
              {"name":"lint","bucket":"pass","state":"SUCCESS","link":"https://example.test/lint"},
              {"name":"tests","bucket":"fail","state":"FAILURE","link":"https://example.test/tests"}
            ]"#,
        )
        .unwrap();
        assert_eq!(checks.len(), 2);
        assert_eq!(checks[1].name, "tests");
        assert_eq!(checks[1].bucket, "fail");
    }

    #[test]
    fn pr_watch_parses_unresolved_non_outdated_review_threads() {
        let page = parse_review_state_json(
            r#"{
              "data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": [
                {"isResolved": false, "isOutdated": false, "comments": {"nodes": [
                  {"author": {"login": "coderabbitai"}, "bodyText": "First line\nMore detail", "path": "src/main.rs", "line": 42, "url": "https://example.test/comment"}
                ]}},
                {"isResolved": true, "isOutdated": false, "comments": {"nodes": [
                  {"author": {"login": "human"}, "bodyText": "resolved", "path": "src/lib.rs", "line": 1, "url": "https://example.test/resolved"}
                ]}}
              ]}}}}
            }"#,
        )
        .unwrap();
        assert_eq!(page.review_decision, "REVIEW_REQUIRED");
        let comments = page.comments;
        assert_eq!(comments.len(), 1);
        assert_eq!(comments[0].author, "coderabbitai");
        assert_eq!(comments[0].first_line, "First line");
    }

    #[test]
    fn pr_hygiene_args_parse_search_limit_and_json_flags() {
        let args = parse_pr_hygiene_args(vec![
            OsString::from("--search"),
            OsString::from("author:@me is:pr is:open org:sureapp"),
            OsString::from("--limit=25"),
            OsString::from("--json"),
            OsString::from("--no-workspaces"),
        ])
        .unwrap();
        assert_eq!(args.search.unwrap(), "author:@me is:pr is:open org:sureapp");
        assert_eq!(args.limit, 25);
        assert!(args.json);
        assert!(args.no_workspaces);
        assert!(parse_pr_hygiene_args(vec![OsString::from("--limit=101")]).is_err());
    }

    #[test]
    fn pr_hygiene_parses_graphql_search_results() {
        let report = parse_pr_hygiene_graphql(
            r#"{
              "data": {"search": {"issueCount": 1, "nodes": [{
                "number": 42,
                "title": "fix(policy): stop retry storm [EPD-1234]",
                "url": "https://github.com/sureapp/api/pull/42",
                "state": "OPEN",
                "isDraft": false,
                "reviewDecision": "REVIEW_REQUIRED",
                "createdAt": "2026-07-01T12:00:00Z",
                "updatedAt": "2026-07-05T12:00:00Z",
                "headRefName": "chris/EPD-1234/retry-storm",
                "baseRefName": "main",
                "additions": 120,
                "deletions": 30,
                "changedFiles": 5,
                "repository": {"nameWithOwner": "sureapp/api", "name": "api", "owner": {"login": "sureapp"}},
                "commits": {"totalCount": 2},
                "statusCheckRollup": {"contexts": {"pageInfo": {"hasNextPage": true}, "nodes": [
                  {"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS", "detailsUrl": "https://ci.example/lint"},
                  {"__typename": "StatusContext", "context": "circleci", "state": "PENDING", "targetUrl": "https://ci.example/circle"}
                ]}},
                "reviewThreads": {"pageInfo": {"hasNextPage": true}, "nodes": [
                  {"isResolved": false, "isOutdated": false, "comments": {"nodes": [
                    {"author": {"login": "reviewer"}, "bodyText": "Can we simplify this?\nMore", "path": "src/lib.rs", "line": 10, "url": "https://github.com/comment"}
                  ]}}
                ]}
              }]}}
            }"#,
            "author:@me is:pr is:open",
            50,
        )
        .unwrap();
        assert_eq!(report.total_count, 1);
        assert_eq!(report.prs.len(), 1);
        let pr = &report.prs[0];
        assert_eq!(pr.repo_slug, "sureapp/api");
        assert_eq!(pr.head_ref_name, "chris/EPD-1234/retry-storm");
        assert_eq!(pr.checks.len(), 2);
        assert_eq!(pr.checks[0].bucket, "pass");
        assert_eq!(pr.checks[1].bucket, "pending");
        assert_eq!(pr.comments.len(), 1);
        assert_eq!(pr.comments[0].first_line, "Can we simplify this?");
        assert!(pr.checks_truncated);
        assert!(pr.review_threads_truncated);
    }

    #[test]
    fn pr_hygiene_surfaces_graphql_errors() {
        let err = parse_pr_hygiene_graphql(
            r#"{"errors":[{"message":"Search syntax failed"}],"data":null}"#,
            "bad query",
            50,
        )
        .unwrap_err()
        .to_string();
        assert!(err.contains("Search syntax failed"));
    }

    #[test]
    fn pr_hygiene_review_effort_uses_size_buckets() {
        assert_eq!(review_effort(20, 10, 2, 1), "XS (<10m)");
        assert_eq!(review_effort(200, 40, 6, 4), "S (10-30m)");
        assert_eq!(review_effort(600, 120, 12, 8), "M (30-60m)");
        assert_eq!(review_effort(3000, 100, 50, 20), "XL (multi-hour)");
    }

    #[test]
    fn clap_parses_public_release_commands_and_forwards_legacy_namespaces() {
        let cli = Cli::try_parse_from([
            "jj-workflow",
            "tag-push",
            "v0.2.1",
            "--revision",
            "main",
            "--no-sign",
        ])
        .unwrap();
        match cli.command {
            CliCommand::TagPush(args) => {
                assert_eq!(args.tag, "v0.2.1");
                assert_eq!(args.revision.as_deref(), Some("main"));
                assert!(args.signing.no_sign);
            }
            other => panic!("unexpected command: {other:?}"),
        }

        let cli = Cli::try_parse_from(["jj-workflow", "tag", "push", "v0.2.1", "--sign"]).unwrap();
        match cli.command {
            CliCommand::Tag(tag) => match tag.command {
                TagCommand::Push(args) => {
                    assert_eq!(args.tag, "v0.2.1");
                    assert!(args.signing.sign);
                }
            },
            other => panic!("unexpected command: {other:?}"),
        }

        let cli = Cli::try_parse_from([
            "jj-workflow",
            "ship",
            "--bookmark",
            "main",
            "--tag",
            "v0.2.1",
            "--",
            "--allow-new",
        ])
        .unwrap();
        match cli.command {
            CliCommand::Ship(args) => {
                assert_eq!(args.bookmark_input.as_deref(), Some("main"));
                assert_eq!(args.tag.as_deref(), Some("v0.2.1"));
                assert_eq!(args.passthrough, vec![OsString::from("--allow-new")]);
            }
            other => panic!("unexpected command: {other:?}"),
        }

        let cli = Cli::try_parse_from(["jj-workflow", "pr", "create", "--title", "demo"]).unwrap();
        match cli.command {
            CliCommand::Pr(args) => assert_eq!(
                args.args,
                vec![
                    OsString::from("create"),
                    OsString::from("--title"),
                    OsString::from("demo"),
                ]
            ),
            other => panic!("unexpected command: {other:?}"),
        }
    }

    fn test_config(group: &Path) -> WsConfig {
        WsConfig {
            project_groups: vec![ProjectGroup {
                path: group.to_path_buf(),
                workspace_dir: "ws".to_string(),
            }],
            copy_envrc: "untracked".to_string(),
            venv_mode: "copy".to_string(),
            direnv_allow: true,
            docker_cleanup: "auto".to_string(),
            docker_remove_volumes: true,
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

    struct PathGuard {
        previous: Option<OsString>,
    }

    impl PathGuard {
        fn prepend(dir: &Path) -> Self {
            let previous = env::var_os("PATH");
            let mut paths = vec![dir.to_path_buf()];
            if let Some(previous_path) = previous.as_ref() {
                paths.extend(env::split_paths(previous_path));
            }
            let next = env::join_paths(paths).unwrap();
            env::set_var("PATH", next);
            Self { previous }
        }
    }

    impl Drop for PathGuard {
        fn drop(&mut self) {
            if let Some(previous) = self.previous.as_ref() {
                env::set_var("PATH", previous);
            } else {
                env::remove_var("PATH");
            }
        }
    }

    #[cfg(unix)]
    fn install_fake_npm(root: &Path) -> PathBuf {
        let bin = root.join("bin");
        fs::create_dir_all(&bin).unwrap();
        let npm = bin.join("npm");
        fs::write(
            &npm,
            "#!/bin/sh\ncase \"$1:$2\" in\n  run:lint|test:) exit 0 ;;\n  *) echo \"unexpected fake npm args: $*\" >&2; exit 64 ;;\nesac\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&npm).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&npm, permissions).unwrap();
        bin
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
    fn tag_push_parsing_accepts_release_options() {
        let parsed = parse_tag_push_args(vec![
            "v0.2.1".into(),
            "--revision".into(),
            "main".into(),
            "--remote=origin".into(),
            "--message".into(),
            "repo v0.2.1".into(),
            "--no-sign".into(),
            "--allow-move".into(),
            "--dry-run".into(),
        ])
        .unwrap();
        assert_eq!(
            parsed,
            TagPushArgs {
                tag: "v0.2.1".to_string(),
                revision: Some("main".to_string()),
                remote: Some("origin".to_string()),
                message: Some("repo v0.2.1".to_string()),
                signing: TagSigning::NoSign,
                allow_move: true,
                dry_run: true,
                ..TagPushArgs::default()
            }
        );
    }

    #[test]
    fn tag_push_validates_semver_by_default() {
        validate_release_tag("v0.2.1").unwrap();
        for tag in ["0.2.1", "v0.2", "v0.2.x", "v0.2.1-beta"] {
            assert!(validate_release_tag(tag).is_err(), "{tag} should fail");
        }
    }

    #[test]
    fn tag_signing_flags_are_exclusive() {
        let err = parse_tag_push_args(vec!["v0.2.1".into(), "--sign".into(), "--no-sign".into()])
            .unwrap_err();
        assert!(err.to_string().contains("only one of --sign or --no-sign"));

        let err = parse_common_args(vec![
            "--tag".into(),
            "v0.2.1".into(),
            "--sign".into(),
            "--no-sign".into(),
        ])
        .unwrap_err();
        assert!(err.to_string().contains("only one of --sign or --no-sign"));
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
    fn venv_source_python_must_be_usable() {
        let root = named_tempdir("venv-usable");
        let venv = root.join(".venv");
        fs::create_dir_all(venv.join("bin")).unwrap();

        assert!(!source_venv_python_usable(&venv));

        fs::write(venv.join("bin/python"), "#!/bin/sh\n").unwrap();
        assert!(source_venv_python_usable(&venv));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn ws_add_parser_accepts_flags_and_equals_forms() {
        assert_eq!(
            parse_ws_add_args(vec![
                "feature".into(),
                "--revision=@".into(),
                "--project-group=/tmp/projects".into(),
                "--venv=link".into(),
                "--no-envrc".into(),
                "--no-venv".into(),
                "--no-direnv".into(),
                "-q".into(),
            ])
            .unwrap(),
            WsAddArgs {
                name: "feature".to_string(),
                revision: Some("@".to_string()),
                project_group: Some(PathBuf::from("/tmp/projects")),
                quiet: true,
                venv_mode: Some("link".to_string()),
                no_envrc: true,
                no_venv: true,
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
                keep_docker_volumes: false,
                dry_run: true,
                quiet: true,
            }
        );
        assert!(parse_ws_forget_args(vec![
            "feature".into(),
            "--docker-volumes".into(),
            "--keep-docker-volumes".into(),
        ])
        .is_err());
        assert!(parse_ws_forget_args(vec!["feature".into(), "--pick".into()]).is_err());
        assert!(parse_ws_forget_args(vec![]).is_err());
    }

    #[test]
    fn ws_forget_safety_allows_published_non_empty_work() {
        if which::which("git").is_err() {
            return;
        }

        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("forget-published");
        let origin = root.join("origin.git");
        let repo = root.join("demo");
        run(Command::new("git").arg("init").arg("--bare").arg(&origin));
        run(Command::new("jj").arg("git").arg("init").arg(&repo));
        jj(
            &repo,
            &["git", "remote", "add", "origin", origin.to_str().unwrap()],
        );
        fs::write(repo.join("file.txt"), "hello\n").unwrap();
        jj(&repo, &["describe", "-m", "published"]);

        assert!(workspace_has_unpublished_work(&repo).unwrap());

        jj(&repo, &["bookmark", "set", "feature", "-r", "@"]);
        jj(
            &repo,
            &["git", "push", "--bookmark", "feature", "--remote", "origin"],
        );
        assert!(!workspace_has_unpublished_work(&repo).unwrap());

        jj(&repo, &["new"]);
        assert!(!workspace_has_unpublished_work(&repo).unwrap());

        fs::write(repo.join("local.txt"), "local\n").unwrap();
        jj(&repo, &["describe", "-m", "local"]);
        assert!(workspace_has_unpublished_work(&repo).unwrap());

        jj(&repo, &["new"]);
        assert!(workspace_has_unpublished_work(&repo).unwrap());

        let _ = fs::remove_dir_all(&root);
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
    fn lint_config_parsing_reads_tracked_and_repo_arrays() {
        assert_eq!(
            lint_commands(&parse_lints_toml(
                "lints = [\n  \"cargo fmt --check\",\n  \"cargo test\",\n]\n"
            )),
            strings(&["cargo fmt --check", "cargo test"])
        );
        let named = parse_lints_toml(
            "lints = [\n  { name = \"ruff format\", command = \"uv run ruff format --check .\" },\n  { command = \"uv run mypy\" },\n]\n",
        );
        assert_eq!(
            lint_commands(&named),
            strings(&["uv run ruff format --check .", "uv run mypy"])
        );
        assert_eq!(named[0].name.as_deref(), Some("ruff format"));
        assert_eq!(named[1].name, None);
        assert_eq!(
            parse_config_string_array("[\"pnpm lint\",\"pnpm test\"]"),
            strings(&["pnpm lint", "pnpm test"])
        );
        assert!(parse_lints_toml("not_lints = [\"nope\"]").is_empty());
    }

    #[test]
    fn lint_name_inference_handles_common_runners() {
        for (command, expected) in [
            ("uv run ruff format --check .", "ruff format"),
            ("uv run ruff check .", "ruff check"),
            ("uv run mypy", "mypy"),
            ("poetry run python -m pytest", "pytest"),
            (
                "cargo clippy --workspace --all-targets -- -D warnings",
                "cargo clippy",
            ),
            ("cargo nextest run --workspace", "cargo nextest run"),
            ("npm run typecheck", "npm typecheck"),
            ("npm test", "npm test"),
            ("pnpm lint", "pnpm lint"),
            ("yarn run format:check", "yarn format:check"),
            ("bun run test", "bun test"),
            ("tox run -e linting", "tox linting"),
            ("nox -s tests", "nox tests"),
            ("nix flake check", "nix flake check"),
            ("fd -e sh -e bash -e zsh -x shellcheck", "shellcheck"),
        ] {
            assert_eq!(infer_lint_name(command), expected, "{command}");
        }
    }

    #[test]
    fn lint_display_name_prefers_explicit_name_then_inference() {
        let explicit = LintCommand {
            name: Some("custom validation".to_string()),
            command: "uv run ruff check .".to_string(),
        };
        assert_eq!(lint_display_name(&explicit), "custom validation");

        let inferred = LintCommand {
            name: None,
            command: "uv run ruff check .".to_string(),
        };
        assert_eq!(lint_display_name(&inferred), "ruff check");
    }

    #[test]
    fn lint_onboard_config_uses_named_table_entries() {
        let contents = lint_config_toml(&[LintSuggestion {
            command: "uv run ruff format --check .".to_string(),
            source: "pyproject.toml tool.ruff".to_string(),
            reason: "Python ruff format check".to_string(),
        }])
        .unwrap();

        assert!(
            contents
                .contains("{ name = \"ruff format\", command = \"uv run ruff format --check .\" }"),
            "unexpected config:\n{contents}"
        );
    }

    #[test]
    fn lint_onboard_helper_predicates_are_table_driven() {
        for (script, expected) in [
            ("prettier --check .", true),
            ("prettier --list-different .", true),
            ("biome check .", true),
            ("ruff format --check .", true),
            ("prettier --write .", false),
            ("biome format --write .", false),
            ("eslint --fix .", false),
            ("turbo run format", false),
        ] {
            assert_eq!(
                is_check_only_format_script(script),
                expected,
                "format script: {script}"
            );
        }

        for (script, expected) in [
            ("biome check", true),
            ("prettier --check .", true),
            ("tsc --noEmit", true),
            ("eslint .", true),
            ("eslint . --fix", false),
            ("prettier --write .", false),
            ("vite dev", false),
            ("next start", false),
            ("wrangler deploy", false),
        ] {
            assert_eq!(
                is_safe_package_check_script(script),
                expected,
                "package script: {script}"
            );
        }

        for (name, expected) in [
            ("lint", true),
            ("linting", true),
            ("style", true),
            ("typing", true),
            ("typecheck", true),
            ("test", true),
            ("tests", true),
            ("py", true),
            ("py312", true),
            ("black", true),
            ("flake8", true),
            ("isort", true),
            ("zizmor", true),
            ("pylint", true),
            ("pre-commit", true),
            ("docs", true),
            ("serve", false),
            ("dev", false),
            ("release", false),
        ] {
            assert_eq!(
                is_validation_name(name),
                expected,
                "validation name: {name}"
            );
        }
    }

    #[test]
    fn lint_onboard_target_and_selection_helpers_are_table_driven() {
        let makefile = "lint:\n\ntest tests:\n\ntypecheck type-check:\n\ncheck ci:\n\nall:\n\nserve:\n\n%.o:\n\nFOO := bar\n";
        assert_eq!(
            makefile_targets(makefile),
            strings(&[
                "check",
                "ci",
                "lint",
                "test",
                "tests",
                "type-check",
                "typecheck"
            ])
        );

        for (input, expected) in [("1", vec![1]), ("1,3", vec![1, 3]), ("3,1,3", vec![1, 3])] {
            assert_eq!(
                parse_lint_selection(input).unwrap(),
                expected,
                "selection: {input}"
            );
        }
        for input in ["0", "abc", ""] {
            assert!(
                parse_lint_selection(input).is_err(),
                "selection should fail: {input}"
            );
        }
    }

    #[test]
    fn lint_onboard_python_runner_priority_is_table_driven() {
        for (name, files, pyproject, expected) in [
            ("uv", vec!["uv.lock", "poetry.lock"], "", "uv run "),
            ("pdm", vec!["pdm.lock"], "[tool.poetry]\n", "pdm run "),
            ("poetry", vec!["poetry.lock"], "", "poetry run "),
            ("hatch", vec!["hatch.toml"], "", "hatch run "),
            ("none", Vec::new(), "", ""),
        ] {
            let root = named_tempdir(&format!("lint-runner-{name}"));
            for file in files {
                fs::write(root.join(file), "").unwrap();
            }
            assert_eq!(python_runner(&root, pyproject), expected, "runner: {name}");
            let _ = fs::remove_dir_all(&root);
        }
    }

    #[test]
    fn lint_onboard_detects_package_scripts_and_package_manager() {
        let root = named_tempdir("lint-package");
        fs::write(
            root.join("package.json"),
            r#"{"scripts":{"lint":"eslint .","format":"prettier --write .","format:check":"prettier --check .","typecheck":"tsc --noEmit","check":"pnpm lint && pnpm format:check","test":"vitest","biome":"biome check","build":"vite build"},"lint-staged":{"*.ts":"eslint"}}"#,
        )
        .unwrap();
        fs::write(root.join("pnpm-lock.yaml"), "lockfileVersion: '9'\n").unwrap();

        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        assert_eq!(
            commands,
            vec![
                "pnpm lint",
                "pnpm typecheck",
                "pnpm check",
                "pnpm test",
                "pnpm format:check",
                "pnpm biome"
            ]
        );
        assert!(report
            .inspect
            .iter()
            .any(|item| item.contains("scripts.build")));
        assert!(report
            .inspect
            .iter()
            .any(|item| item.contains("lint-staged")));
        assert!(report
            .inspect
            .iter()
            .any(|item| item.contains("scripts.check includes lint")));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_detects_rust_nix_and_workflow_hints() {
        let root = named_tempdir("lint-workflows");
        fs::create_dir_all(root.join(".github/workflows")).unwrap();
        fs::create_dir_all(root.join(".husky")).unwrap();
        for file in [
            "Cargo.toml",
            "flake.nix",
            "Makefile",
            "justfile",
            "compose.yaml",
            "README.md",
            "CONTRIBUTING.md",
            ".pre-commit-config.yaml",
            "lefthook.yml",
            ".gitlab-ci.yml",
            ".build.yml",
        ] {
            fs::write(root.join(file), "# test\n").unwrap();
        }

        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        assert!(commands.contains(&"cargo fmt --check"));
        assert!(commands.contains(&"cargo clippy --workspace --all-targets -- -D warnings"));
        assert!(commands.contains(&"cargo test --workspace"));
        assert!(commands.contains(&"nix flake check"));
        for needle in [
            "Makefile",
            "justfile",
            "Docker Compose",
            "README.md",
            "CONTRIBUTING.md",
            ".pre-commit-config.yaml",
            ".husky",
            "lefthook",
            ".github/workflows",
            ".gitlab-ci.yml",
            ".build.yml",
        ] {
            assert!(
                report.inspect.iter().any(|item| item.contains(needle)),
                "missing inspect hint for {needle}: {:?}",
                report.inspect
            );
        }

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_json_contains_suggestions_and_hints() {
        let report = LintOnboardReport {
            suggestions: vec![LintSuggestion {
                command: "pnpm lint".to_string(),
                source: "package.json scripts.lint".to_string(),
                reason: "standard lint script".to_string(),
            }],
            inspect: vec!["Makefile -> inspect make test".to_string()],
        };
        let value = lint_onboard_json(&report);
        assert_eq!(value["suggested"][0]["command"], "pnpm lint");
        assert_eq!(value["inspect"][0], "Makefile -> inspect make test");
        assert!(value["hints"].as_array().unwrap().len() >= 3);
    }

    #[test]
    fn lint_onboard_detects_project_lint_and_ci_check_scripts() {
        let root = named_tempdir("lint-scripts");
        fs::create_dir_all(root.join("ci")).unwrap();
        fs::write(root.join("lint"), "#!/bin/sh\ntrue\n").unwrap();
        fs::write(root.join("ci/check"), "#!/bin/sh\ntrue\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(root.join("lint"), fs::Permissions::from_mode(0o755)).unwrap();
            fs::set_permissions(root.join("ci/check"), fs::Permissions::from_mode(0o755)).unwrap();
        }

        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        assert!(commands.contains(&"./lint"));
        assert!(commands.contains(&"ci/check"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_detects_python_pyproject_tools() {
        let root = named_tempdir("lint-python-pyproject");
        fs::write(
            root.join("pyproject.toml"),
            r#"
[tool.ruff]
[tool.mypy]
[tool.pyright]
[tool.pytest.ini_options]
[tool.tox.env.style]
[tool.tox.env.typing]
[dependency-groups]
linting = []
"#,
        )
        .unwrap();
        fs::write(root.join("uv.lock"), "").unwrap();

        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        for expected in ["tox run -e style", "tox run -e typing"] {
            assert!(
                commands.contains(&expected),
                "missing {expected}: {commands:?}"
            );
        }
        for demoted in [
            "uv run ruff check .",
            "uv run ruff format --check .",
            "uv run mypy",
            "uv run pyright",
            "uv run pytest",
        ] {
            assert!(
                !commands.contains(&demoted),
                "unexpected primitive {demoted}: {commands:?}"
            );
        }
        assert!(report
            .inspect
            .iter()
            .any(|item| item.contains("Python project")));
        assert!(report.inspect.iter().any(|item| item.contains("uv run")));
        assert!(report
            .inspect
            .iter()
            .any(|item| item.contains("demoted primitive Python")));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_wraps_python_primitives_when_no_aggregate_exists() {
        let root = named_tempdir("lint-python-wrapper");
        fs::write(
            root.join("pyproject.toml"),
            "[tool.ruff]\n[tool.pytest.ini_options]\n[tool.uv]\n",
        )
        .unwrap();
        fs::write(root.join("uv.lock"), "").unwrap();

        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        assert!(commands.contains(&"uv run ruff check ."));
        assert!(commands.contains(&"uv run ruff format --check ."));
        assert!(commands.contains(&"uv run pytest"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_avoids_pyproject_tox_and_ruff_fix_false_positives() {
        let root = named_tempdir("lint-python-false-positives");
        fs::write(
            root.join("pyproject.toml"),
            r#"
[tool.ruff]
fix = true
[tool.tox.env.style]
commands = []
[dependency-groups]
tests = []
"#,
        )
        .unwrap();

        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        assert!(commands.contains(&"tox run -e style"));
        assert!(!commands.contains(&"tox run -e tests"));
        assert!(!commands.contains(&"ruff check ."));
        assert!(report.inspect.iter().any(|item| item.contains("fix=true")));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_selection_writes_chosen_commands() {
        let root = named_tempdir("lint-selection");
        let report = LintOnboardReport {
            suggestions: vec![
                LintSuggestion {
                    command: "first".to_string(),
                    source: "test".to_string(),
                    reason: "test".to_string(),
                },
                LintSuggestion {
                    command: "second".to_string(),
                    source: "test".to_string(),
                    reason: "test".to_string(),
                },
            ],
            inspect: Vec::new(),
        };
        let selection = parse_lint_selection("2").unwrap();
        write_tracked_lint_config(&root, &report, Some(&selection)).unwrap();
        let written = fs::read_to_string(root.join(".jj-lint.toml")).unwrap();
        assert!(!written.contains("first"));
        assert!(written.contains("second"));
        let preview =
            lint_config_toml(&selected_lints(&report, Some(&selection)).unwrap()).unwrap();
        assert!(!preview.contains("first"));
        assert!(preview.contains("second"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_detects_broader_tox_envs_and_skips_make_all() {
        let root = named_tempdir("lint-broader-tox");
        fs::write(
            root.join("tox.ini"),
            "[tox]\nenvlist = black, flake8, isort, zizmor, py, py312, docs\n[testenv:pre-commit]\ncommands = pre-commit run --all-files\n",
        )
        .unwrap();
        fs::write(root.join("Makefile"), "all:\n\t@echo help\nlint:\n\ttrue\n").unwrap();
        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        for expected in [
            "tox run -e black",
            "tox run -e flake8",
            "tox run -e isort",
            "tox run -e zizmor",
            "tox run -e py",
            "tox run -e py312",
            "tox run -e docs",
            "tox run -e pre-commit",
            "make lint",
        ] {
            assert!(
                commands.contains(&expected),
                "missing {expected}: {commands:?}"
            );
        }
        assert!(!commands.contains(&"make all"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_detects_python_tox_nox_and_script_entrypoints() {
        let root = named_tempdir("lint-python-tox-nox");
        fs::create_dir_all(root.join("scripts")).unwrap();
        fs::write(
            root.join("tox.ini"),
            "[tox]\nenvlist = linting, py312\n[testenv:typing]\ncommands = mypy\n",
        )
        .unwrap();
        fs::write(
            root.join("noxfile.py"),
            "def lint(session): pass\ndef tests(session): pass\n",
        )
        .unwrap();
        fs::write(root.join("scripts/check"), "#!/bin/sh\ntrue\n").unwrap();
        fs::write(root.join("scripts/lint"), "#!/bin/sh\nruff check --fix\n").unwrap();

        let report = lint_onboard_report(&root).unwrap();
        let commands = report
            .suggestions
            .iter()
            .map(|lint| lint.command.as_str())
            .collect::<Vec<_>>();
        for expected in [
            "tox run -e linting",
            "tox run -e typing",
            "nox -s lint",
            "nox -s tests",
            "scripts/check",
        ] {
            assert!(
                commands.contains(&expected),
                "missing {expected}: {commands:?}"
            );
        }
        assert!(report
            .inspect
            .iter()
            .any(|item| item.contains("scripts/lint")));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lint_onboard_write_tracked_refuses_overwrite_and_reads_back() {
        let root = named_tempdir("lint-write");
        let report = LintOnboardReport {
            suggestions: vec![
                LintSuggestion {
                    command: "true".to_string(),
                    source: "test".to_string(),
                    reason: "test".to_string(),
                },
                LintSuggestion {
                    command: "printf ok".to_string(),
                    source: "test".to_string(),
                    reason: "test".to_string(),
                },
            ],
            inspect: Vec::new(),
        };

        write_tracked_lint_config(&root, &report, None).unwrap();
        assert_eq!(
            lint_commands(&configured_lints(&root).unwrap()),
            strings(&["true", "printf ok"])
        );
        assert!(write_tracked_lint_config(&root, &report, None).is_err());

        let _ = fs::remove_dir_all(&root);
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
        fs::write(repo.join(".gitignore"), ".venv\n.jj-lint.toml\n").unwrap();
        fs::write(repo.join("tracked.txt"), "hello\n").unwrap();
        fs::write(repo.join(".envrc"), "use flake\n").unwrap();
        fs::write(repo.join(".jj-lint.toml"), "lints = [\"true\"]\n").unwrap();
        fs::create_dir_all(repo.join(".venv/bin")).unwrap();
        let source_venv = fs::canonicalize(&repo).unwrap().join(".venv");
        fs::write(
            repo.join(".venv/pyvenv.cfg"),
            format!("command = {}\n", source_venv.display()),
        )
        .unwrap();
        fs::write(repo.join(".venv/bin/python"), "#!/bin/sh\n").unwrap();
        fs::write(
            repo.join(".venv/bin/tool"),
            format!("#!{}/bin/python\n", source_venv.display()),
        )
        .unwrap();
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
        assert_eq!(
            fs::read_to_string(ws.join(".jj-lint.toml")).unwrap(),
            "lints = [\"true\"]\n"
        );
        assert!(!fs::symlink_metadata(ws.join(".venv"))
            .unwrap()
            .file_type()
            .is_symlink());
        let dest_venv = fs::canonicalize(&ws).unwrap().join(".venv");
        let copied_tool = fs::read_to_string(ws.join(".venv/bin/tool")).unwrap();
        assert!(copied_tool.contains(&dest_venv.to_string_lossy().to_string()));
        assert!(!copied_tool.contains(&source_venv.to_string_lossy().to_string()));
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
    fn integration_skips_broken_source_venv() {
        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("broken-venv");
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
        fs::write(repo.join(".gitignore"), ".venv\n").unwrap();
        fs::write(repo.join("tracked.txt"), "hello\n").unwrap();
        fs::create_dir_all(repo.join(".venv/bin")).unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink("/missing/python", repo.join(".venv/bin/python")).unwrap();
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
        assert!(!ws.join(".venv").exists());
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

    #[test]
    fn integration_tag_push_publishes_and_verifies_remote_tag() {
        if which::which("git").is_err() {
            return;
        }

        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("tag-push");
        let origin = root.join("origin.git");
        let repo = root.join("repo");

        run(Command::new("git").arg("init").arg("--bare").arg(&origin));
        run(Command::new("jj").arg("git").arg("init").arg(&repo));
        jj(
            &repo,
            &["git", "remote", "add", "origin", origin.to_str().unwrap()],
        );
        fs::write(repo.join("file.txt"), "initial\n").unwrap();
        jj(&repo, &["describe", "-m", "initial"]);
        jj(&repo, &["bookmark", "set", "main", "-r", "@"]);
        jj(
            &repo,
            &["git", "push", "--bookmark", "main", "--remote", "origin"],
        );
        let target_commit = jj_stdout(
            &repo,
            &[
                "log",
                "-r",
                "main",
                "-n",
                "1",
                "--no-graph",
                "--color=never",
                "-T",
                "commit_id",
            ],
        )
        .trim()
        .to_string();

        let old = env::current_dir().unwrap();
        env::set_current_dir(&repo).unwrap();
        tag_push(TagPushArgs {
            tag: "v0.2.1".to_string(),
            revision: Some("main".to_string()),
            remote: Some("origin".to_string()),
            signing: TagSigning::NoSign,
            quiet: true,
            ..TagPushArgs::default()
        })
        .unwrap();
        env::set_current_dir(old).unwrap();

        assert_remote_annotated_tag(&origin, "v0.2.1", &target_commit);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn integration_tag_push_rejects_existing_remote_lightweight_tag() {
        if which::which("git").is_err() {
            return;
        }

        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("tag-push-lightweight");
        let origin = root.join("origin.git");
        let repo = root.join("repo");

        run(Command::new("git").arg("init").arg("--bare").arg(&origin));
        run(Command::new("jj").arg("git").arg("init").arg(&repo));
        jj(
            &repo,
            &["git", "remote", "add", "origin", origin.to_str().unwrap()],
        );
        fs::write(repo.join("file.txt"), "initial\n").unwrap();
        jj(&repo, &["describe", "-m", "initial"]);
        jj(&repo, &["bookmark", "set", "main", "-r", "@"]);
        jj(
            &repo,
            &["git", "push", "--bookmark", "main", "--remote", "origin"],
        );
        let target_commit = jj_stdout(
            &repo,
            &[
                "log",
                "-r",
                "main",
                "-n",
                "1",
                "--no-graph",
                "--color=never",
                "-T",
                "commit_id",
            ],
        )
        .trim()
        .to_string();
        let git_dir = jj_stdout(&repo, &["git", "root"]).trim().to_string();
        run(Command::new("git")
            .arg("-c")
            .arg("tag.gpgSign=false")
            .arg("--git-dir")
            .arg(&git_dir)
            .arg("tag")
            .arg("v0.2.3")
            .arg(&target_commit));
        run(Command::new("git")
            .arg("--git-dir")
            .arg(&git_dir)
            .arg("push")
            .arg("origin")
            .arg("refs/tags/v0.2.3"));

        let old = env::current_dir().unwrap();
        env::set_current_dir(&repo).unwrap();
        let err = tag_push(TagPushArgs {
            tag: "v0.2.3".to_string(),
            revision: Some("main".to_string()),
            remote: Some("origin".to_string()),
            signing: TagSigning::NoSign,
            quiet: true,
            ..TagPushArgs::default()
        })
        .unwrap_err();
        env::set_current_dir(old).unwrap();

        assert!(
            err.to_string().contains("is lightweight"),
            "unexpected error: {err:#}"
        );

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn integration_ship_tag_tags_the_shipped_commit() {
        if which::which("git").is_err() {
            return;
        }

        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("ship-tag");
        let origin = root.join("origin.git");
        let repo = root.join("repo");

        run(Command::new("git").arg("init").arg("--bare").arg(&origin));
        run(Command::new("jj").arg("git").arg("init").arg(&repo));
        jj(
            &repo,
            &["git", "remote", "add", "origin", origin.to_str().unwrap()],
        );
        fs::write(repo.join("file.txt"), "release\n").unwrap();
        jj(&repo, &["describe", "-m", "release"]);
        let shipped_commit = jj_stdout(
            &repo,
            &[
                "log",
                "-r",
                "@",
                "-n",
                "1",
                "--no-graph",
                "--color=never",
                "-T",
                "commit_id",
            ],
        )
        .trim()
        .to_string();

        let old = env::current_dir().unwrap();
        env::set_current_dir(&repo).unwrap();
        run_ship(
            parse_common_args(vec![
                "--bookmark".into(),
                "main".into(),
                "--remote".into(),
                "origin".into(),
                "--tag".into(),
                "v0.2.2".into(),
                "--no-sign".into(),
            ])
            .unwrap(),
        )
        .unwrap();
        env::set_current_dir(old).unwrap();

        assert_remote_annotated_tag(&origin, "v0.2.2", &shipped_commit);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn integration_lint_onboard_writes_and_runs_package_lints() {
        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("lint-run");
        #[cfg(unix)]
        let _path_guard = PathGuard::prepend(&install_fake_npm(&root));
        run(Command::new("jj").arg("git").arg("init").arg(&root));
        fs::write(
            root.join("package.json"),
            r#"{"scripts":{"lint":"true","test":"true"}}"#,
        )
        .unwrap();

        let old = env::current_dir().unwrap();
        env::set_current_dir(&root).unwrap();
        run_lint_onboard(vec!["--write".into()]).unwrap();
        assert_eq!(
            lint_commands(&configured_lints(&root).unwrap()),
            strings(&["npm run lint", "npm test"])
        );
        run_lint(Vec::new()).unwrap();
        env::set_current_dir(old).unwrap();

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn integration_lint_onboard_preview_select_does_not_write() {
        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("lint-preview");
        run(Command::new("jj").arg("git").arg("init").arg(&root));
        fs::write(
            root.join("package.json"),
            r#"{"scripts":{"lint":"true","typecheck":"true","test":"true"}}"#,
        )
        .unwrap();

        let old = env::current_dir().unwrap();
        env::set_current_dir(&root).unwrap();
        run_lint_onboard(vec!["--preview".into(), "--select=1,3".into()]).unwrap();
        env::set_current_dir(old).unwrap();

        assert!(!root.join(".jj-lint.toml").exists());
        assert!(configured_lints(&root).unwrap().is_empty());

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn integration_lint_onboard_local_select_sets_selected_lints() {
        let _guard = INTEGRATION_LOCK.lock().unwrap();
        let root = named_tempdir("lint-local-select");
        run(Command::new("jj").arg("git").arg("init").arg(&root));
        fs::write(
            root.join("package.json"),
            r#"{"scripts":{"lint":"true","typecheck":"true","test":"true"}}"#,
        )
        .unwrap();

        let old = env::current_dir().unwrap();
        env::set_current_dir(&root).unwrap();
        run_lint_onboard(vec!["--local".into(), "--select=2".into()]).unwrap();
        assert_eq!(
            lint_commands(&configured_lints(&root).unwrap()),
            strings(&["npm run typecheck"])
        );
        env::set_current_dir(old).unwrap();
        assert!(!root.join(".jj-lint.toml").exists());

        let _ = fs::remove_dir_all(&root);
    }
}

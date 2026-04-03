use anyhow::{anyhow, bail, Context, Result};
use std::env;
use std::ffi::{OsStr, OsString};
use std::io::{self, IsTerminal, Write};
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
        "Usage:\n  {name} ship [-b|--bookmark <bookmark>] [--remote <remote>] [-- <jj push args...>]\n  {name} sync [-b|--bookmark <bookmark>] [--remote <remote>] [--onto <revset>] [-- <jj rebase args...>]"
    );
}

#[derive(Debug, Default, PartialEq, Eq)]
struct ParsedArgs {
    bookmark_input: Option<String>,
    remote_input: Option<String>,
    onto: Option<String>,
    help: bool,
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

    let base_rev = if let Some(onto) = args.onto.take() {
        onto
    } else if let Some(bookmark_input) = args.bookmark_input.take() {
        if let Some((_bookmark, remote)) = split_bookmark_remote(&bookmark_input) {
            if args.remote_input.is_none() {
                args.remote_input = Some(remote.to_string());
            }
        }
        bookmark_input
    } else {
        resolve_sync_base()?
    };

    if let Some(remote) = args.remote_input.as_deref() {
        run_jj_status(["git", "fetch", "--remote", remote])?;
    } else {
        run_jj_status(["git", "fetch"])?;
    }

    if base_rev != "trunk()" && commit_id(&base_rev)?.is_none() {
        bail!("sync base '{base_rev}' not found after fetch")
    }

    let mut rebase_args = vec![
        OsString::from("rebase"),
        OsString::from("-d"),
        OsString::from(base_rev),
    ];
    rebase_args.extend(args.passthrough);
    run_jj_status_os(rebase_args)
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

fn resolve_sync_base() -> Result<String> {
    let bookmarks = all_local_bookmarks()?;

    if let Some(candidates) = sync_base_candidates(&bookmarks) {
        return pick_option("Sync base", &candidates, "Re-run with --bookmark <name>.");
    }

    if commit_id("trunk()")?.is_some() {
        eprintln!("Warning: no local integration bookmark found; falling back to trunk().");
        Ok("trunk()".to_string())
    } else {
        bail!("couldn't determine a sync base. Use --bookmark <name>.")
    }
}

fn all_local_bookmarks() -> Result<Vec<String>> {
    let output = run_jj_capture([
        "bookmark",
        "list",
        "--color=never",
        "-T",
        "self.name() ++ \"\\n\"",
    ])?;
    Ok(output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(std::string::ToString::to_string)
        .collect())
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
        Some(target) => run_jj_status(["bookmark", "set", bookmark, "-r", target]),
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
        "Usage:\n  jj ship [-b|--bookmark <bookmark>] [--remote <remote>] [-- <jj push args...>]\n\nShips the parent of the working copy. Refuses empty targets and will not fall back to integration bookmarks unless you choose one explicitly with --bookmark."
    );
}

fn print_sync_usage() {
    eprintln!(
        "Usage:\n  jj sync [-b|--bookmark <bookmark>] [--remote <remote>] [--onto <revset>] [-- <jj rebase args...>]"
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

fn filter_bookmarks<F>(bookmarks: &[String], predicate: F) -> Vec<String>
where
    F: Fn(&str) -> bool,
{
    bookmarks
        .iter()
        .filter(|bookmark| predicate(bookmark))
        .cloned()
        .collect()
}

fn pick_option(prompt: &str, options: &[String], rerun_hint: &str) -> Result<String> {
    match options {
        [] => bail!("no options available for {prompt}"),
        [only] => Ok(only.clone()),
        _ => {
            eprintln!("Warning: {prompt} is ambiguous.");

            if io::stdin().is_terminal()
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

struct JjOutput {
    status: std::process::ExitStatus,
    stdout: String,
    stderr: String,
}

#[cfg(test)]
mod tests {
    use super::{
        choose_ship_bookmark, is_integration_bookmark, parse_common_args, ship_plan,
        sync_base_candidates, ParsedArgs, ShipPlan,
    };
    use std::ffi::OsString;

    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| (*value).to_string()).collect()
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
}

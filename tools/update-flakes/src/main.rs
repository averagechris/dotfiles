use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const DEFAULT_COOLDOWN_DAYS: i64 = 7;
const DEFAULT_COOLDOWN_INPUTS: &str = "pi,pi-coding-agent";

#[derive(Debug)]
struct Config {
    check_only: bool,
    ignore_cooldown: bool,
    cooldown_days: i64,
    cooldown_inputs: HashSet<String>,
    update_flakes: bool,
    update_manual_packages: bool,
    selected_manual_packages: HashSet<String>,
    skipped_manual_packages: HashSet<String>,
    manual_versions: HashMap<String, String>,
    manifest_path: PathBuf,
    show_output: bool,
}

#[derive(Debug, Deserialize)]
struct Manifest {
    packages: Vec<ManualPackage>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ManualPackage {
    name: String,
    enabled: bool,
    kind: String,
    file: PathBuf,
    #[serde(default)]
    cooldown: bool,
    #[serde(default)]
    cooldown_days: Option<i64>,
    latest: LatestSource,
    #[serde(default)]
    assets: Vec<ArchiveAsset>,
    #[serde(default)]
    note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
enum LatestSource {
    Manual,
    GithubRelease {
        owner: String,
        repo: String,
        #[serde(default, rename = "stripPrefix")]
        strip_prefix: Option<String>,
    },
}

#[derive(Debug, Deserialize)]
struct ArchiveAsset {
    #[serde(default)]
    system: Option<String>,
    url: String,
    #[serde(default)]
    unpack: bool,
}

#[derive(Clone, Debug)]
struct GithubRelease {
    version: String,
    published_at: Option<DateTime<Utc>>,
}

#[derive(Debug)]
struct CommandOutput {
    stdout: String,
    stderr: String,
}

fn main() {
    if let Err(err) = run() {
        log_error(&err.to_string());
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let repo_root = find_repo_root()?;
    let mut config = parse_args(&repo_root)?;

    env::set_current_dir(&repo_root)?;

    log_info("Starting updates...");
    if config.ignore_cooldown {
        log_warn("Cooldown checks are disabled for this run");
    } else {
        let mut inputs = config.cooldown_inputs.iter().cloned().collect::<Vec<_>>();
        inputs.sort();
        let inputs = inputs.join(",");
        log_info(&format!(
            "Cooldown: {}d for gated inputs/manual packages: {}",
            config.cooldown_days, inputs
        ));
    }
    println!();

    if config.update_flakes {
        update_all_flakes(&repo_root, &config)?;
    }

    if config.update_manual_packages {
        update_manual_packages(&repo_root, &mut config)?;
    }

    if config.check_only {
        log_info("Check complete. Run without --check to apply updates.");
    } else {
        log_info("Updates completed successfully!");
        log_info("");
        log_info("Next steps:");
        log_info("  1. Review changes: jj diff");
        log_info("  2. Test builds: nix flake check");
        log_info("  3. Describe: jj describe -m 'chore: update flake inputs and manual packages'");
        log_info("");
        log_info("Use --ignore-cooldown only after manually reviewing fresh upstream releases.");
    }

    Ok(())
}

fn parse_args(repo_root: &Path) -> Result<Config, Box<dyn std::error::Error>> {
    let cooldown_days = env::var("FLAKE_UPDATE_COOLDOWN_DAYS")
        .ok()
        .and_then(|value| value.parse::<i64>().ok())
        .unwrap_or(DEFAULT_COOLDOWN_DAYS);
    let cooldown_inputs_raw = env::var("FLAKE_UPDATE_COOLDOWN_INPUTS")
        .unwrap_or_else(|_| DEFAULT_COOLDOWN_INPUTS.to_string());

    let mut config = Config {
        check_only: false,
        ignore_cooldown: false,
        cooldown_days,
        cooldown_inputs: split_csv(&cooldown_inputs_raw),
        update_flakes: true,
        update_manual_packages: true,
        selected_manual_packages: HashSet::new(),
        skipped_manual_packages: env::var("MANUAL_PACKAGE_UPDATE_SKIP")
            .map(|value| split_csv(&value))
            .unwrap_or_default(),
        manual_versions: HashMap::new(),
        manifest_path: repo_root.join("manual-package-updates.json"),
        show_output: env::var("UPDATE_FLAKES_SHOW_OUTPUT")
            .map(|value| matches!(value.as_str(), "1" | "true" | "yes"))
            .unwrap_or(false),
    };

    let args = env::args().skip(1).collect::<Vec<_>>();
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--check" => config.check_only = true,
            "--ignore-cooldown" => config.ignore_cooldown = true,
            "--cooldown-days" => {
                index += 1;
                config.cooldown_days = args
                    .get(index)
                    .ok_or("--cooldown-days requires a day count")?
                    .parse()?;
            }
            "--cooldown-inputs" => {
                index += 1;
                config.cooldown_inputs = split_csv(
                    args.get(index)
                        .ok_or("--cooldown-inputs requires a comma-separated input list")?,
                );
            }
            "--no-manual-packages" => config.update_manual_packages = false,
            "--manual-packages-only" => config.update_flakes = false,
            "--manual-package" | "--package" => {
                index += 1;
                config.selected_manual_packages.insert(
                    args.get(index)
                        .ok_or("--manual-package requires a package name")?
                        .to_string(),
                );
            }
            "--skip-manual-package" | "--skip-package" => {
                index += 1;
                config.skipped_manual_packages.insert(
                    args.get(index)
                        .ok_or("--skip-manual-package requires a package name")?
                        .to_string(),
                );
            }
            "--manual-version" | "--version" => {
                index += 1;
                let value = args
                    .get(index)
                    .ok_or("--manual-version requires name=version")?;
                let (name, version) = value
                    .split_once('=')
                    .ok_or("--manual-version requires name=version")?;
                config
                    .manual_versions
                    .insert(name.to_string(), version.to_string());
            }
            "--manifest" => {
                index += 1;
                config.manifest_path = PathBuf::from(
                    args.get(index)
                        .ok_or("--manifest requires a manifest path")?,
                );
            }
            "--show-output" => config.show_output = true,
            "--help" | "-h" => {
                print_help();
                std::process::exit(0);
            }
            other => return Err(format!("Unknown argument: {other}").into()),
        }
        index += 1;
    }

    Ok(config)
}

fn print_help() {
    println!(
        "Usage: update-flakes [OPTIONS]\n\n\
         Options:\n\
           --check                         Check for updates without applying\n\
           --ignore-cooldown               Disable flake/manual package cooldown checks\n\
           --cooldown-days DAYS            Cooldown window for gated inputs/packages\n\
           --cooldown-inputs CSV           Flake inputs gated by cooldown\n\
           --no-manual-packages            Only update flake inputs\n\
           --manual-packages-only          Only update manifest-enrolled manual packages\n\
           --manual-package NAME           Limit manual package updates to NAME\n\
           --skip-manual-package NAME      Skip a manifest-enrolled manual package\n\
           --manual-version NAME=VERSION   Provide an explicit version for a manual package\n\
           --manifest PATH                 Use an alternate manual package manifest\n\
           --show-output                   Stream full output from nix update commands\n"
    );
}

fn split_csv(value: &str) -> HashSet<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn find_repo_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    if let Ok(root) = env::var("DOTFILES_REPO_ROOT") {
        return Ok(PathBuf::from(root));
    }

    let mut dir = env::current_dir()?;
    loop {
        if dir.join("flake.nix").exists() && dir.join("scripts").exists() {
            return Ok(dir);
        }
        if !dir.pop() {
            return Err("could not find dotfiles repository root".into());
        }
    }
}

fn update_all_flakes(repo_root: &Path, config: &Config) -> Result<(), Box<dyn std::error::Error>> {
    log_info("=== Updating shared module flakes ===");
    update_flake(&repo_root.join("flakes/base-lib"), "base-lib", config)?;
    update_flake(
        &repo_root.join("flakes/nixos-modules"),
        "nixos-modules",
        config,
    )?;
    update_flake(&repo_root.join("flakes/hm-modules"), "hm-modules", config)?;
    update_flake(
        &repo_root.join("flakes/darwin-modules"),
        "darwin-modules",
        config,
    )?;
    println!();

    log_info("=== Updating host flakes ===");
    let hosts_dir = repo_root.join("flakes/hosts");
    let mut hosts = fs::read_dir(&hosts_dir)?
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().map(|ty| ty.is_dir()).unwrap_or(false))
        .collect::<Vec<_>>();
    hosts.sort_by_key(|entry| entry.file_name());
    for host in hosts {
        let name = host.file_name().to_string_lossy().to_string();
        update_flake(&host.path(), &format!("hosts/{name}"), config)?;
    }
    println!();

    log_info("=== Updating top-level flake ===");
    update_flake(repo_root, "top-level", config)?;
    println!();

    Ok(())
}

fn update_flake(
    flake_path: &Path,
    flake_name: &str,
    config: &Config,
) -> Result<(), Box<dyn std::error::Error>> {
    if !flake_path.join("flake.nix").exists() {
        log_warn(&format!("Skipping {flake_name}: no flake.nix found"));
        return Ok(());
    }

    if config.check_only {
        log_info(&format!("Checking {flake_name}..."));
    } else {
        log_info(&format!("Updating {flake_name}..."));
    }

    let mut has_cooldown_input = false;
    let mut update_inputs = Vec::new();
    let lock_path = flake_path.join("flake.lock");

    if !config.ignore_cooldown && lock_path.exists() {
        for input in list_updateable_inputs(&lock_path)? {
            if config.cooldown_inputs.contains(&input) {
                has_cooldown_input = true;
                if input_passes_cooldown(flake_name, flake_path, &input, config)? {
                    update_inputs.push(input);
                }
            } else {
                update_inputs.push(input);
            }
        }

        if !has_cooldown_input {
            update_inputs.clear();
        } else if update_inputs.is_empty() {
            log_info(&format!(
                "  No updateable inputs remain for {flake_name} after cooldown checks"
            ));
            return Ok(());
        }
    }

    let input_args = if config.ignore_cooldown || update_inputs.is_empty() {
        Vec::new()
    } else {
        update_inputs
    };

    if config.check_only {
        let mut args = vec!["flake".to_string(), "update".to_string()];
        args.extend(input_args);
        args.extend([
            "--flake".to_string(),
            flake_path.display().to_string(),
            "--dry-run".to_string(),
        ]);
        let output = run_capture("nix", &args)?;
        if config.show_output {
            print_command_output(&output);
        }
        if output.stdout.contains("would update") || output.stderr.contains("would update") {
            log_info(&format!("  Updates available for {flake_name}"));
        } else {
            log_info(&format!("  {flake_name} is up to date"));
        }
    } else {
        let mut args = vec!["flake".to_string(), "update".to_string()];
        args.extend(input_args);
        args.extend(["--flake".to_string(), flake_path.display().to_string()]);
        run_status("nix", &args, config.show_output)?;
    }

    Ok(())
}

fn list_updateable_inputs(lock_path: &Path) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let lock: Value = serde_json::from_str(&fs::read_to_string(lock_path)?)?;
    let nodes = lock
        .get("nodes")
        .and_then(Value::as_object)
        .ok_or("flake.lock is missing nodes")?;
    let root_inputs = nodes
        .get("root")
        .and_then(|root| root.get("inputs"))
        .and_then(Value::as_object)
        .ok_or("flake.lock is missing root inputs")?;

    let mut inputs = Vec::new();
    for (name, node_ref) in root_inputs {
        let Some(node_ref) = node_ref.as_str() else {
            continue;
        };
        let Some(node) = nodes.get(node_ref).and_then(Value::as_object) else {
            continue;
        };
        let input_type = node
            .get("original")
            .and_then(|original| original.get("type"))
            .or_else(|| node.get("locked").and_then(|locked| locked.get("type")))
            .and_then(Value::as_str);

        if input_type == Some("path") {
            continue;
        }
        inputs.push(name.clone());
    }

    Ok(inputs)
}

fn input_passes_cooldown(
    flake_name: &str,
    flake_path: &Path,
    input_name: &str,
    config: &Config,
) -> Result<bool, Box<dyn std::error::Error>> {
    let Some(input_ref) = input_ref_from_lock(&flake_path.join("flake.lock"), input_name)? else {
        log_warn(&format!(
            "  Skipping {flake_name} input '{input_name}': cannot determine candidate ref for cooldown check"
        ));
        return Ok(false);
    };

    let args = vec!["flake", "metadata", "--json", &input_ref];
    let output = match run_capture("nix", &args) {
        Ok(output) => output,
        Err(_) => {
            log_warn(&format!(
                "  Skipping {flake_name} input '{input_name}': cannot determine candidate age for {input_ref}"
            ));
            return Ok(false);
        }
    };
    let metadata: Value = serde_json::from_str(&output.stdout)?;
    let Some(last_modified) = metadata
        .get("locked")
        .and_then(|locked| locked.get("lastModified"))
        .and_then(Value::as_i64)
    else {
        log_warn(&format!(
            "  Skipping {flake_name} input '{input_name}': metadata for {input_ref} has no lastModified"
        ));
        return Ok(false);
    };

    let age_seconds = Utc::now().timestamp() - last_modified;
    let cooldown_seconds = config.cooldown_days * 24 * 60 * 60;
    let age_days = age_seconds / 86_400;
    if age_seconds < cooldown_seconds {
        log_warn(&format!(
            "  Skipping {flake_name} input '{input_name}': latest {input_ref} is {age_days}d old; cooldown is {}d",
            config.cooldown_days
        ));
        return Ok(false);
    }

    Ok(true)
}

fn input_ref_from_lock(
    lock_path: &Path,
    input_name: &str,
) -> Result<Option<String>, Box<dyn std::error::Error>> {
    let lock: Value = serde_json::from_str(&fs::read_to_string(lock_path)?)?;
    let nodes = lock
        .get("nodes")
        .and_then(Value::as_object)
        .ok_or("flake.lock is missing nodes")?;
    let Some(node_ref) = nodes
        .get("root")
        .and_then(|root| root.get("inputs"))
        .and_then(|inputs| inputs.get(input_name))
        .and_then(Value::as_str)
    else {
        return Ok(None);
    };
    let Some(node) = nodes.get(node_ref).and_then(Value::as_object) else {
        return Ok(None);
    };
    let source = node
        .get("original")
        .or_else(|| node.get("locked"))
        .and_then(Value::as_object);
    let Some(source) = source else {
        return Ok(None);
    };
    let Some(input_type) = source.get("type").and_then(Value::as_str) else {
        return Ok(None);
    };

    let ref_string = match input_type {
        "github" => {
            let mut reference = format!(
                "github:{}/{}",
                source
                    .get("owner")
                    .and_then(Value::as_str)
                    .ok_or("github input missing owner")?,
                source
                    .get("repo")
                    .and_then(Value::as_str)
                    .ok_or("github input missing repo")?
            );
            if let Some(branch) = source.get("ref").and_then(Value::as_str) {
                reference.push('/');
                reference.push_str(branch);
            }
            reference
        }
        "sourcehut" => {
            let mut reference = format!(
                "sourcehut:{}/{}",
                source
                    .get("owner")
                    .and_then(Value::as_str)
                    .ok_or("sourcehut input missing owner")?,
                source
                    .get("repo")
                    .and_then(Value::as_str)
                    .ok_or("sourcehut input missing repo")?
            );
            if let Some(branch) = source.get("ref").and_then(Value::as_str) {
                reference.push('/');
                reference.push_str(branch);
            }
            reference
        }
        "git" => {
            let mut reference = format!(
                "git+{}",
                source
                    .get("url")
                    .and_then(Value::as_str)
                    .ok_or("git input missing url")?
            );
            if let Some(branch) = source.get("ref").and_then(Value::as_str) {
                reference.push_str("?ref=");
                reference.push_str(branch);
            }
            reference
        }
        _ => return Ok(None),
    };

    Ok(Some(ref_string))
}

fn update_manual_packages(
    repo_root: &Path,
    config: &mut Config,
) -> Result<(), Box<dyn std::error::Error>> {
    log_info("=== Updating manifest-enrolled manual packages ===");
    let manifest_path = absolutize(repo_root, &config.manifest_path);
    let manifest: Manifest = serde_json::from_str(&fs::read_to_string(&manifest_path)?)?;

    for package in manifest.packages {
        let package_selected = config.selected_manual_packages.contains(&package.name);
        if !config.selected_manual_packages.is_empty() && !package_selected {
            continue;
        }
        if config.skipped_manual_packages.contains(&package.name) {
            log_info(&format!("Skipping {}: skipped by CLI/env", package.name));
            continue;
        }
        if !package.enabled {
            if package_selected {
                let note = package.note.as_deref().unwrap_or("disabled in manifest");
                log_info(&format!("Skipping {}: {note}", package.name));
            }
            continue;
        }
        if package.kind != "archive" {
            if package_selected {
                log_warn(&format!(
                    "Skipping {}: updater kind '{}' is not implemented yet",
                    package.name, package.kind
                ));
            }
            continue;
        }
        update_archive_package(repo_root, config, &package, package_selected)?;
    }
    println!();
    Ok(())
}

fn update_archive_package(
    repo_root: &Path,
    config: &Config,
    package: &ManualPackage,
    package_selected: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let package_file = repo_root.join(&package.file);
    let current_text = fs::read_to_string(&package_file)?;
    let current_version = extract_nix_string_attr(&current_text, "version")
        .ok_or_else(|| format!("{} has no version attribute", package.file.display()))?;

    let release = resolve_target_version(config, package, package_selected)?;
    let Some(release) = release else {
        return Ok(());
    };

    if release.version == current_version {
        if package_selected || config.check_only {
            log_info(&format!(
                "{} is up to date ({current_version})",
                package.name
            ));
        }
        return Ok(());
    }

    if !config.ignore_cooldown && package.cooldown {
        let cooldown_days = package.cooldown_days.unwrap_or(config.cooldown_days);
        if let Some(published_at) = release.published_at {
            let age = Utc::now() - published_at;
            if age.num_days() < cooldown_days {
                log_warn(&format!(
                    "Skipping {}: latest {} is {}d old; cooldown is {}d",
                    package.name,
                    release.version,
                    age.num_days(),
                    cooldown_days
                ));
                return Ok(());
            }
        } else {
            log_warn(&format!(
                "{}: cannot determine release age for cooldown; continuing because the target version was provided explicitly",
                package.name
            ));
        }
    }

    log_info(&format!(
        "{}: {current_version} -> {}",
        package.name, release.version
    ));

    let mut hashes = Vec::new();
    for asset in &package.assets {
        let url = asset.url.replace("{version}", &release.version);
        if config.check_only {
            if config.show_output {
                let label = asset.system.as_deref().unwrap_or("source");
                log_info(&format!("  would prefetch {label}: {url}"));
            }
            continue;
        }
        if config.show_output {
            let label = asset.system.as_deref().unwrap_or("source");
            log_info(&format!("  prefetching {label}: {url}"));
        }
        let hash = prefetch_url(&url, asset.unpack)?;
        if config.show_output {
            let label = asset.system.as_deref().unwrap_or("source");
            log_info(&format!("  {label}: {hash}"));
        }
        hashes.push((asset.system.clone(), hash));
    }

    if config.check_only {
        log_info(&format!(
            "  Updates available for {}; would refresh {} asset hash(es)",
            package.name,
            package.assets.len()
        ));
        return Ok(());
    }

    let mut new_text = replace_nix_string_attr_once(&current_text, "version", &release.version)?;
    for (system, hash) in hashes {
        new_text = replace_hash(&new_text, system.as_deref(), &hash)?;
    }
    fs::write(package_file, new_text)?;
    log_info(&format!(
        "  Updated {}; refreshed {} asset hash(es)",
        package.file.display(),
        package.assets.len()
    ));

    Ok(())
}

fn resolve_target_version(
    config: &Config,
    package: &ManualPackage,
    package_selected: bool,
) -> Result<Option<GithubRelease>, Box<dyn std::error::Error>> {
    if let Some(version) = config.manual_versions.get(&package.name) {
        return Ok(Some(GithubRelease {
            version: version.clone(),
            published_at: None,
        }));
    }

    match &package.latest {
        LatestSource::Manual => {
            if package_selected {
                log_info(&format!(
                    "Skipping {}: manifest requires --manual-version {}=<version>",
                    package.name, package.name
                ));
            }
            Ok(None)
        }
        LatestSource::GithubRelease {
            owner,
            repo,
            strip_prefix,
        } => {
            let min_age_days = (!config.ignore_cooldown && package.cooldown)
                .then(|| package.cooldown_days.unwrap_or(config.cooldown_days));
            match select_github_release(
                &package.name,
                owner,
                repo,
                strip_prefix.as_deref(),
                min_age_days,
            ) {
                Ok(release) => Ok(release),
                Err(err) => {
                    log_warn(&format!(
                        "Skipping {}: cannot query GitHub releases for {owner}/{repo}: {err}",
                        package.name
                    ));
                    Ok(None)
                }
            }
        }
    }
}

fn select_github_release(
    package_name: &str,
    owner: &str,
    repo: &str,
    strip_prefix: Option<&str>,
    min_age_days: Option<i64>,
) -> Result<Option<GithubRelease>, Box<dyn std::error::Error>> {
    let endpoint = format!("repos/{owner}/{repo}/releases?per_page=50");
    let output = github_api_get(&endpoint)?;
    let releases: Value = serde_json::from_str(&output.stdout)?;
    let releases = releases
        .as_array()
        .ok_or("GitHub releases response was not an array")?;

    let mut newest_non_prerelease: Option<GithubRelease> = None;
    for release in releases {
        if release
            .get("prerelease")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            continue;
        }

        let Some(candidate) = parse_github_release(release, strip_prefix)? else {
            continue;
        };

        if newest_non_prerelease.is_none() {
            newest_non_prerelease = Some(candidate.clone());
        }

        let Some(min_age_days) = min_age_days else {
            return Ok(Some(candidate));
        };

        let Some(published_at) = candidate.published_at else {
            continue;
        };
        let age_days = (Utc::now() - published_at).num_days();
        if age_days >= min_age_days {
            if let Some(latest) = &newest_non_prerelease {
                if latest.version != candidate.version {
                    let latest_age = latest
                        .published_at
                        .map(|date| (Utc::now() - date).num_days())
                        .map(|age| format!("{age}d old"))
                        .unwrap_or_else(|| "unknown age".to_string());
                    log_info(&format!(
                        "{package_name}: latest {} is {latest_age}; selecting cooldown-safe {} ({age_days}d old)",
                        latest.version, candidate.version
                    ));
                }
            }
            return Ok(Some(candidate));
        }
    }

    if let (Some(latest), Some(min_age_days)) = (newest_non_prerelease, min_age_days) {
        let latest_age = latest
            .published_at
            .map(|date| (Utc::now() - date).num_days())
            .map(|age| format!("{age}d old"))
            .unwrap_or_else(|| "unknown age".to_string());
        log_warn(&format!(
            "Skipping {package_name}: no release in the first 50 GitHub releases is at least {min_age_days}d old; latest {} is {latest_age}",
            latest.version
        ));
    } else {
        log_warn(&format!(
            "Skipping {package_name}: no non-prerelease GitHub releases found"
        ));
    }

    Ok(None)
}

fn github_api_get(endpoint: &str) -> Result<CommandOutput, Box<dyn std::error::Error>> {
    if let Ok(output) = run_capture("gh", ["api", endpoint]) {
        return Ok(output);
    }

    let url = format!("https://api.github.com/{endpoint}");
    let mut command = Command::new("curl");
    command.args(["-fsSL", "-H", "User-Agent: dotfiles-update-flakes"]);
    if let Ok(token) = env::var("GITHUB_TOKEN").or_else(|_| env::var("GH_TOKEN")) {
        command.args(["-H", &format!("Authorization: Bearer {token}")]);
    }
    command.arg(url);

    let output = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return Err(format!("curl failed with status {}\n{stderr}", output.status).into());
    }
    Ok(CommandOutput { stdout, stderr })
}

fn parse_github_release(
    release: &Value,
    strip_prefix: Option<&str>,
) -> Result<Option<GithubRelease>, Box<dyn std::error::Error>> {
    let Some(tag) = release.get("tag_name").and_then(Value::as_str) else {
        return Ok(None);
    };
    let version = strip_prefix
        .and_then(|prefix| tag.strip_prefix(prefix))
        .unwrap_or(tag)
        .to_string();
    let published_at = release
        .get("published_at")
        .and_then(Value::as_str)
        .and_then(|date| DateTime::parse_from_rfc3339(date).ok())
        .map(|date| date.with_timezone(&Utc));

    Ok(Some(GithubRelease {
        version,
        published_at,
    }))
}

fn prefetch_url(url: &str, unpack: bool) -> Result<String, Box<dyn std::error::Error>> {
    let mut args = vec!["store", "prefetch-file", "--json"];
    if unpack {
        args.push("--unpack");
    }
    args.push(url);
    let output = run_capture("nix", &args)?;
    let json: Value = serde_json::from_str(&output.stdout)?;
    let hash = json
        .get("hash")
        .and_then(Value::as_str)
        .ok_or("nix store prefetch-file output has no hash")?;
    Ok(hash.to_string())
}

fn extract_nix_string_attr(text: &str, attr: &str) -> Option<String> {
    let needle = format!("{attr} = \"");
    let start = text.find(&needle)? + needle.len();
    let end = text[start..].find('"')? + start;
    Some(text[start..end].to_string())
}

fn replace_nix_string_attr_once(
    text: &str,
    attr: &str,
    value: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    let needle = format!("{attr} = \"");
    let start = text
        .find(&needle)
        .ok_or_else(|| format!("could not find attr {attr}"))?
        + needle.len();
    let end = text[start..]
        .find('"')
        .ok_or_else(|| format!("could not find end quote for attr {attr}"))?
        + start;
    let mut out = String::with_capacity(text.len() + value.len());
    out.push_str(&text[..start]);
    out.push_str(value);
    out.push_str(&text[end..]);
    Ok(out)
}

fn replace_hash(
    text: &str,
    system: Option<&str>,
    hash: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    if let Some(system) = system {
        let block_start_marker = format!("{system} = {{");
        let block_start = text
            .find(&block_start_marker)
            .ok_or_else(|| format!("could not find asset block for {system}"))?;
        let rest = &text[block_start..];
        let hash_offset = rest
            .find("hash = \"")
            .ok_or_else(|| format!("could not find hash in asset block for {system}"))?;
        replace_hash_at(text, block_start + hash_offset, hash)
    } else {
        let hash_offset = text.find("hash = \"").ok_or("could not find source hash")?;
        replace_hash_at(text, hash_offset, hash)
    }
}

fn replace_hash_at(
    text: &str,
    hash_attr_start: usize,
    hash: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    let value_start = hash_attr_start + "hash = \"".len();
    let value_end = text[value_start..]
        .find('"')
        .ok_or("could not find end quote for hash")?
        + value_start;
    let mut out = String::with_capacity(text.len() + hash.len());
    out.push_str(&text[..value_start]);
    out.push_str(hash);
    out.push_str(&text[value_end..]);
    Ok(out)
}

fn absolutize(repo_root: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        repo_root.join(path)
    }
}

fn run_status<I, S>(
    program: &str,
    args: I,
    show_output: bool,
) -> Result<(), Box<dyn std::error::Error>>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let args = args
        .into_iter()
        .map(|arg| arg.as_ref().to_os_string())
        .collect::<Vec<OsString>>();

    if show_output {
        let status = Command::new(program).args(&args).status()?;
        if !status.success() {
            return Err(format!("{program} failed with status {status}").into());
        }
    } else {
        let output = Command::new(program)
            .args(&args)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()?;
        if !output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!(
                "{program} failed with status {}\nstdout:\n{}\nstderr:\n{}",
                output.status, stdout, stderr
            )
            .into());
        }
    }
    Ok(())
}

fn run_capture<I, S>(program: &str, args: I) -> Result<CommandOutput, Box<dyn std::error::Error>>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let output = Command::new(program)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return Err(format!("{program} failed with status {}\n{stderr}", output.status).into());
    }
    Ok(CommandOutput { stdout, stderr })
}

fn print_command_output(output: &CommandOutput) {
    print!("{}", output.stdout);
    eprint!("{}", output.stderr);
}

fn log_info(message: &str) {
    println!("\x1b[0;32m[INFO]\x1b[0m {message}");
}

fn log_warn(message: &str) {
    println!("\x1b[1;33m[WARN]\x1b[0m {message}");
}

fn log_error(message: &str) {
    eprintln!("\x1b[0;31m[ERROR]\x1b[0m {message}");
}

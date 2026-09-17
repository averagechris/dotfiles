use serde_json::Value;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn home(name: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!("bay-bin-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(root.join("bay")).unwrap();
    fs::write(
        root.join("bay/config.toml"),
        format!(
            "schema = 1\n[[groups]]\npath = {:?}\n[[groups]]\npath = {:?}\n",
            root.join("one").display().to_string(),
            root.join("two").display().to_string()
        ),
    )
    .unwrap();
    root
}

fn bay(home: &PathBuf) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_bay"));
    command.env("XDG_CONFIG_HOME", home);
    command
}

fn init_repo(path: &PathBuf) {
    fs::create_dir_all(path).unwrap();
    let status = Command::new("jj")
        .args(["git", "init", path.to_str().unwrap()])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
fn device_json_from_non_repo_is_clean_and_stable() {
    let home = home("list");
    let output = bay(&home)
        .current_dir(&home)
        .args(["list", "--json"])
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["schema"], 1);
    assert_eq!(value["workspaces"], serde_json::json!([]));
}

#[test]
fn not_found_uses_stderr_and_documented_exit_code() {
    let home = home("errors");
    let output = bay(&home)
        .current_dir(&home)
        .args(["path", "missing", "--json"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(3));
    assert!(output.stdout.is_empty());
    let value: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(value["schema"], 1);
    assert_eq!(value["error"]["code"], "not_found");
    assert!(value["error"].get("details").is_none());
}

#[test]
fn jj_ws_empty_invocation_preserves_success_and_usage() {
    let home = home("local");
    let output=Command::new(env!("CARGO_BIN_EXE_jj-workflow")).env("XDG_CONFIG_HOME",home).arg("ws").output().unwrap();
    assert!(output.status.success());assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).starts_with("Usage:\n  jj ws add"));
}

#[test]
fn jj_ws_unknown_command_preserves_error_prefix_and_exit(){let output=Command::new(env!("CARGO_BIN_EXE_jj-workflow")).args(["ws","nope"]).output().unwrap();assert_eq!(output.status.code(),Some(1));assert!(String::from_utf8_lossy(&output.stderr).starts_with("Error: unknown ws subcommand: nope"));}

#[test]
fn revision_before_name_is_not_misparsed_as_the_name() {
    let home = home("option-first");
    let output = bay(&home)
        .current_dir(&home)
        .args(["add", "-r", "@", "repo/topic", "--json"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(3));
    let value: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(value["error"]["code"], "not_a_repo");
}

#[test]
fn gc_requires_a_repository_outside_managed_repos() {
    let home = home("gc-no-repo");
    let output = bay(&home)
        .current_dir("/")
        .args(["gc", "--dry-run"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("requires REPO"));
}

#[test]
fn maintenance_is_scoped_to_the_selected_repository() {
    let home = home("maintenance-scope");
    let one = home.join("one/alpha");
    let two = home.join("two/beta");
    init_repo(&one);
    init_repo(&two);

    let alpha_root = bay(&home)
        .current_dir(&home)
        .args(["root", "alpha"])
        .output()
        .unwrap();
    let beta_root = bay(&home)
        .current_dir(&home)
        .args(["root", "beta"])
        .output()
        .unwrap();
    assert!(alpha_root.status.success());
    assert!(beta_root.status.success());
    let alpha_trash = PathBuf::from(String::from_utf8(alpha_root.stdout).unwrap().trim())
        .join(".trash/0-alpha-old");
    let beta_trash = PathBuf::from(String::from_utf8(beta_root.stdout).unwrap().trim())
        .join(".trash/0-beta-old");
    fs::create_dir_all(&alpha_trash).unwrap();
    fs::create_dir_all(&beta_trash).unwrap();

    let output = bay(&home)
        .current_dir(&home)
        .args(["gc", "alpha", "--older-than", "0h", "--dry-run"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("alpha-old"));
    assert!(!stdout.contains("beta-old"));
    assert!(alpha_trash.exists());
    assert!(beta_trash.exists());

    for repo in ["alpha", "beta"] {
        let output = bay(&home)
            .current_dir(&home)
            .args(["add", &format!("{repo}/work"), "-r", "@", "-q"])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let alpha_work = home.join("one/ws/alpha/work");
    let beta_work = home.join("two/ws/beta/work");
    fs::create_dir_all(alpha_work.join("target")).unwrap();
    fs::create_dir_all(beta_work.join("target")).unwrap();
    fs::write(alpha_work.join("target/artifact"), "alpha").unwrap();
    fs::write(beta_work.join("target/artifact"), "beta").unwrap();

    let output = bay(&home)
        .current_dir(&home)
        .args(["sweep", "alpha", "--idle", "0h", "--dry-run"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains(alpha_work.to_str().unwrap()), "{stdout}");
    assert!(!stdout.contains(beta_work.to_str().unwrap()));
    assert!(alpha_work.join("target/artifact").exists());
    assert!(beta_work.join("target/artifact").exists());
}

fn counting_path(home:&PathBuf)->(String,PathBuf){let real=which::which("jj").unwrap();let bin=home.join("counter-bin");fs::create_dir_all(&bin).unwrap();let count=home.join("query-count");fs::write(bin.join("jj"),format!("#!/bin/sh\nprintf '%s\\n' \"$*\" | grep -q 'workspace list' && echo x >> {:?}\nexec {:?} \"$@\"\n",count,real)).unwrap();#[cfg(unix)]{use std::os::unix::fs::PermissionsExt;fs::set_permissions(bin.join("jj"),fs::Permissions::from_mode(0o755)).unwrap();}(format!("{}:{}",bin.display(),std::env::var("PATH").unwrap()),count)}
fn query_count(path:&PathBuf)->usize{fs::read_to_string(path).unwrap_or_default().lines().count()}

#[test]
fn absolute_repo_selection_queries_only_selected_store(){let home=home("absolute-target");let root=home.join("one/alpha");init_repo(&root);init_repo(&home.join("two/beta"));let(path,count)=counting_path(&home);let output=bay(&home).env("PATH",path).args(["list",root.to_str().unwrap(),"--json"]).output().unwrap();assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));assert_eq!(query_count(&count),1);}

#[test]
fn basename_selection_does_not_query_unrelated_repositories(){let home=home("basename-target");init_repo(&home.join("one/alpha"));init_repo(&home.join("one/beta"));init_repo(&home.join("two/alpha"));let(path,count)=counting_path(&home);let output=bay(&home).env("PATH",path).args(["list","alpha","--json"]).output().unwrap();assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));assert_eq!(query_count(&count),2);let value:Value=serde_json::from_slice(&output.stdout).unwrap();assert!(value["workspaces"].as_array().unwrap().iter().all(|record|record["repo"]=="alpha"));}

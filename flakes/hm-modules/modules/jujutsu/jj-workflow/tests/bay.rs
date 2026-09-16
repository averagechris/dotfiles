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

fn init_repo(home: &PathBuf, group: &str, repo: &str, workspace: &str) -> PathBuf {
    let root=home.join(group).join(repo);fs::create_dir_all(&root).unwrap();
    assert!(Command::new("jj").current_dir(&root).args(["git","init"]).status().unwrap().success());
    let dest=home.join(group).join("ws").join(repo).join(workspace);fs::create_dir_all(dest.parent().unwrap()).unwrap();
    assert!(Command::new("jj").current_dir(&root).args(["workspace","add","--name",workspace,dest.to_str().unwrap()]).status().unwrap().success());
    root
}

#[test]
fn device_json_from_non_repo_is_clean_and_stable() {
    let home = home("list");
    let output = bay(&home).current_dir(&home).args(["list", "--json"]).output().unwrap();
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["schema"], 1);
    assert_eq!(value["workspaces"], serde_json::json!([]));
}

#[test]
fn not_found_uses_stderr_and_documented_exit_code() {
    let home = home("errors");
    let output = bay(&home).current_dir(&home).args(["path", "missing", "--json"]).output().unwrap();
    assert_eq!(output.status.code(), Some(3));
    assert!(output.stdout.is_empty());
    let value: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(value["schema"], 1);
    assert_eq!(value["error"]["code"], "not_found");
}

#[test]
fn jj_ws_empty_invocation_preserves_success_and_usage() {
    let home = home("local");
    let output = Command::new(env!("CARGO_BIN_EXE_jj-workflow")).env("XDG_CONFIG_HOME",home).arg("ws").output().unwrap();
    assert!(output.status.success());
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).starts_with("Usage:\n  jj ws add"));
}

#[test]
fn jj_ws_unknown_command_preserves_error_prefix_and_exit() {
    let output = Command::new(env!("CARGO_BIN_EXE_jj-workflow")).args(["ws","nope"]).output().unwrap();
    assert_eq!(output.status.code(),Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).starts_with("Error: unknown ws subcommand: nope"));
}

#[test]
fn revision_before_name_is_not_misparsed_as_the_name() {
    let home = home("option-first");
    let output = bay(&home).current_dir(&home).args(["add", "-r", "@", "repo/topic", "--json"]).output().unwrap();
    assert_eq!(output.status.code(), Some(3));
    let value: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(value["error"]["code"], "not_a_repo");
}

#[test]
fn ambiguous_selector_reports_candidates_on_stderr() {
    let home=home("ambiguous");init_repo(&home,"one","alpha","shared");init_repo(&home,"two","beta","shared");
    let output=bay(&home).current_dir(&home).args(["path","shared","--json"]).output().unwrap();
    assert_eq!(output.status.code(),Some(3));assert!(output.stdout.is_empty());
    let value:Value=serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(value["error"]["code"],"ambiguous");assert_eq!(value["error"]["candidates"].as_array().unwrap().len(),2);
}

#[test]
fn duplicate_workspace_anchors_query_registry_once() {
    let home=home("dedupe");init_repo(&home,"one","alpha","shared");
    let real=which::which("jj").unwrap();let bin=home.join("bin");fs::create_dir_all(&bin).unwrap();let count=home.join("count");
    fs::write(bin.join("jj"),format!("#!/bin/sh\nprintf '%s\\n' \"$*\" | grep -q 'workspace list' && echo x >> {:?}\nexec {:?} \"$@\"\n",count,real)).unwrap();
    #[cfg(unix)] { use std::os::unix::fs::PermissionsExt;fs::set_permissions(bin.join("jj"),fs::Permissions::from_mode(0o755)).unwrap(); }
    let old=std::env::var("PATH").unwrap();let output=bay(&home).env("PATH",format!("{}:{old}",bin.display())).args(["list","--json"]).output().unwrap();assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));let value:Value=serde_json::from_slice(&output.stdout).unwrap();let repos:std::collections::HashSet<_>=value["workspaces"].as_array().unwrap().iter().map(|record|record["repo"].as_str().unwrap()).collect();assert_eq!(repos.len(),1);assert_eq!(repos.into_iter().next(),Some("alpha"));
    assert_eq!(fs::read_to_string(count).unwrap().lines().count(),1);
}

fn counting_path(home:&PathBuf)->(String,PathBuf){let real=which::which("jj").unwrap();let bin=home.join("counter-bin");fs::create_dir_all(&bin).unwrap();let count=home.join("query-count");fs::write(bin.join("jj"),format!("#!/bin/sh\nprintf '%s\\n' \"$*\" | grep -q 'workspace list' && echo x >> {:?}\nexec {:?} \"$@\"\n",count,real)).unwrap();#[cfg(unix)]{use std::os::unix::fs::PermissionsExt;fs::set_permissions(bin.join("jj"),fs::Permissions::from_mode(0o755)).unwrap();}(format!("{}:{}",bin.display(),std::env::var("PATH").unwrap()),count)}
fn query_count(path:&PathBuf)->usize{fs::read_to_string(path).unwrap_or_default().lines().count()}

#[test]
fn absolute_repo_selection_queries_only_selected_store(){let home=home("absolute-target");let root=init_repo(&home,"one","alpha","shared");init_repo(&home,"two","beta","other");let(path,count)=counting_path(&home);let output=bay(&home).env("PATH",path).args(["list",root.to_str().unwrap(),"--json"]).output().unwrap();assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));assert_eq!(query_count(&count),1);}

#[test]
fn basename_selection_does_not_query_unrelated_repositories(){let home=home("basename-target");init_repo(&home,"one","alpha","shared");init_repo(&home,"one","beta","other");init_repo(&home,"two","alpha","second");let(path,count)=counting_path(&home);let output=bay(&home).env("PATH",path).args(["list","alpha","--json"]).output().unwrap();assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));assert_eq!(query_count(&count),2);let value:Value=serde_json::from_slice(&output.stdout).unwrap();assert!(value["workspaces"].as_array().unwrap().iter().all(|record|record["repo"]=="alpha"));}

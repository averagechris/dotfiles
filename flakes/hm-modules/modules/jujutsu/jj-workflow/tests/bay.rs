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

fn fake_gh(home: &PathBuf) -> (String, PathBuf) {
    let bin=home.join("fake-gh-bin"); fs::create_dir_all(&bin).unwrap();
    let log=home.join("gh-log");
    fs::write(bin.join("gh"),format!("#!/bin/sh\nprintf 'prompt=%s\\n' \"$GH_PROMPT_DISABLED\" > {:?}\nprintf '%s\\n' \"$*\" >> {:?}\nprintf '%s' \"$GH_RESPONSE\"\n",log,log)).unwrap();
    #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; fs::set_permissions(bin.join("gh"),fs::Permissions::from_mode(0o755)).unwrap(); }
    (format!("{}:{}",bin.display(),std::env::var("PATH").unwrap()),log)
}

fn clone_fixture(name:&str)->(PathBuf,String,PathBuf) {
    let h=find_home(name); let source=h.join("source"); init_repo(&source);
    let (path,_)=fake_gh(&h);
    let response=serde_json::json!({"nameWithOwner":"SureApp/api","owner":{"login":"SureApp"},"name":"api","url":source,"sshUrl":source,"defaultBranchRef":null,"isArchived":false,"isPrivate":false,"visibility":"PUBLIC","viewerPermission":"READ"}).to_string();
    (h,path,PathBuf::from(response))
}

fn find_home(name:&str)->PathBuf {
    let h=home(name);
    fs::create_dir_all(h.join("one")).unwrap();
    fs::write(h.join("bay/config.toml"),format!("schema = 1\n[[groups]]\npath = {:?}\ngithub-owners = [\"SureApp\"]\n[[groups]]\npath = {:?}\ngithub-owners = [\"*\"]\n",h.join("one").display().to_string(),h.join("two").display().to_string())).unwrap();
    h
}

#[test]
fn repo_find_search_uses_stable_gh_contract_and_no_prompt() {
    let h=find_home("repo-search"); let (path,log)=fake_gh(&h);
    let response=r#"[{"fullName":"SureApp/api","description":"API","url":"https://github.com/SureApp/api","isArchived":false,"isPrivate":true,"updatedAt":"2026-01-02T03:04:05Z"}]"#;
    let out=bay(&h).env("PATH",path).env("GH_RESPONSE",response).args(["repo","find","insurance","--owner","SureApp","--limit","7","--json"]).output().unwrap();
    assert!(out.status.success(),"{}",String::from_utf8_lossy(&out.stderr));
    let value:Value=serde_json::from_slice(&out.stdout).unwrap(); assert_eq!(value["schema"],1); assert_eq!(value["query"],"insurance"); assert_eq!(value["repos"][0]["group"],h.join("one").display().to_string()); assert!(value["repos"][0]["local"].is_null());
    let invocation=fs::read_to_string(log).unwrap(); assert!(invocation.contains("prompt=1")); assert!(invocation.contains("search repos insurance --limit 7 --json fullName,description,url,isArchived,isPrivate,updatedAt --owner SureApp"));
}

#[test]
fn exact_url_uses_view_and_reports_present_or_foreign_without_writes() {
    let h=find_home("repo-exact"); let repo=h.join("one/api"); init_repo(&repo);
    assert!(Command::new("jj").current_dir(&repo).args(["git","remote","add","origin","git@github.com:sureapp/API.git"]).status().unwrap().success());
    let (path,log)=fake_gh(&h); let response=r#"{"nameWithOwner":"SureApp/api","description":null,"url":"https://github.com/SureApp/api","isArchived":true,"isPrivate":false,"updatedAt":"2026-01-02T03:04:05Z"}"#;
    let marker=repo.join("untouched"); fs::write(&marker,"keep").unwrap();
    let out=bay(&h).env("PATH",path.clone()).env("GH_RESPONSE",response).args(["repo","find","https://github.com/SureApp/api/issues/9","--json"]).output().unwrap();
    assert!(out.status.success(),"{}",String::from_utf8_lossy(&out.stderr)); let value:Value=serde_json::from_slice(&out.stdout).unwrap(); assert_eq!(value["repos"][0]["local"]["status"],"present"); assert_eq!(fs::read_to_string(&marker).unwrap(),"keep"); assert!(fs::read_to_string(&log).unwrap().contains("repo view SureApp/api --json"));
    assert!(Command::new("jj").current_dir(&repo).args(["git","remote","set-url","origin","https://github.com/Other/api"]).status().unwrap().success());
    let out=bay(&h).env("PATH",path).env("GH_RESPONSE",response).args(["repo","find","SureApp/api.git","--json"]).output().unwrap(); let value:Value=serde_json::from_slice(&out.stdout).unwrap(); assert_eq!(value["repos"][0]["local"]["status"],"foreign");
}


#[test]
fn repo_clone_is_real_clean_and_idempotent_including_empty_destination() {
    let (h,path,response)=clone_fixture("clone-real"); let dest=h.join("one/api"); fs::create_dir_all(&dest).unwrap();
    let first=bay(&h).env("PATH",&path).env("GH_RESPONSE",response.as_os_str()).args(["repo","clone","SureApp/api","--json"]).output().unwrap();
    assert!(first.status.success(),"{}",String::from_utf8_lossy(&first.stderr));
    let value:Value=serde_json::from_slice(&first.stdout).unwrap(); assert_eq!(value["repo"]["status"],"cloned"); assert!(dest.join(".jj").exists()); assert!(dest.join(".git").exists());
    let before=fs::metadata(&dest).unwrap().modified().unwrap();
    let second=bay(&h).env("PATH",path).env("GH_RESPONSE",response.as_os_str()).args(["repo","clone","SureApp/api","--json"]).output().unwrap();
    assert!(second.status.success(),"{}",String::from_utf8_lossy(&second.stderr)); assert!(second.stderr.is_empty());
    assert_eq!(serde_json::from_slice::<Value>(&second.stdout).unwrap()["repo"]["status"],"exists"); assert_eq!(fs::metadata(&dest).unwrap().modified().unwrap(),before);
}

#[cfg(unix)]
#[test]
fn repo_clone_refuses_destination_symlink_without_outside_writes() {
    use std::os::unix::fs::symlink;
    let (h,path,response)=clone_fixture("clone-symlink"); let outside=h.join("outside"); fs::create_dir_all(&outside).unwrap(); symlink(&outside,h.join("one/api")).unwrap();
    let out=bay(&h).env("PATH",path).env("GH_RESPONSE",response.as_os_str()).args(["repo","clone","SureApp/api","--json"]).output().unwrap();
    assert_eq!(out.status.code(),Some(3)); assert!(out.stdout.is_empty()); assert_eq!(serde_json::from_slice::<Value>(&out.stderr).unwrap()["error"]["code"],"collision"); assert_eq!(fs::read_dir(outside).unwrap().count(),0);
}

#[test]
fn repo_clone_collisions_leave_existing_contents_untouched() {
    for (suffix,repo) in [("file",false),("foreign",true)] {
        let (h,path,response)=clone_fixture(&format!("clone-collision-{suffix}")); let dest=h.join("one/api");
        if repo { init_repo(&dest); assert!(Command::new("jj").current_dir(&dest).args(["git","remote","add","origin","https://github.com/Other/api.git"]).status().unwrap().success()); }
        else { fs::create_dir_all(&dest).unwrap(); }
        let marker=dest.join("keep"); fs::write(&marker,"untouched").unwrap();
        let out=bay(&h).env("PATH",path).env("GH_RESPONSE",response.as_os_str()).args(["repo","clone","SureApp/api","--json"]).output().unwrap();
        assert_eq!(out.status.code(),Some(3)); assert!(out.stdout.is_empty()); let error:Value=serde_json::from_slice(&out.stderr).unwrap(); assert_eq!(error["error"]["code"],"collision"); assert_eq!(error["error"]["details"]["path"],dest.display().to_string()); assert_eq!(fs::read_to_string(marker).unwrap(),"untouched");
    }
}

#[test]
fn concurrent_identical_clones_serialize_to_cloned_then_exists() {
    let (h,path,response)=clone_fixture("clone-concurrent");
    let spawn=|| bay(&h).env("PATH",&path).env("GH_RESPONSE",response.as_os_str()).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).args(["repo","clone","SureApp/api","--json"]).spawn().unwrap();
    let a=spawn(); let b=spawn(); let outputs=[a.wait_with_output().unwrap(),b.wait_with_output().unwrap()];
    assert!(outputs.iter().all(|o|o.status.success()),"{:?}",outputs.iter().map(|o|String::from_utf8_lossy(&o.stderr)).collect::<Vec<_>>());
    let mut statuses=outputs.iter().map(|o|serde_json::from_slice::<Value>(&o.stdout).unwrap()["repo"]["status"].as_str().unwrap().to_owned()).collect::<Vec<_>>(); statuses.sort(); assert_eq!(statuses,["cloned","exists"]);
}

#[cfg(unix)]
fn paused_clone(h:&PathBuf,path:&str,response:&PathBuf)->(std::process::Child,PathBuf,PathBuf) {
    use std::os::unix::fs::PermissionsExt;
    let bin=h.join("fake-gh-bin"); let ready=h.join("clone-ready"); let invocations=h.join("jj-invocations");
    fs::write(bin.join("jj"),format!("#!/bin/sh\necho x >> {:?}\ntouch {:?}\nsleep 30\n",invocations,ready)).unwrap(); fs::set_permissions(bin.join("jj"),fs::Permissions::from_mode(0o755)).unwrap();
    let child=bay(h).env("PATH",path).env("GH_RESPONSE",response.as_os_str()).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).args(["repo","clone","SureApp/api","--json"]).spawn().unwrap();
    for _ in 0..100 { if ready.exists(){return (child,ready,invocations)} std::thread::sleep(std::time::Duration::from_millis(20)); }
    panic!("clone did not reach transport");
}

#[cfg(unix)]
#[test]
fn killed_lock_owner_releases_advisory_lock_for_immediate_retry() {
    let (h,path,response)=clone_fixture("clone-killed-owner"); let (mut owner,_,_)=paused_clone(&h,&path,&response); owner.kill().unwrap(); owner.wait().unwrap(); fs::remove_file(h.join("fake-gh-bin/jj")).unwrap(); let started=std::time::Instant::now();
    let out=bay(&h).env("PATH",path).env("GH_RESPONSE",response.as_os_str()).args(["repo","clone","SureApp/api","--json"]).output().unwrap();
    assert!(out.status.success(),"{}",String::from_utf8_lossy(&out.stderr)); assert!(started.elapsed()<std::time::Duration::from_secs(5)); assert_eq!(serde_json::from_slice::<Value>(&out.stdout).unwrap()["repo"]["status"],"cloned");
}

#[cfg(unix)]
#[test]
fn waiter_rechecks_destination_after_lock_and_refuses_installed_symlink() {
    use std::os::unix::fs::symlink;
    let (h,path,response)=clone_fixture("clone-waiter-symlink"); let (mut owner,_,invocations)=paused_clone(&h,&path,&response);
    let waiter=bay(&h).env("PATH",&path).env("GH_RESPONSE",response.as_os_str()).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).args(["repo","clone","SureApp/api","--json"]).spawn().unwrap();
    std::thread::sleep(std::time::Duration::from_millis(100)); let destination=h.join("one/api"); let outside=h.join("outside"); fs::remove_dir(&destination).unwrap(); fs::create_dir(&outside).unwrap(); symlink(&outside,&destination).unwrap();
    owner.kill().unwrap(); owner.wait().unwrap(); let started=std::time::Instant::now(); let out=waiter.wait_with_output().unwrap();
    assert!(started.elapsed()<std::time::Duration::from_secs(5)); assert_eq!(out.status.code(),Some(3)); assert_eq!(serde_json::from_slice::<Value>(&out.stderr).unwrap()["error"]["code"],"collision"); assert_eq!(fs::read_to_string(invocations).unwrap().lines().count(),1); assert_eq!(fs::read_dir(outside).unwrap().count(),0);
}

#[cfg(unix)]
#[test]
fn lock_file_symlink_never_creates_external_target() {
    use std::os::unix::fs::symlink;
    let (h,path,response)=clone_fixture("clone-lock-symlink"); let first=bay(&h).env("PATH",&path).env("GH_RESPONSE",response.as_os_str()).args(["repo","clone","SureApp/api","--json"]).output().unwrap(); assert!(first.status.success());
    let lock_dir=h.join("one/.bay-clone-locks"); let lock=fs::read_dir(&lock_dir).unwrap().next().unwrap().unwrap().path(); fs::remove_file(&lock).unwrap(); let outside=h.join("must-not-be-created"); symlink(&outside,&lock).unwrap();
    let out=bay(&h).env("PATH",path).env("GH_RESPONSE",response.as_os_str()).args(["repo","clone","SureApp/api","--json"]).output().unwrap(); assert_eq!(out.status.code(),Some(3)); assert!(!outside.exists());
}

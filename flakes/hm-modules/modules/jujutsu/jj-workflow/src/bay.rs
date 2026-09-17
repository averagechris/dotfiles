//! Device-wide facade for the repository-local workspace operations.
use crate::bay_repo::{github_slug, route_group};
use crate::ws::{discover_workspaces, run_ws, ws_config, ProjectGroup, WorkspaceKind, WsConfig};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{BTreeMap, HashSet};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::fs::OpenOptions;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

#[cfg(not(unix))]
compile_error!("bay repository clone locking requires Unix openat/O_NOFOLLOW support");

#[derive(Clone, Debug, Serialize)]
struct Record {
    name: String,
    path: Option<PathBuf>,
    repo: Option<String>,
    main: Option<PathBuf>,
    group: Option<PathBuf>,
    kind: &'static str,
    managed: bool,
    #[serde(skip)]
    anchor: PathBuf,
}

#[derive(Debug)]
struct BayError {
    code: i32,
    kind: &'static str,
    message: String,
    candidates: Vec<Record>,
    details: Option<serde_json::Value>,
}
type Result<T> = std::result::Result<T, BayError>;
fn err(code: i32, kind: &'static str, message: impl Into<String>) -> BayError {
    BayError {
        code,
        kind,
        message: message.into(),
        candidates: vec![],
        details: None,
    }
}

pub fn run_cli() -> i32 {
    let args: Vec<OsString> = env::args_os().skip(1).collect();
    let json_mode = args.iter().any(|a| a == "--json");
    match run(args) {
        Ok(()) => 0,
        Err(e) => {
            if json_mode {
                let mut error = json!({"code":e.kind,"message":e.message,"candidates":e.candidates});
                if let Some(details) = e.details { error["details"] = details; }
                eprintln!("{}", json!({"schema":1,"error":error}));
            } else {
                eprintln!("bay: {}", e.message);
                for c in e.candidates {
                    eprintln!(
                        "  {}/{}\t{}",
                        c.repo.unwrap_or_default(),
                        c.name,
                        c.path
                            .map(|p| p.display().to_string())
                            .unwrap_or_else(|| "<missing>".into())
                    );
                }
            }
            e.code
        }
    }
}

fn run(mut args: Vec<OsString>) -> Result<()> {
    if args.is_empty() {
        return Err(err(2, "usage", usage()));
    }
    let sub = args.remove(0).to_string_lossy().into_owned();
    if !matches!(sub.as_str(), "list" | "ls" | "repo") { args.retain(|arg| arg != "--json"); }
    match sub.as_str() {
        "list" | "ls" => list(args),
        "path" => path(args),
        "root" => root(args),
        "add" => add(args),
        "rm" | "forget" => remove(args),
        "repo" => repo(args),
        "prune" | "gc" | "du" | "sweep" => maintenance(&sub, args),
        "-h" | "--help" | "help" => {
            println!("{}", usage());
            Ok(())
        }
        _ => Err(err(
            2,
            "usage",
            format!("unknown command {sub:?}\n{}", usage()),
        )),
    }
}
fn usage() -> &'static str {
    "Usage: bay list|ls [REPO] [--json]\n       bay repo find <query> [--owner LOGIN] [--limit N] [--json]\n       bay repo clone <input> [--group PATH] [--as NAME] [--protocol ssh|https] [--depth N] [--json]\n       bay path <selector>\n       bay root [REPO]\n       bay add [<repo>/]<name> [-r REV] [--repo PATH] [--at DIR] [--json]\n       bay rm|forget <selector> [jj ws forget options]\n       bay prune [REPO] [--dry-run] [--delete] [--pick] [--yes]\n       bay gc [REPO] [--older-than DUR] [--dry-run]\n       bay du [REPO]\n       bay sweep [REPO] [--idle DUR] [--dry-run]"
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GhRepo {
    #[serde(alias = "fullName")]
    name_with_owner: String,
    description: Option<String>,
    url: String,
    is_archived: bool,
    is_private: bool,
    updated_at: String,
}

#[derive(Serialize)]
struct FoundLocal { path: PathBuf, status: &'static str }
#[derive(Serialize)]
struct FoundRepo {
    slug: String, owner: String, name: String, description: Option<String>, url: String,
    archived: bool, private: bool, updated_at: String, group: Option<PathBuf>, local: Option<FoundLocal>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CloneGhRepo {
    name_with_owner: String,
    owner: GhOwner,
    name: String,
    url: String,
    ssh_url: String,
    default_branch_ref: Option<GhBranch>,
    is_archived: bool,
    is_private: bool,
    visibility: String,
    viewer_permission: Option<String>,
}
#[derive(Debug, Deserialize)] struct GhOwner { login: String }
#[derive(Debug, Deserialize)] struct GhBranch { name: String }
#[derive(Serialize)] struct ClonedRepo<'a> {
    slug: &'a str, owner: &'a str, name: &'a str, url: &'a str, clone_url: &'a str,
    protocol: &'a str, group: &'a Path, path: &'a Path, status: &'a str,
    default_branch: Option<&'a str>, archived: bool, private: bool,
}

fn repo(mut args: Vec<OsString>) -> Result<()> {
    if args.first().is_some_and(|arg| arg == "clone") {
        args.remove(0);
        return repo_clone(args);
    }
    if args.first().is_none_or(|arg| arg != "find") {
        return Err(err(2, "usage", "usage: bay repo find <query> [--owner LOGIN] [--limit N] [--json]\n       bay repo clone <input> [--group PATH] [--as NAME] [--protocol ssh|https] [--depth N] [--json]"));
    }
    args.remove(0);
    let json_out = take_flag(&mut args, "--json");
    let mut owner = None;
    let mut limit = 20usize;
    let mut query = None;
    let mut i = 0;
    while i < args.len() {
        let value = args[i].to_string_lossy();
        if value == "--owner" || value == "--limit" {
            if i + 1 >= args.len() { return Err(err(2, "usage", format!("missing value for {value}"))); }
            let flag = args.remove(i); let raw = args.remove(i).to_string_lossy().into_owned();
            if flag == "--owner" { owner = Some(raw); }
            else { limit = raw.parse().ok().filter(|n| *n > 0).ok_or_else(|| err(2,"usage","--limit must be a positive integer"))?; }
        } else if value.starts_with('-') || query.replace(value.into_owned()).is_some() {
            return Err(err(2, "usage", "unexpected argument to bay repo find"));
        } else { i += 1; }
    }
    let query = query.ok_or_else(|| err(2,"usage","bay repo find requires a query"))?;
    let exact = github_slug(&query);
    if (query.contains('/') || query.contains("://") || query.contains('@')) && exact.is_none() {
        return Err(err(2, "usage", format!("invalid GitHub repository {query:?}")));
    }
    let fields = "nameWithOwner,description,url,isArchived,isPrivate,updatedAt";
    let mut command = Command::new("gh");
    command.env("GH_PROMPT_DISABLED", "1");
    if let Some((ref owner, ref name)) = exact {
        command.args(["repo","view",&format!("{owner}/{name}"),"--json",fields]);
    } else {
        command.args(["search","repos",&query,"--limit",&limit.to_string(),"--json","fullName,description,url,isArchived,isPrivate,updatedAt"]);
        if let Some(ref owner) = owner { command.args(["--owner", owner]); }
    }
    let output = command.output().map_err(|e| err(1,"gh_unavailable",format!("cannot run gh: {e}")))?;
    if !output.status.success() {
        let message = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let lower = message.to_ascii_lowercase();
        if exact.is_some() && (lower.contains("could not resolve") || lower.contains("not found")) { return Err(err(3,"not_found",message)); }
        let kind = if lower.contains("auth") || lower.contains("login") || lower.contains("token") { "gh_auth" } else { "gh_failed" };
        return Err(err(1,kind,message));
    }
    let mut raw: Vec<GhRepo> = if exact.is_some() {
        vec![serde_json::from_slice(&output.stdout).map_err(|e| err(1,"gh_failed",format!("invalid gh response: {e}")))?]
    } else { serde_json::from_slice(&output.stdout).map_err(|e| err(1,"gh_failed",format!("invalid gh response: {e}")))? };
    raw.sort_by_key(|r| r.name_with_owner.to_ascii_lowercase());
    raw.dedup_by(|a,b| a.name_with_owner.eq_ignore_ascii_case(&b.name_with_owner));
    let cfg = ws_config().map_err(config_err)?;
    let repos: Vec<_> = raw.into_iter().filter_map(|r| {
        let (repo_owner,name)=r.name_with_owner.split_once('/')?;
        let group=route_group(&cfg.project_groups,None,Some(repo_owner)).ok();
        let local=group.and_then(|g| local_identity(&g.path.join(name),repo_owner,name));
        Some(FoundRepo{slug:format!("{repo_owner}/{name}"),owner:repo_owner.into(),name:name.into(),description:r.description,url:r.url,archived:r.is_archived,private:r.is_private,updated_at:r.updated_at,group:group.map(|g|g.path.clone()),local})
    }).collect();
    if json_out { println!("{}",json!({"schema":1,"query":query,"repos":repos})); }
    else {
        println!("SLUG\tGROUP\tLOCAL\tDESCRIPTION");
        for r in repos { println!("{}{}\t{}\t{}\t{}",r.slug,if r.archived{" [archived]"}else{""},r.group.as_ref().map_or("-".into(),|p|p.display().to_string()),r.local.as_ref().map_or("absent",|l|l.status),r.description.unwrap_or_default().replace(['\t','\n']," ")); }
    }
    Ok(())
}

fn repo_clone(mut args: Vec<OsString>) -> Result<()> {
    let json_out = take_flag(&mut args, "--json");
    let mut input = None;
    let mut group = None;
    let mut alias = None;
    let mut protocol = None;
    let mut depth = None;
    let mut i = 0;
    while i < args.len() {
        let value = args[i].to_string_lossy().into_owned();
        if matches!(value.as_str(), "--group" | "--as" | "--protocol" | "--depth") {
            if i + 1 >= args.len() { return Err(err(2,"usage",format!("missing value for {value}"))); }
            args.remove(i); let raw=args.remove(i).to_string_lossy().into_owned();
            match value.as_str() {
                "--group" => group=Some(PathBuf::from(raw)),
                "--as" => alias=Some(raw),
                "--protocol" if matches!(raw.as_str(),"ssh"|"https") => protocol=Some(raw),
                "--protocol" => return Err(err(2,"usage","--protocol must be ssh or https")),
                "--depth" => { raw.parse::<usize>().ok().filter(|n|*n>0).ok_or_else(||err(2,"usage","--depth must be a positive integer"))?; depth=Some(raw); },
                _ => unreachable!(),
            }
        } else if value.starts_with('-') || input.replace(value).is_some() {
            return Err(err(2,"usage","unexpected argument to bay repo clone"));
        } else { i += 1; }
    }
    let input=input.ok_or_else(||err(2,"usage","bay repo clone requires an input"))?;
    let (requested_owner,requested_name)=github_slug(&input).ok_or_else(||err(2,"usage",format!("invalid GitHub repository {input:?}")))?;
    if let Some(name)=alias.as_deref() {
        let valid=!name.starts_with('.') && !name.is_empty() && name != "." && name != ".." && !name.contains(['/', '\\']);
        if !valid { return Err(err(2,"usage","--as must be a basename and may not start with a dot")); }
    }
    let fields="nameWithOwner,owner,name,url,sshUrl,defaultBranchRef,isArchived,isPrivate,visibility,viewerPermission";
    let output=Command::new("gh").env("GH_PROMPT_DISABLED","1").args(["repo","view",&format!("{requested_owner}/{requested_name}"),"--json",fields]).output()
        .map_err(|e|err(1,"gh_unavailable",format!("cannot run gh: {e}")))?;
    if !output.status.success() {
        let message=String::from_utf8_lossy(&output.stderr).trim().to_string(); let lower=message.to_ascii_lowercase();
        if lower.contains("could not resolve") || lower.contains("not found") { return Err(err(3,"not_found",message)); }
        let kind=if lower.contains("auth")||lower.contains("login")||lower.contains("token"){"gh_auth"}else{"gh_failed"};
        return Err(err(1,kind,message));
    }
    let metadata:CloneGhRepo=serde_json::from_slice(&output.stdout).map_err(|e|err(1,"gh_failed",format!("invalid gh response: {e}")))?;
    let cfg=ws_config().map_err(config_err)?;
    let selected=route_group(&cfg.project_groups,group.as_deref(),Some(&metadata.owner.login))
        .map_err(|e|err(e.exit_code(),e.kind(),"no configured project group matches this repository"))?;
    let basename=alias.as_deref().unwrap_or(&metadata.name);
    let group_path=fs::canonicalize(&selected.path).map_err(|e|err(3,"no_group",format!("cannot access configured group {}: {e}",selected.path.display())))?;
    if !group_path.is_dir() { return Err(err(3,"no_group",format!("configured group is not a directory: {}",group_path.display()))); }
    let destination=group_path.join(basename);
    // The destination is always one validated basename below the canonical group. The
    // claim serializes inspection and cloning without placing anything in destination.
    let _claim=DestinationClaim::acquire(&group_path,&destination)?;
    let chosen=protocol.unwrap_or_else(|| {
        let low_privilege=metadata.viewer_permission.as_deref().is_none_or(|p|matches!(p,"READ"|"TRIAGE"));
        if metadata.visibility.eq_ignore_ascii_case("PUBLIC") && low_privilege { "https".into() } else { "ssh".into() }
    });
    let clone_url=if chosen=="https" { &metadata.url } else { &metadata.ssh_url };
    let mut status="cloned";
    let destination_existed=match fs::symlink_metadata(&destination) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => return Err(collision(&destination,vec![])),
        Ok(_) => true,
        Err(e) if e.kind()==std::io::ErrorKind::NotFound => { fs::create_dir(&destination).map_err(|e|err(3,"collision",format!("cannot claim destination {}: {e}",destination.display())))?; false },
        Err(e) => return Err(err(3,"collision",format!("cannot inspect destination {}: {e}",destination.display()))),
    };
    let claimed_path=fs::canonicalize(&destination).map_err(|e|err(3,"collision",format!("cannot resolve destination {}: {e}",destination.display())))?;
    if !claimed_path.starts_with(&group_path) { return Err(collision(&destination,vec![])); }
    if destination_existed {
        let is_repo=destination.join(".jj").exists() || destination.join(".git").exists();
        let nonempty=fs::read_dir(&destination).map(|mut e|e.next().is_some()).unwrap_or(true);
        if is_repo {
            let remotes=repo_remote_urls(&destination);
            let matching=remotes.iter().any(|remote| {
                remote.eq_ignore_ascii_case(clone_url) || github_slug(remote).is_some_and(|(o,n)|o.eq_ignore_ascii_case(&metadata.owner.login)&&n.eq_ignore_ascii_case(&metadata.name))
            });
            if matching { status="exists"; }
            else { return Err(collision(&destination,remotes)); }
        } else if nonempty { return Err(collision(&destination,vec![])); }
    }
    if status=="cloned" {
        // Revalidate under the advisory lock immediately before handing the path to
        // jj. In particular, a waiter never relies on inspection done before lock.
        let metadata=fs::symlink_metadata(&destination).map_err(|e|err(3,"collision",format!("destination changed before clone: {e}")))?;
        let before_clone=fs::canonicalize(&destination).map_err(|e|err(3,"collision",format!("destination changed before clone: {e}")))?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() || !before_clone.starts_with(&group_path) { return Err(collision(&destination,vec![])); }
        let mut command=Command::new("jj"); command.env("GIT_TERMINAL_PROMPT","0").args(["git","clone"]);
        if let Some(depth)=depth.as_deref(){command.args(["--depth",depth]);}
        let output=command.arg(clone_url).arg(&destination).output().map_err(|e|err(1,"clone_failed",format!("cannot run jj: {e}")))?;
        if !output.status.success() {
            let message=String::from_utf8_lossy(&output.stderr).trim().to_string();
            let suffix=if destination_existed{""}else{"; the newly claimed empty destination was left in place"};
            return Err(err(1,"clone_failed",format!("{}{suffix}",if message.is_empty(){"jj git clone failed"}else{&message})));
        }
    }
    if metadata.is_archived { eprintln!("bay: warning: {} is archived",metadata.name_with_owner); }
    let path=fs::canonicalize(&destination).map_err(|e|err(1,"clone_failed",format!("cannot resolve cloned destination: {e}")))?;
    if !path.starts_with(&group_path) { return Err(collision(&destination,vec![])); }
    let result=ClonedRepo{slug:&metadata.name_with_owner,owner:&metadata.owner.login,name:&metadata.name,url:&metadata.url,clone_url,protocol:&chosen,group:&group_path,path:&path,status,default_branch:metadata.default_branch_ref.as_ref().map(|b|b.name.as_str()),archived:metadata.is_archived,private:metadata.is_private};
    if json_out { println!("{}",json!({"schema":1,"repo":result})); } else { println!("{}",path.display()); }
    Ok(())
}

fn repo_remote_urls(path:&Path)->Vec<String> {
    let output=if path.join(".jj").exists(){Command::new("jj").args(["-R"]).arg(path).args(["--ignore-working-copy","git","remote","list"]).output()}
    else{Command::new("git").args(["-C"]).arg(path).args(["remote","-v"]).output()};
    output.ok().filter(|o|o.status.success()).map(|o|String::from_utf8_lossy(&o.stdout).lines().filter_map(|line|line.split_whitespace().nth(1).map(str::to_owned)).collect()).unwrap_or_default()
}
fn collision(path:&Path,remotes:Vec<String>)->BayError { let mut e=err(3,"collision",format!("destination already exists: {}",path.display())); e.details=Some(json!({"path":path,"existing_remotes":remotes})); e }

struct DestinationClaim(fs::File);
impl DestinationClaim {
    fn acquire(group:&Path,destination:&Path)->Result<Self> {
        let lock_dir=group.join(".bay-clone-locks");
        match fs::symlink_metadata(&lock_dir) {
            Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => return Err(err(3,"collision",format!("unsafe clone lock directory: {}",lock_dir.display()))),
            Err(e) if e.kind()==std::io::ErrorKind::NotFound => {
                match fs::create_dir(&lock_dir) { Ok(())=>{}, Err(e) if e.kind()==std::io::ErrorKind::AlreadyExists=>{}, Err(e)=>return Err(err(1,"clone_failed",format!("cannot create clone lock directory: {e}"))) }
                let metadata=fs::symlink_metadata(&lock_dir).map_err(|e|err(1,"clone_failed",format!("cannot inspect clone lock directory: {e}")))?;
                if metadata.file_type().is_symlink() || !metadata.is_dir() { return Err(err(3,"collision",format!("unsafe clone lock directory: {}",lock_dir.display()))); }
                #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; fs::set_permissions(&lock_dir,fs::Permissions::from_mode(0o700)).map_err(|e|err(1,"clone_failed",format!("cannot secure clone lock directory: {e}")))?; }
            }
            Err(e) => return Err(err(1,"clone_failed",format!("cannot inspect clone lock directory: {e}"))),
            _ => {}
        }
        let canonical_lock=fs::canonicalize(&lock_dir).map_err(|e|err(1,"clone_failed",format!("cannot resolve clone lock directory: {e}")))?;
        if !canonical_lock.starts_with(group) { return Err(err(3,"collision","clone lock directory escapes configured group")); }
        let mut hash=DefaultHasher::new(); destination.hash(&mut hash);
        let path=canonical_lock.join(format!("{:016x}.lock",hash.finish()));
        if fs::symlink_metadata(&path).is_ok_and(|m|m.file_type().is_symlink() || !m.is_file()) { return Err(err(3,"collision","unsafe clone lock file")); }
        let file=open_lock_nofollow(&canonical_lock,&path)?;
        #[cfg(unix)] {
            use std::os::unix::fs::{MetadataExt,PermissionsExt};
            let opened=file.metadata().map_err(|e|err(1,"clone_failed",format!("cannot inspect opened clone lock: {e}")))?;
            let named=fs::symlink_metadata(&path).map_err(|e|err(1,"clone_failed",format!("cannot inspect clone lock path: {e}")))?;
            if named.file_type().is_symlink() || opened.dev()!=named.dev() || opened.ino()!=named.ino() { return Err(err(3,"collision","clone lock path changed while opening")); }
            file.set_permissions(fs::Permissions::from_mode(0o600)).map_err(|e|err(1,"clone_failed",format!("cannot secure clone lock: {e}")))?;
        }
        // Kernel ownership releases on close, process exit, and SIGKILL. Persistent
        // files therefore carry no stale-owner state.
        for _ in 0..600 {
            match file.try_lock() {
                Ok(()) => return Ok(Self(file)),
                Err(std::fs::TryLockError::WouldBlock) => thread::sleep(Duration::from_millis(50)),
                Err(std::fs::TryLockError::Error(e)) => return Err(err(1,"clone_failed",format!("cannot lock clone destination: {e}"))),
            }
        }
        Err(err(3,"collision",format!("clone destination is busy: {}",destination.display())))
    }
}

#[cfg(unix)]
fn open_lock_nofollow(lock_dir:&Path,path:&Path)->Result<fs::File> {
    use std::ffi::CString;
    use std::os::fd::{AsRawFd,FromRawFd};
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
    // Pin the real directory first. openat then cannot be redirected if its name
    // is replaced between validation and opening the lock file.
    let directory=OpenOptions::new().read(true).custom_flags(libc::O_DIRECTORY|libc::O_NOFOLLOW|libc::O_CLOEXEC).open(lock_dir)
        .map_err(|e|err(3,"collision",format!("cannot safely open clone lock directory: {e}")))?;
    let opened=directory.metadata().map_err(|e|err(1,"clone_failed",format!("cannot inspect opened clone lock directory: {e}")))?;
    let named=fs::symlink_metadata(lock_dir).map_err(|e|err(1,"clone_failed",format!("cannot inspect clone lock directory path: {e}")))?;
    if named.file_type().is_symlink() || opened.dev()!=named.dev() || opened.ino()!=named.ino() { return Err(err(3,"collision","clone lock directory changed while opening")); }
    let name=CString::new(path.file_name().expect("lock path has filename").as_bytes()).expect("hashed lock filename has no NUL");
    // SAFETY: directory is an owned, open directory fd; name is NUL-terminated
    // and contains no slash; successful fd ownership is transferred exactly once.
    let fd=unsafe { libc::openat(directory.as_raw_fd(),name.as_ptr(),libc::O_RDWR|libc::O_CREAT|libc::O_NOFOLLOW|libc::O_CLOEXEC,0o600) };
    if fd<0 {
        let error=std::io::Error::last_os_error();
        return Err(if error.raw_os_error()==Some(libc::ELOOP) { err(3,"collision","unsafe clone lock symlink") } else { err(1,"clone_failed",format!("cannot safely open clone lock: {error}")) });
    }
    // SAFETY: openat returned a new owned descriptor and no other File owns it.
    Ok(unsafe { fs::File::from_raw_fd(fd) })
}

fn local_identity(path: &Path, owner: &str, name: &str) -> Option<FoundLocal> {
    if !path.exists() { return None; }
    let mut urls = Vec::new();
    if path.join(".jj").exists() {
        if let Ok(out)=Command::new("jj").args(["-R"]).arg(path).args(["--ignore-working-copy","git","remote","list"]).output() { urls.extend(String::from_utf8_lossy(&out.stdout).split_whitespace().map(str::to_owned)); }
    } else if path.join(".git").exists() {
        if let Ok(out)=Command::new("git").args(["-C"]).arg(path).args(["remote","-v"]).output() { urls.extend(String::from_utf8_lossy(&out.stdout).split_whitespace().map(str::to_owned)); }
    }
    let present=urls.iter().filter_map(|url|github_slug(url)).any(|(o,n)|o.eq_ignore_ascii_case(owner)&&n.eq_ignore_ascii_case(name));
    Some(FoundLocal{path:canonical(path),status:if present{"present"}else{"foreign"}})
}

fn list(args: Vec<OsString>) -> Result<()> {
    let json_out = args.iter().any(|a| a == "--json");
    let repo = args
        .iter()
        .find(|a| *a != "--json")
        .map(|a| a.to_string_lossy().into_owned());
    let records = if let Some(repo) = repo { discover_selected(&repo)? } else { discover()? };
    if json_out {
        println!("{}", json!({"schema":1,"workspaces":records}));
    } else {
        println!("REPO\tNAME\tPATH");
        for r in records {
            println!(
                "{}\t{}\t{}",
                r.repo.unwrap_or_default(),
                r.name,
                r.path
                    .map(|p| p.display().to_string())
                    .unwrap_or_else(|| "<missing>".into())
            );
        }
    }
    Ok(())
}

fn path(args: Vec<OsString>) -> Result<()> {
    if args.len() != 1 {
        return Err(err(2, "usage", "bay path requires one selector"));
    }
    let selector=args[0].to_string_lossy();let r=select(&selector,&discover_for_workspace_selector(&selector)?)?;
    println!(
        "{}",
        r.path
            .ok_or_else(|| err(
                3,
                "not_found",
                format!("workspace {} has a missing root", r.name)
            ))?
            .display()
    );
    Ok(())
}
fn root(args: Vec<OsString>) -> Result<()> {
    if args.len() > 1 {
        return Err(err(2, "usage", "bay root accepts at most one repository"));
    }
    let all = if let Some(repo)=args.first(){discover_selected(&repo.to_string_lossy())?}else{discover()?};
    let first = if let Some(repo) = args.first() {
        select_repo(&repo.to_string_lossy(), &all)?
    } else {
        unique_repo(repo_records_from_cwd(&all))?
    };
    let cfg = ws_config().map_err(config_err)?;
    let group = first
        .group
        .ok_or_else(|| err(3, "not_a_repo", "repository is outside configured groups"))?;
    let g = cfg
        .project_groups
        .iter()
        .find(|g| canonical(&g.path) == group)
        .ok_or_else(|| err(1, "config", "group disappeared"))?;
    println!(
        "{}",
        group
            .join(&g.workspace_dir)
            .join(first.repo.unwrap())
            .display()
    );
    Ok(())
}

fn add(mut args: Vec<OsString>) -> Result<()> {
    let json_out = take_flag(&mut args, "--json");
    if json_out && !args.iter().any(|arg| arg == "-q" || arg == "--quiet") {
        args.push("-q".into());
    }
    let mut repo_path = None;
    let mut at = None;
    let mut i = 0;
    while i < args.len() {
        let s = args[i].to_string_lossy();
        if s == "--repo" || s == "--at" {
            if i + 1 >= args.len() {
                return Err(err(2, "usage", format!("missing value for {s}")));
            }
            let v = PathBuf::from(args.remove(i + 1));
            let flag = args.remove(i);
            if flag == "--repo" {
                repo_path = Some(v)
            } else {
                at = Some(v)
            }
        } else {
            i += 1
        }
    }
    let name_i = add_name_index(&args)?;
    let raw = args[name_i].to_string_lossy().into_owned();
    let (repo_name, name) = raw
        .split_once('/')
        .map(|(a, b)| (Some(a), b))
        .unwrap_or((None, raw.as_str()));
    args[name_i] = OsString::from(name);
    let anchor = if let Some(p) = repo_path.or(at) {
        repo_anchor(&p)?
    } else if let Some(repo) = repo_name {
        unique_repo(discover_selected(repo)?)?.anchor
    } else {
        let all=discover()?;
        unique_repo(repo_records_from_cwd(&all))?.anchor
    };
    let requested_name = name.to_string();
    if json_out {
        env::set_var("BAY_JSON", "1");
    }
    let result = in_dir(&anchor, || run_ws(prepend("add", args)));
    if json_out {
        env::remove_var("BAY_JSON");
    }
    result?.map_err(operation_err)?;
    if json_out {
        let store = repo_store(&anchor)?;
        let workspace = discover()?
            .into_iter()
            .find(|r| r.name == requested_name && repo_store(&r.anchor).is_ok_and(|candidate| candidate == store))
            .ok_or_else(|| err(1, "jj_failed", "created workspace was not discoverable"))?;
        println!("{}", json!({"schema":1,"workspace":workspace}));
    }
    Ok(())
}
fn remove(mut args: Vec<OsString>) -> Result<()> {
    let json_out = take_flag(&mut args, "--json");
    if json_out && !args.iter().any(|arg| arg == "-q" || arg == "--quiet") {
        args.push("-q".into());
    }
    let selector_i = args
        .iter()
        .position(|a| !a.to_string_lossy().starts_with('-'))
        .ok_or_else(|| err(2, "usage", "missing selector"))?;
    let selector=args[selector_i].to_string_lossy();let all=discover_for_workspace_selector(&selector)?;
    let r = select(&selector, &all)?;
    args[selector_i] = OsString::from(&r.name);
    in_dir(&r.anchor, || run_ws(prepend("forget", args)))?.map_err(operation_err)?;
    if json_out {
        println!("{}", json!({"schema":1,"removed":{"name":r.name,"path":r.path}}));
    }
    Ok(())
}
fn maintenance(sub: &str, mut args: Vec<OsString>) -> Result<()> {
    let value_flags: &[&str] = match sub {
        "gc" => &["--older-than"],
        "sweep" => &["--idle"],
        _ => &[],
    };
    let mut repo_i = None;
    let mut i = 0;
    while i < args.len() {
        let s = args[i].to_string_lossy();
        if value_flags.contains(&s.as_ref()) {
            i += 2;
            continue;
        }
        if s.starts_with('-') {
            i += 1;
            continue;
        }
        if repo_i.replace(i).is_some() {
            return Err(err(
                2,
                "usage",
                format!("bay {sub} accepts at most one repository"),
            ));
        }
        i += 1;
    }
    let selected = if let Some(index) = repo_i {
        let selector = args.remove(index);
        let all=discover_selected(&selector.to_string_lossy())?;
        select_repo(&selector.to_string_lossy(), &all)?
    } else {
        let all=discover()?;
        unique_repo(repo_records_from_cwd(&all)).map_err(|e| {
            if e.kind == "not_a_repo" {
                err(
                    2,
                    "usage",
                    format!("bay {sub} requires REPO when run outside a configured repository"),
                )
            } else {
                e
            }
        })?
    };
    in_dir(&selected.anchor, || run_ws(prepend(sub, args)))?.map_err(operation_err)
}

fn select_repo(selector: &str, all: &[Record]) -> Result<Record> {
    let path_like =
        selector.starts_with('/') || selector.starts_with('.') || selector.starts_with('~');
    let candidates = if path_like {
        let expanded = if let Some(rest) = selector.strip_prefix("~/") {
            env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_default()
                .join(rest)
        } else {
            PathBuf::from(selector)
        };
        let anchor = repo_anchor(&expanded)?;
        let store = repo_store(&anchor)?;
        all.iter()
            .filter(|r| repo_store(&r.anchor).is_ok_and(|s| s == store))
            .cloned()
            .collect()
    } else {
        all.iter()
            .filter(|r| r.repo.as_deref() == Some(selector))
            .cloned()
            .collect()
    };
    unique_repo(candidates).map_err(|e| {
        if e.kind == "not_a_repo" {
            err(
                3,
                "not_found",
                format!("no repository matches {selector:?}"),
            )
        } else {
            e
        }
    })
}
fn add_name_index(args: &[OsString]) -> Result<usize> {
    let mut i = 0;
    let mut found = None;
    while i < args.len() {
        let s = args[i].to_string_lossy();
        if matches!(
            s.as_ref(),
            "-r" | "--revision" | "--project-group" | "--project-dir" | "--venv" | "--venv-mode"
        ) {
            i += 2;
            continue;
        }
        if s.starts_with('-') || s.contains('=') {
            i += 1;
            continue;
        }
        if found.replace(i).is_some() {
            return Err(err(2, "usage", "unexpected extra add argument"));
        }
        i += 1
    }
    found.ok_or_else(|| err(2, "usage", "missing bay name"))
}
fn prepend(s: &str, mut a: Vec<OsString>) -> Vec<OsString> {
    let mut v = vec![s.into()];
    v.append(&mut a);
    v
}
fn take_flag(args: &mut Vec<OsString>, flag: &str) -> bool {
    let found = args.iter().any(|arg| arg == flag);
    args.retain(|arg| arg != flag);
    found
}
fn in_dir<T>(p: &Path, f: impl FnOnce() -> T) -> Result<T> {
    let old = env::current_dir().map_err(|e| {
        err(
            1,
            "jj_failed",
            format!("cannot record caller directory: {e}"),
        )
    })?;
    env::set_current_dir(p).map_err(|e| {
        err(
            3,
            "not_a_repo",
            format!("cannot enter selected repository {}: {e}", p.display()),
        )
    })?;
    let out = f();
    env::set_current_dir(&old).map_err(|e| {
        err(
            1,
            "jj_failed",
            format!("cannot restore caller directory {}: {e}", old.display()),
        )
    })?;
    Ok(out)
}
fn operation_err(e: anyhow::Error) -> BayError {
    let m = format!("{e:#}");
    let (code, kind) =
        if m.contains("unpublished") || (m.contains("non-empty") && m.contains("refus")) {
            (4, "unpublished_work")
        } else if m.contains("current workspace") {
            (4, "current_workspace")
        } else if m.contains("hook") {
            (1, "hook_failed")
        } else {
            (1, "jj_failed")
        };
    err(code, kind, m)
}
fn config_err(e: anyhow::Error) -> BayError {
    err(1, "config", format!("{e:#}"))
}

fn discover() -> Result<Vec<Record>> {
    discover_matching(None)
}
fn discover_selected(selector: &str) -> Result<Vec<Record>> {
    if selector.starts_with('/') || selector.starts_with('.') || selector.starts_with('~') {
        let path = if let Some(rest) = selector.strip_prefix("~/") { env::var_os("HOME").map(PathBuf::from).unwrap_or_default().join(rest) } else { PathBuf::from(selector) };
        let anchor=repo_anchor(&path)?;let cfg=ws_config().map_err(config_err)?;let group=cfg.project_groups.iter().filter(|g|anchor.starts_with(canonical(&g.path))).max_by_key(|g|g.path.components().count()).cloned().ok_or_else(||err(3,"not_a_repo","repository is outside configured groups"))?;
        return records_for(&anchor,&group,&cfg);
    }
    discover_matching(Some(selector))
}
fn discover_for_workspace_selector(selector:&str)->Result<Vec<Record>>{if selector.starts_with('/')||selector.starts_with('.')||selector.starts_with('~'){discover_selected(selector)}else if let Some((repo,_))=selector.split_once('/'){discover_selected(repo)}else{discover()}}
fn discover_matching(repo_filter: Option<&str>) -> Result<Vec<Record>> {
    let cfg = ws_config().map_err(config_err)?;
    let mut candidates = BTreeMap::new();
    for g in &cfg.project_groups {
        let selected = if let Some(repo) = repo_filter { repo_anchors(g, repo)? } else { anchors(g)? };
        for a in selected {
            match repo_store(&a){Ok(store)=>{candidates.entry(store).or_insert((a,g.clone()));},Err(e)=>eprintln!("bay: skipping stale repository candidate: {}",e.message)}
        }
    }
    let jobs = Arc::new(Mutex::new(candidates.into_values()));
    let results: Arc<Mutex<Vec<Result<Vec<Record>>>>> = Arc::new(Mutex::new(Vec::new()));
    thread::scope(|scope| {
        for _ in 0..6 {
            let jobs = jobs.clone();
            let results = results.clone();
            let cfg = &cfg;
            scope.spawn(move || loop {
                let job = jobs.lock().unwrap().next();
                let Some((anchor, g)) = job else { return };
                let item = records_for(&anchor,&g,cfg);
                results.lock().unwrap().push(item);
            });
        }
    });
    let mut out = vec![];
    for item in Arc::try_unwrap(results).unwrap().into_inner().unwrap() {
        match item {
            Ok(records) => out.extend(records),
            Err(e) => eprintln!("bay: skipping stale repository candidate: {}", e.message),
        }
    }
    out.sort_by(|a, b| (&a.repo, &a.name).cmp(&(&b.repo, &b.name)));
    Ok(out)
}
fn records_for(anchor:&Path,g:&ProjectGroup,cfg:&WsConfig)->Result<Vec<Record>>{let repo=repo_name(anchor,g);let entries=discover_workspaces(anchor,cfg).map_err(|e|err(1,"jj_failed",format!("{e:#}")))?;let main=entries.iter().find(|e|e.name=="default").and_then(|e|e.path.clone());let operation_anchor=main.clone().unwrap_or_else(||anchor.to_path_buf());Ok(entries.into_iter().map(|e|Record{name:e.name,path:e.path,repo:repo.clone(),main:main.clone(),group:Some(canonical(&g.path)),kind:if e.kind==WorkspaceKind::Main{"main"}else{"bay"},managed:e.managed,anchor:operation_anchor.clone()}).collect())}
fn anchors(g: &ProjectGroup) -> Result<Vec<PathBuf>> {
    let mut v = vec![];
    let rd = match fs::read_dir(&g.path) {
        Ok(x) => x,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(v),
        Err(e) => return Err(err(1, "config", e.to_string())),
    };
    for e in rd.flatten() {
        let p = e.path();
        if p.join(".jj").exists() {
            v.push(p)
        }
    }
    let wr = g.path.join(&g.workspace_dir);
    if let Ok(repos) = fs::read_dir(wr) {
        for repo in repos.flatten() {
            if let Ok(bays) = fs::read_dir(repo.path()) {
                for bay in bays.flatten() {
                    let p = bay.path();
                    if p.join(".jj").exists() {
                        v.push(p)
                    }
                }
            }
        }
    }
    Ok(v)
}
fn repo_anchors(g:&ProjectGroup,repo:&str)->Result<Vec<PathBuf>>{let mut v=vec![];let main=g.path.join(repo);if main.join(".jj").exists(){v.push(main)}let bays=g.path.join(&g.workspace_dir).join(repo);match fs::read_dir(&bays){Ok(entries)=>for entry in entries.flatten(){let p=entry.path();if p.join(".jj").exists(){v.push(p)}},Err(e)if e.kind()==std::io::ErrorKind::NotFound=>{},Err(e)=>return Err(err(1,"config",format!("failed to read {}: {e}",bays.display())))}Ok(v)}
fn repo_store(anchor: &Path) -> Result<PathBuf> {
    let p = anchor.join(".jj/repo");
    let target = if p.is_file() {
        let relative = fs::read_to_string(&p)
            .map_err(|e| err(3, "not_a_repo", format!("{}: {e}", anchor.display())))?;
        p.parent().unwrap_or(anchor).join(relative)
    } else {
        p
    };
    fs::canonicalize(&target)
        .map_err(|e| err(3, "not_a_repo", format!("{}: {e}", anchor.display())))
}
fn repo_name(anchor: &Path, g: &ProjectGroup) -> Option<String> {
    let gp = canonical(&g.path);
    let a = canonical(anchor);
    let rel = a.strip_prefix(&gp).ok()?;
    let p: Vec<_> = rel.components().collect();
    if p.first()?.as_os_str() == g.workspace_dir.as_str() {
        p.get(1)
    } else {
        p.first()
    }
    .map(|x| x.as_os_str().to_string_lossy().into_owned())
}
fn canonical(p: &Path) -> PathBuf {
    fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf())
}
fn repo_anchor(p: &Path) -> Result<PathBuf> {
    let o = Command::new("jj")
        .args(["-R"])
        .arg(p)
        .args(["--ignore-working-copy", "root"])
        .output()
        .map_err(|e| err(3, "not_a_repo", e.to_string()))?;
    if !o.status.success() {
        return Err(err(3, "not_a_repo", String::from_utf8_lossy(&o.stderr)));
    }
    Ok(PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()))
}
fn repo_records_from_cwd(all: &[Record]) -> Vec<Record> {
    let cwd = env::current_dir().unwrap_or_default();
    all.iter()
        .filter(|r| r.path.as_ref().is_some_and(|p| cwd.starts_with(p)))
        .cloned()
        .collect()
}
fn unique_repo(v: Vec<Record>) -> Result<Record> {
    let mut seen = HashSet::new();
    let u: Vec<_> = v
        .into_iter()
        .filter(|r| seen.insert(repo_store(&r.anchor).ok()))
        .collect();
    match u.len() {
        0 => Err(err(3, "not_a_repo", "no repository selected")),
        1 => Ok(u[0].clone()),
        _ => Err(err(3, "ambiguous", "repository is ambiguous")),
    }
}
fn select(s: &str, all: &[Record]) -> Result<Record> {
    let expanded = if let Some(x) = s.strip_prefix("~/") {
        env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_default()
            .join(x)
    } else {
        PathBuf::from(s)
    };
    let mut c: Vec<Record> = if s.starts_with('/') || s.starts_with('.') || s.starts_with('~') {
        let p = canonical(&expanded);
        all.iter()
            .filter(|r| r.path.as_ref().is_some_and(|x| canonical(x) == p))
            .cloned()
            .collect()
    } else if let Some((repo, name)) = s.split_once('/') {
        all.iter()
            .filter(|r| r.repo.as_deref() == Some(repo) && r.name == name)
            .cloned()
            .collect()
    } else {
        let local = repo_records_from_cwd(all);
        let pool = if local.is_empty() {
            all.to_vec()
        } else {
            local
        };
        pool.into_iter().filter(|r| r.name == s).collect()
    };
    match c.len() {
        0 => Err(err(3, "not_found", format!("no workspace matches {s:?}"))),
        1 => Ok(c.remove(0)),
        _ => {
            let mut e = err(
                3,
                "ambiguous",
                format!("workspace selector {s:?} is ambiguous"),
            );
            e.candidates = c;
            e.candidates
                .sort_by(|a, b| (&a.repo, &a.name).cmp(&(&b.repo, &b.name)));
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn missing_selected_anchor_never_runs_operation() {
        let mut ran = false;
        let result = in_dir(Path::new("/definitely/missing/bay-anchor"), || ran = true);
        assert!(result.is_err());
        assert!(!ran);
    }
}

//! Device-wide facade for the repository-local workspace operations.
use crate::ws::{discover_workspaces, run_ws, ws_config, ProjectGroup, WorkspaceKind, WsConfig};
use serde::Serialize;
use serde_json::json;
use std::collections::{BTreeMap, HashSet};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;

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
    if !matches!(sub.as_str(), "list" | "ls") { args.retain(|arg| arg != "--json"); }
    match sub.as_str() {
        "list" | "ls" => list(args),
        "path" => path(args),
        "root" => root(args),
        "add" => add(args),
        "rm" | "forget" => remove(args),
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
    "Usage: bay list|ls [REPO] [--json]\n       bay path <selector>\n       bay root [REPO]\n       bay add [<repo>/]<name> [-r REV] [--repo PATH] [--at DIR]\n       bay rm|forget <selector> [jj ws forget options]\n       bay prune [REPO] [--dry-run] [--delete] [--pick] [--yes]\n       bay gc [REPO] [--older-than DUR] [--dry-run]\n       bay du [REPO]\n       bay sweep [REPO] [--idle DUR] [--dry-run]"
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

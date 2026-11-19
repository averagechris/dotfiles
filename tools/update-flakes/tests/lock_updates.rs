use std::fs;
use std::path::Path;
use std::process::{Command, Output};

fn run(dir: &Path, program: &str, args: &[&str]) -> String {
    let output = Command::new(program)
        .current_dir(dir)
        .args(args)
        .output()
        .unwrap();
    assert_success(output)
}

fn assert_success(output: Output) -> String {
    assert!(
        output.status.success(),
        "stdout: {}\nstderr: {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap()
}

fn commit(dir: &Path) {
    run(dir, "git", &["add", "."]);
    run(
        dir,
        "git",
        &[
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "core.hooksPath=/dev/null",
            "commit",
            "-qm",
            "Update fixture",
        ],
    );
}

fn update(repo: &Path, check: bool) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_update-flakes"));
    command
        .current_dir(repo)
        .env("DOTFILES_REPO_ROOT", repo)
        .env("TMPDIR", repo.parent().unwrap().join("scratch ?"))
        .arg("--no-manual-packages");
    if check {
        command.arg("--check");
    }
    command.output().unwrap()
}

#[test]
#[ignore = "requires Git with relative worktree support and a Nix store"]
fn check_predicts_apply_in_a_relative_worktree() {
    let temp = tempfile::tempdir().unwrap();
    let upstream = temp.path().join("upstream");
    let repo = temp.path().join("repo");
    let worktree = temp.path().join("worktree");
    fs::create_dir(temp.path().join("scratch ?")).unwrap();
    fs::create_dir(&upstream).unwrap();
    fs::write(upstream.join("flake.nix"), "{ outputs = { self }: {}; }").unwrap();
    run(&upstream, "git", &["init", "-q"]);
    commit(&upstream);

    fs::create_dir_all(repo.join("child")).unwrap();
    fs::create_dir(repo.join("maintenance")).unwrap();
    let root_flake = "{ inputs.child.url = \"path:./child\"; outputs = { self, child }: {}; }";
    fs::write(repo.join("flake.nix"), root_flake).unwrap();
    fs::write(
        repo.join("child/flake.nix"),
        format!(
            "{{ inputs.upstream.url = \"git+file://{}\"; outputs = {{ self, upstream }}: {{}}; }}",
            upstream.display()
        ),
    )
    .unwrap();
    fs::write(
        repo.join("maintenance/policy.json"),
        r#"{"canonical_locks": ["child/flake.lock", "flake.lock"]}"#,
    )
    .unwrap();
    run(&repo, "git", &["init", "-q"]);
    for directory in ["child", "."] {
        let reference = format!("path:{}?dir={directory}", repo.display());
        let lock = repo.join(directory).join("flake.lock");
        run(
            &repo,
            "nix",
            &[
                "flake",
                "lock",
                &reference,
                "--output-lock-file",
                lock.to_str().unwrap(),
            ],
        );
    }
    commit(&repo);
    run(
        &repo,
        "git",
        &[
            "worktree",
            "add",
            "--detach",
            "--relative-paths",
            worktree.to_str().unwrap(),
        ],
    );

    let root = worktree.join("flake.lock");
    let child = worktree.join("child/flake.lock");
    let before = [fs::read(&root).unwrap(), fs::read(&child).unwrap()];
    fs::write(upstream.join("extra"), "New upstream revision").unwrap();
    commit(&upstream);
    let revision = run(&upstream, "git", &["rev-parse", "HEAD"]);

    let check = assert_success(update(&worktree, true));
    assert!(
        check.contains("Updates available for child: upstream"),
        "{check}"
    );
    assert!(
        check.contains("Updates available for top-level: upstream"),
        "{check}"
    );
    assert_eq!(
        [fs::read(&root).unwrap(), fs::read(&child).unwrap()],
        before
    );

    // A parent failure must leave both original locks in place.
    fs::write(worktree.join("flake.nix"), "invalid expression").unwrap();
    assert!(!update(&worktree, false).status.success());
    assert_eq!(
        [fs::read(&root).unwrap(), fs::read(&child).unwrap()],
        before
    );
    fs::write(worktree.join("flake.nix"), root_flake).unwrap();

    assert_success(update(&worktree, false));
    for path in [&root, &child] {
        let lock: serde_json::Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
        assert_eq!(lock["nodes"]["upstream"]["locked"]["rev"], revision.trim());
    }
    let check = assert_success(update(&worktree, true));
    assert!(check.contains("child is up to date"), "{check}");
    assert!(check.contains("top-level is up to date"), "{check}");

    fs::remove_file(&child).unwrap();
    let check = assert_success(update(&worktree, true));
    assert!(
        check.contains("Updates available for child: <new lock file>"),
        "{check}"
    );
    assert!(!child.exists());
    assert_success(update(&worktree, false));
    assert!(child.is_file());
}

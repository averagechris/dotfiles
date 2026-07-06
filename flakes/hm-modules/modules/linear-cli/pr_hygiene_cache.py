"""Cache and render the repo-managed `jj pr hygiene` report.

The scheduled job keeps GitHub PR hygiene fresh for shell prompt/greeting use.
Prompt mode is strictly local: it never shells out to `jj` or `gh`.
"""

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


JJ_ROOT_TIMEOUT_SECONDS = 3
JJ_PR_HYGIENE_TIMEOUT_SECONDS = 120


def utc_now():
    return dt.datetime.now(dt.timezone.utc)


def iso(ts):
    # Keep timestamps jq/fromdateiso8601-friendly for the fast prompt path.
    return ts.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, TypeError, ValueError):
        return None


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def write_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, text=True
    )
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True)
        handle.write("\n")
    os.replace(tmp_name, path)
    os.chmod(path, 0o600)


def expand_path(path):
    return Path(os.path.expandvars(os.path.expanduser(path)))


def command_ok(cwd, args, timeout=None):
    try:
        result = subprocess.run(
            args,
            cwd=cwd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def sorted_children(path):
    """Return sorted directory entries, or [] for unreadable/stale paths."""

    try:
        return sorted(path.iterdir())
    except OSError:
        return []


def is_dir(path):
    try:
        return path.is_dir()
    except OSError:
        return False


def candidate_workdirs(raw_workdirs):
    seen = set()

    def add(path):
        try:
            resolved = path.resolve()
        except OSError:
            resolved = path
        if resolved in seen:
            return
        seen.add(resolved)
        yield resolved

    for raw in raw_workdirs:
        root = expand_path(raw)
        try:
            exists = root.exists()
        except OSError:
            exists = False
        if not exists:
            continue
        yield from add(root)
        if is_dir(root):
            # Project-group roots like ~/sureapp contain main checkouts one level
            # down. Managed workspaces use <group>/ws/<repo>/<workspace>.
            for child in sorted_children(root):
                if child.name.startswith(".") or not is_dir(child):
                    continue
                yield from add(child)
                if child.name == "ws":
                    for repo in sorted_children(child):
                        if not is_dir(repo):
                            continue
                        for workspace in sorted_children(repo):
                            if is_dir(workspace):
                                yield from add(workspace)


def find_jj_workdir(raw_workdirs):
    for path in candidate_workdirs(raw_workdirs):
        if command_ok(
            path,
            ["jj", "root", "--color=never"],
            timeout=JJ_ROOT_TIMEOUT_SECONDS,
        ):
            return path
    return None


def cache_inputs(args):
    return {
        "search": args.search,
        "limit": args.limit,
        "ttlSeconds": args.ttl_minutes * 60,
        # Match the configured strings passed by the Nix prompt/greeting path.
        # Workdir discovery still expands ~/$HOME when scanning the filesystem,
        # but cache invalidation should compare the exact input contract.
        "workdirs": list(args.workdir),
        "noWorkspaces": bool(args.no_workspaces),
    }


def cache_fresh(payload, args=None, now=None):
    if not isinstance(payload, dict):
        return False
    now = now or utc_now()
    cache = payload.get("cache") or {}
    if not isinstance(cache, dict):
        return False
    expires = parse_iso(cache.get("expiresAt"))
    if expires is None or now >= expires:
        return False
    if args is not None and cache.get("inputs") != cache_inputs(args):
        return False
    return True


def refresh(args, force=False):
    cached = load_json(args.artifact)
    if not force and cache_fresh(cached, args):
        return cached, False

    workdir = find_jj_workdir(args.workdir)
    if workdir is None:
        raise SystemExit(
            "could not find a jj workdir for PR hygiene; configure prHygiene.workdirs"
        )

    cmd = [
        "jj",
        "pr",
        "hygiene",
        "--json",
        "--limit",
        str(args.limit),
        "--search",
        args.search,
    ]
    if args.no_workspaces:
        cmd.append("--no-workspaces")

    try:
        result = subprocess.run(
            cmd,
            cwd=workdir,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=JJ_PR_HYGIENE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        stderr = (exc.stderr or "").strip() if isinstance(exc.stderr, str) else ""
        raise SystemExit(
            f"jj pr hygiene timed out in {workdir} after {JJ_PR_HYGIENE_TIMEOUT_SECONDS}s"
            f"{f': {stderr[:500]}' if stderr else ''}"
        ) from exc
    except OSError as exc:
        raise SystemExit(f"failed to run jj pr hygiene in {workdir}: {exc}") from exc
    if result.returncode != 0:
        stderr = result.stderr.strip()
        if len(stderr) > 500:
            stderr = stderr[:500] + "…"
        raise SystemExit(
            f"jj pr hygiene failed in {workdir} with status {result.returncode}: {stderr or '(no stderr)'}"
        )
    try:
        payload = json.loads(result.stdout)
    except ValueError as exc:
        raise SystemExit(f"jj pr hygiene returned malformed JSON: {exc}") from exc

    now = utc_now()
    expires = now + dt.timedelta(minutes=args.ttl_minutes)
    payload["cache"] = {
        "generatedAt": iso(now),
        "expiresAt": iso(expires),
        "ttlSeconds": args.ttl_minutes * 60,
        "workdir": str(workdir),
        "inputs": cache_inputs(args),
    }
    write_json(args.artifact, payload)
    return payload, True


def actionable_prs(payload):
    if not isinstance(payload, dict):
        return []
    prs = payload.get("prs") or []
    if not isinstance(prs, list):
        return []
    return [
        pr
        for pr in prs
        if isinstance(pr, dict)
        and pr.get("status") in {"needs-fix", "ready", "needs-review"}
    ]


def human_age(payload):
    if not isinstance(payload, dict):
        return "unknown age"
    generated = parse_iso((payload.get("cache") or {}).get("generatedAt"))
    if generated is None:
        return "unknown age"
    seconds = int((utc_now() - generated).total_seconds())
    if seconds < 3600:
        return f"{max(seconds // 60, 0)}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def print_human(payload):
    if not isinstance(payload, dict):
        payload = {}
    prs = payload.get("prs") or []
    if not isinstance(prs, list):
        prs = []
    actionable = actionable_prs(payload)
    print(
        f"GitHub PR hygiene: {len(actionable)} actionable / {len(prs)} open "
        f"(cached {human_age(payload)})"
    )
    if not prs:
        print("No open PRs found.")
        return
    for idx, pr in enumerate(actionable or prs, 1):
        repo = pr.get("repo", "?")
        number = pr.get("number", "?")
        title = pr.get("title", "?")
        status = pr.get("status", "unknown")
        priority = str(pr.get("priority", "?")).upper()
        effort = pr.get("reviewEffort", "?")
        url = pr.get("url", "")
        follow_up = pr.get("followUp", "inspect")
        print(f"{idx}. {priority} · {status} · {effort} · {repo}#{number}")
        print(f"   {title}")
        if url:
            print(f"   {url}")
        print(f"   follow-up: {follow_up}")


def print_prompt(payload, args):
    if not cache_fresh(payload, args):
        return 1
    actionable = actionable_prs(payload)
    if not actionable:
        return 1
    print(f"PR{len(actionable)}", end="")
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["refresh", "report", "prompt"])
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--search", default="author:@me is:pr is:open archived:false")
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--ttl-minutes", type=int, default=45)
    parser.add_argument("--workdir", action="append", default=[])
    parser.add_argument("--no-workspaces", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    if args.mode == "prompt":
        return print_prompt(load_json(args.artifact) or {}, args)

    if args.mode == "refresh":
        payload, did_refresh = refresh(args, force=args.force)
        print("refreshed" if did_refresh else "fresh")
        return 0

    payload, _ = refresh(args, force=args.force)
    if args.json:
        print(json.dumps(payload, indent=1, sort_keys=True))
    else:
        print_human(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Run against a built V2 binary and emitted HM opencode directory, never live state.

Usage: python3 runtime-v2.py /nix/store/.../bin/opencode /nix/store/.../opencode
Requires bash, jq and direnv on PATH. Keeps evidence under TMPDIR; stops its servers.
No completions, credentials, activation, or mocked OpenCode/direnv implementations.
"""

import base64
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


binary, emitted = Path(sys.argv[1]).absolute(), Path(sys.argv[2]).absolute()
# Match process.cwd(): macOS /var and /private/var otherwise create two V2 locations.
root = Path(tempfile.mkdtemp(prefix="opencode-v2-runtime-")).resolve()
print(f"Evidence: {root}", flush=True)
module = Path(__file__).resolve().parents[1]
tools = {name: str(Path(shutil.which(name)).resolve()) for name in ["bash", "jq", "direnv"]}
for name in ["home", "tmp", "state", "cache", "data", "work", "cold", "allowed/sub", "blocked/sub"]:
    (root / name).mkdir(parents=True)
shutil.copytree(emitted, root / "config/opencode", symlinks=False)
(root / "config/opencode").chmod(0o755)
env = {
    "PATH": f"{binary.parent}:{Path(tools['jq']).parent}:/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": str(root / "home"), "TMPDIR": str(root / "tmp"), "SHELL": "/bin/bash",
    "OPENCODE_DISABLE_PROJECT_CONFIG": "1", "OPENCODE_DISABLE_MODELS_FETCH": "1",
    "OPENCODE_PASSWORD": "local-integration-fixture", "CARGO_INCREMENTAL": "1",
}
for key, name in [("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                  ("XDG_STATE_HOME", "state"), ("XDG_CACHE_HOME", "cache"),
                  ("OPENCODE_CONFIG_DIR", "config/opencode"), ("OPENCODE_TEST_HOME", "home")]:
    env[key] = str(root / name)
config_file = root / "config/opencode/opencode.json"
config_file.chmod(0o644)
config = json.loads(config_file.read_text())
assert all(m.get("disabled") is True for m in config.get("mcp", {}).get("servers", {}).values()), "MCP must be disabled"
assert not ({"agent", "permission", "provider"} & config.keys())
assert "agents" in config and "permissions" in config and "servers" in config["mcp"]
assert all("enabled" not in server for server in config["mcp"]["servers"].values())
for agent_file in (root / "config/opencode/agents").glob("*.md"):
    frontmatter = agent_file.read_text().split("---", 2)[1]
    assert not re.search(r"(?m)^(permission|variant|temperature):", frontmatter)
    assert re.search(r"(?m)^permissions:$", frontmatter)
    assert re.search(r"(?m)^request:\n\s+body:\n\s+temperature:", frontmatter)
    assert "action: bash" not in frontmatter and "action: task" not in frontmatter
config.update({"model": "fixture/base", "providers": {"fixture": {
    "package": "@ai-sdk/openai-compatible",
    "settings": {"baseURL": "http://127.0.0.1:9/v1", "apiKey": "not-a-credential"},
    "models": {"base": {"name": "Base"}, "trial": {"name": "Trial"}},
}}})
config_file.write_text(json.dumps(config))
(root / "allowed/.envrc").write_text('export DOTFILES_TEST=allowed\nexport CARGO_INCREMENTAL=1\n')
(root / "blocked/.envrc").write_text('export DOTFILES_TEST=blocked\ntouch "$HOME/blocked-executed"\n')
subprocess.run([tools["direnv"], "allow", str(root / "allowed")], env=env, check=True, capture_output=True)
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
url = f"http://127.0.0.1:{port}"
# The pinned Nix package sets OPENCODE_CHANNEL=prod, not latest/local.
(root / "config/opencode/service-prod.json").write_text(json.dumps({"port": port, "password": env["OPENCODE_PASSWORD"]}))
headers = {"authorization": "Basic " + base64.b64encode(b"opencode:local-integration-fixture").decode(),
           "x-opencode-directory": str(root / "work"), "content-type": "application/json"}


def save(name, data):
    (root / (name + ".json")).write_text(json.dumps(data, indent=2))


def api(method, path, data=None):
    req = urllib.request.Request(url + path, method=method, headers=headers,
                                 data=None if data is None else json.dumps(data).encode())
    with urllib.request.urlopen(req, timeout=10) as response:
        text = response.read().decode()
    result = json.loads(text) if text else None
    with (root / "requests.jsonl").open("a") as log:
        log.write(json.dumps({"method": method, "path": path, "input": data, "response": result}) + "\n")
    return result


def run(args, name, extra=None, cwd="work"):
    result = subprocess.run([str(a) for a in args], env=env | (extra or {}), cwd=root / cwd,
                            capture_output=True, text=True, timeout=40)
    save(name, {"args": [str(a) for a in args], "cwd": str(root / cwd), "extra_env": extra,
                "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    assert result.returncode == 0, result.stderr
    return result.stdout


@contextmanager
def server():
    args = [str(binary), "serve", "--service", "--hostname", "127.0.0.1", "--port", str(port), "--print-logs"]
    with (root / f"server-{time.time_ns()}.log").open("w") as log:
        process = subprocess.Popen(args, env=env, cwd=root / "work", stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        save(f"invocation-{process.pid}", {"args": args, "env": env, "pid": process.pid})
        try:
            for _ in range(100):
                assert process.poll() is None, f"Server exited; inspect {log.name}"
                try:
                    if api("GET", "/api/status")["pid"] == process.pid:
                        break
                except urllib.error.URLError:
                    time.sleep(.1)
            else:
                raise AssertionError("Server did not become ready")
            yield
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            save(f"exit-{process.pid}", {"returncode": process.returncode})


def ready():
    for _ in range(50):
        agents = api("GET", "/api/agent")["data"]
        plugins = api("GET", "/api/plugin")["data"]
        ours = [p for p in plugins if p.get("id", "").startswith("dotfiles-")]
        if any(a["id"] == "orchestrator" for a in agents) and len(ours) == 2 and all(p["state"]["status"] == "active" for p in ours):
            save("plugins", plugins)
            return agents
        time.sleep(.2)
    raise AssertionError("Location activation did not settle")


with server():
    # First caller on a cold location: the helper must handle asynchronous activation.
    plan = root / "plan"
    plan.write_text("* = fixture/trial\nminion = fixture/trial variant=high\n")
    exports = run([tools["bash"], module / "oconf.sh"], "oconf-cold",
                  {"OCONF_PLAN_FILE": str(plan)}, cwd="cold")
    override = shlex.split(exports)[1].split("=", 1)[1]
    agents = ready()
    save("agents", agents)
    assert agents[0]["id"] == "orchestrator"
    assert {p.stem for p in (emitted / "agents").glob("*.md")} | {"explore"} <= {a["id"] for a in agents}
    for kind in ["skill", "command"]:
        actual = api("GET", f"/api/{kind}")["data"]
        expected = ({p.parent.name for p in (emitted / "skills").glob("*/SKILL.md")} if kind == "skill"
                    else {p.stem for p in (emitted / "commands").glob("*.md")})
        assert expected <= {item["name"] for item in actual}
        save(kind, actual)
    normalized = api("GET", "/api/config")
    assert any(c.get("info", {}).get("experimental", {}).get("subagent_depth") == 2 for c in normalized)
    session = api("POST", "/api/session", {"location": {"directory": str(root / "work")}})["data"]["id"]
    cases = [("build", "shell", "pwd", "allow"), ("build", "shell", "sudo true", "deny"),
              ("build", "shell", "ssh example.invalid", "allow"),
              ("build", "shell", "chmod 600 file && kubectl rollout restart deployment/app", "allow"),
              ("build", "shell", "rm -rf /Users/chris/Downloads", "deny"),
              ("build", "shell", "rm -rf /tmp/opencode-cache", "allow"),
              ("minion", "subagent", "tiny", "allow"),
              ("minion", "subagent", "explore", "allow"), ("minion", "subagent", "build", "deny"),
              ("minion", "subagent", "minion", "deny"), ("build", "unknown_action", "anything", "allow"),
              ("build", "external_directory", "/nix/store/example", "allow"),
              ("build", "external_directory", str(root / "home/projects/ws/example"), "allow"),
              ("build", "external_directory", "/unrelated/example", "ask")]
    for agent, action, resource, expected in cases:
        answer = api("POST", f"/api/session/{session}/permission", {"agent": agent, "action": action, "resources": [resource]})["data"]
        assert answer["effect"] == expected, (agent, action, resource, answer)
        if expected == "ask":
            api("POST", f"/api/session/{session}/permission/{answer['id']}/reply", {"reply": "reject"})
    shells = []
    for cwd in ["work", "allowed/sub", "blocked/sub"]:
        payload = {"command": "printf '%s\\n%s\\n%s\\n' \"$PWD\" \"${DOTFILES_TEST-unset}\" \"$CARGO_INCREMENTAL\"",
                   "timeout": 10000, "metadata": {"sessionID": session}}
        if cwd != "work":
            payload["cwd"] = str(root / cwd)
        shell = api("POST", "/api/shell", payload)["data"]
        for _ in range(100):
            shell = api("GET", f"/api/shell/{shell['id']}")["data"]
            if shell["status"] != "running":
                break
            time.sleep(.05)
        output = Path(shell["file"]).read_text().splitlines()
        assert shell["exit"] == 0 and Path(output[0]).resolve() == (root / cwd).resolve()
        assert output[1:] == ["allowed" if cwd.startswith("allowed") else "unset", "0"]
        shells.append({"shell": shell, "output": output})
    save("shells", shells)
    assert not (root / "home/blocked-executed").exists()
    assert {"fixture/base", "fixture/trial"} <= set(run([binary, "models"], "models-warm").splitlines())
    # Client environment must not silently mutate the running shared server.
    observed = json.loads(run([binary, "api", "config.get", "--param", f"location[directory]={root / 'work'}"],
                              "client-override", {"OPENCODE_CONFIG_CONTENT": override}))
    assert observed == normalized

env["OPENCODE_CONFIG_CONTENT"] = override
with server():
    minion = next(a for a in ready() if a["id"] == "minion")
    assert minion["model"] == {"providerID": "fixture", "id": "trial", "variant": "high"}
    assert api("GET", "/api/config")[-1]["info"]["model"] == {"providerID": "fixture", "model": "trial"}
    save("overridden-minion", minion)
print("PASS: generated configuration, real shells/direnv, permissions, cold oconf and server overrides")

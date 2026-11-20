"""Small, bounded I/O primitives for the trusted maintenance control plane."""
from __future__ import annotations

import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPOSITORY = "averagechris/dotfiles"
MAX_JSON = 4_000_000


class Blocked(RuntimeError):
    """A failed precondition; never turn this into a successful merge."""


class Transient(Blocked):
    """A temporary transport failure that may be retried without accepting evidence."""


def require(condition, message):
    if not condition:
        raise Blocked(message)


def sha(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value), "invalid commit SHA")
    return value


def digest(data):
    return hashlib.sha256(data).hexdigest()


def dumps(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def json_bytes(data):
    require(len(data) <= MAX_JSON, "JSON exceeds size limit")
    return json.loads(data)


def read_json(path):
    return json_bytes(Path(path).read_bytes())


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(dumps(value) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def credential(name, env=None):
    """Load explicitly provisioned credentials, never workstation fallbacks."""
    root = os.environ.get("CREDENTIALS_DIRECTORY")
    if root:
        path = Path(root) / name
        if path.is_file():
            value = path.read_text().strip()
            require(value and "\n" not in value, f"invalid {name} credential")
            return value
    value = os.environ.get(env, "") if env else ""
    require(value and "\n" not in value, f"missing {name} credential")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class GitHub:
    """No arbitrary URLs, credential fallbacks, or response-body error logging."""
    def __init__(self, token):
        self.token = token

    def request(self, method, path, data=None, raw=False):
        require(path.startswith("/") and not path.startswith("//"), "invalid GitHub API path")
        url = "https://api.github.com" + path
        body = dumps(data).encode() if data is not None else None
        request = urllib.request.Request(url, data=body, method=method, headers={
            "Authorization": "Bearer " + self.token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
            "User-Agent": "dotfiles-maintenance",
        })
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=45) as response:
                value = response.read(MAX_JSON + 1)
        except urllib.error.HTTPError as error:
            # Artifact download redirects must never carry Authorization onward.
            if raw and error.code in (301, 302, 303, 307, 308):
                location = error.headers.get("Location", "")
                error.close()
                parsed = urllib.parse.urlsplit(location)
                host = parsed.hostname or ""
                require(parsed.scheme == "https" and not parsed.username and (
                    host.endswith(".blob.core.windows.net") or
                    host.endswith(".actions.githubusercontent.com") or
                    host.endswith(".s3.amazonaws.com")
                ), "unexpected artifact download host")
                try:
                    with urllib.request.build_opener(NoRedirect).open(location, timeout=45) as response:
                        value = response.read(MAX_JSON + 1)
                except urllib.error.HTTPError as download_error:
                    error_type = Transient if download_error.code == 429 or download_error.code >= 500 else Blocked
                    download_error.close()
                    raise error_type("GitHub artifact download failed") from None
                except (OSError, TimeoutError):
                    raise Transient("GitHub artifact download unavailable") from None
            else:
                error_type = Transient if error.code == 429 or error.code >= 500 else Blocked
                code = error.code
                error.close()
                raise error_type(f"GitHub request failed ({code}); check access or rate limits") from None
        except (OSError, TimeoutError):
            raise Transient("GitHub request unavailable") from None
        require(len(value) <= MAX_JSON, "GitHub response exceeds size limit")
        return value if raw else (json.loads(value) if value else None)

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, value):
        return self.request("POST", path, value)

    def file(self, path, ref):
        sha(ref)
        value = self.get(f"/repos/{REPOSITORY}/contents/{urllib.parse.quote(path, safe='/')}?ref={ref}")
        require(value.get("type") == "file" and value.get("encoding") == "base64", "expected a regular source file")
        return base64.b64decode(value["content"], validate=False)

    def pages(self, path, key=None):
        items = []
        for page in range(1, 21):
            result = self.get(path + ("&" if "?" in path else "?") + f"per_page=100&page={page}")
            batch = result[key] if key else result
            require(isinstance(batch, list), "invalid GitHub page")
            items.extend(batch)
            if len(batch) < 100:
                return items
        raise Blocked("GitHub pagination limit exceeded")

    def artifact(self, run_id, name):
        require(isinstance(run_id, int) and not isinstance(run_id, bool) and run_id > 0, "invalid run id")
        items = self.pages(f"/repos/{REPOSITORY}/actions/runs/{run_id}/artifacts", "artifacts")
        matches = [x for x in items if x["name"] == name and not x.get("expired")]
        require(len(matches) == 1, f"missing or ambiguous {name} artifact")
        data = self.request("GET", f"/repos/{REPOSITORY}/actions/artifacts/{int(matches[0]['id'])}/zip", raw=True)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            files = archive.infolist()
            require(len(files) == 1 and files[0].filename == "evidence.json" and files[0].file_size <= MAX_JSON,
                    "unexpected evidence archive")
            # Never extract artifact paths into a privileged checkout.
            return json_bytes(archive.read(files[0]))


def load_policy(root):
    data = (Path(root) / "maintenance/policy.json").read_bytes()
    policy = json_bytes(data)
    require(policy.get("schema") == 1 and policy.get("repository") == REPOSITORY, "unsupported maintenance policy")
    require(policy.get("model") == "gpt-6.1-sol" and policy.get("reasoning") == "high", "unexpected maintenance model")
    return policy, digest(data)

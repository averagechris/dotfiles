// Deployed by the dotfiles Home Manager OpenCode module. @direnv@ is
// substituted with the host's direnv binary at build time.
//
// On every bash tool invocation, OpenCode triggers the `shell.env` hook with
// the command's cwd (the tool's `workdir`). This plugin resolves the direnv
// environment for that directory with `direnv export json` and merges it into
// the command's environment. Subagents dispatched across repos therefore get
// each project's dev shell (via nix-direnv) transparently, without
// `nix develop --command` or `direnv exec` wrappers that would also bypass
// bash permission rules keyed on the underlying command.
//
// Behavior notes:
// - Only direnv-allowed .envrc files load; blocked or failing ones are
//   negative-cached briefly and skipped silently.
// - `direnv export json` diffs against OpenCode's own process env, which is
//   static for the process lifetime, so results are cacheable per .envrc
//   root. A file fingerprint (.envrc, flake.nix, flake.lock, ...) plus a TTL
//   approximates direnv's own watch list.
// - If OpenCode was launched inside a direnv environment, commands running in
//   directories *without* an .envrc still get the unload diff so they do not
//   inherit the launch repo's dev shell.
// - Exported nulls mean "unset". The hook merges over process.env and cannot
//   truly unset, so nulls become empty strings, which most tooling treats as
//   unset (`${VAR:-default}` semantics).

import { execFile } from "node:child_process"
import { existsSync, statSync } from "node:fs"
import os from "node:os"
import path from "node:path"

const DIRENV = "@direnv@"

const TTL_MS = 5 * 60 * 1000
const NEGATIVE_TTL_MS = 60 * 1000
// First load of a cold dev shell evaluates the flake; keep this generous.
const TIMEOUT_MS = 10 * 60 * 1000
const WATCHED_FILES = [".envrc", ".env", "flake.nix", "flake.lock", "shell.nix", "default.nix", "devenv.nix", "devenv.lock"]
const UNLOAD_KEY = "\u0000unload"

const cache = new Map()
const inflight = new Map()

function findEnvrcRoot(cwd) {
  let dir = path.resolve(cwd)
  const home = os.homedir()
  for (;;) {
    if (existsSync(path.join(dir, ".envrc"))) return dir
    if (dir === home) return null
    const parent = path.dirname(dir)
    if (parent === dir) return null
    dir = parent
  }
}

function fingerprint(root) {
  return WATCHED_FILES.map((name) => {
    try {
      return `${name}=${statSync(path.join(root, name)).mtimeMs}`
    } catch {
      return `${name}=absent`
    }
  }).join(";")
}

function direnvExport(cwd) {
  return new Promise((resolve) => {
    execFile(
      DIRENV,
      ["export", "json"],
      { cwd, env: process.env, timeout: TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024 },
      (error, stdout) => {
        if (error) return resolve(null)
        const text = stdout.toString().trim()
        if (!text) return resolve({})
        try {
          resolve(JSON.parse(text))
        } catch {
          resolve(null)
        }
      },
    )
  })
}

function resolveEnv(key, cwd, print) {
  const now = Date.now()
  const hit = cache.get(key)
  if (hit && hit.fingerprint === print && hit.expires > now) return Promise.resolve(hit.env)

  let pending = inflight.get(key)
  if (pending) return pending

  pending = direnvExport(cwd).then((exported) => {
    inflight.delete(key)
    if (exported === null) {
      cache.set(key, { fingerprint: print, expires: Date.now() + NEGATIVE_TTL_MS, env: null })
      return null
    }
    const env = {}
    for (const [name, value] of Object.entries(exported)) {
      env[name] = value === null ? "" : String(value)
    }
    cache.set(key, { fingerprint: print, expires: Date.now() + TTL_MS, env })
    return env
  })
  inflight.set(key, pending)
  return pending
}

export const DotfilesDirenv = async () => ({
  "shell.env": async (input, output) => {
    const cwd = input?.cwd
    if (!cwd) return
    let root
    try {
      root = findEnvrcRoot(cwd)
    } catch {
      return
    }
    let key
    let print
    if (root) {
      key = root
      print = fingerprint(root)
    } else if (process.env.DIRENV_DIR) {
      // No .envrc for this cwd, but OpenCode itself launched inside a direnv
      // environment: apply the unload diff so the launch repo's dev shell
      // does not leak into other projects. The diff is identical for every
      // envrc-less directory, so cache it once.
      key = UNLOAD_KEY
      print = "static"
    } else {
      return
    }
    const env = await resolveEnv(key, root ?? path.resolve(cwd), print)
    if (env) Object.assign(output.env, env)
  },
})

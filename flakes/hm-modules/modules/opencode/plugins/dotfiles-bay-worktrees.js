// Native OpenCode V2 worktree strategy backed by Bay. @bay@ is substituted by Nix.
import { Worktree } from "@opencode/plugin"
import { spawn } from "node:child_process"
import path from "node:path"

const BAY = "@bay@"
const MAX_OUTPUT = 1024 * 1024

function operationError(message, forceRequired) {
  return new Worktree.OperationError({ message, ...(forceRequired === undefined ? {} : { forceRequired }) })
}

function run(args, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason ?? new DOMException("Aborted", "AbortError"))
    const grouped = process.platform !== "win32"
    const child = spawn(BAY, args, { detached: grouped, stdio: ["ignore", "pipe", "pipe"] })
    const stdout = []
    const stderr = []
    let size = 0
    let overflow = false
    let settled = false
    let killTimer
    let escalationPending = false
    const finish = (fn, value) => {
      if (settled) return
      settled = true
      signal?.removeEventListener("abort", abort)
      // An exited Bay leader does not mean its process group is gone. Preserve
      // abort escalation until the bounded group cleanup has run.
      if (killTimer && !escalationPending) clearTimeout(killTimer)
      fn(value)
    }
    const kill = (kind) => {
      try {
        if (grouped && child.pid) process.kill(-child.pid, kind)
        else child.kill(kind)
      } catch (error) {
        if (error?.code !== "ESRCH") throw error
      }
    }
    const abort = () => {
      try { kill("SIGTERM") } catch (error) { return finish(reject, error) }
      escalationPending = true
      killTimer = setTimeout(() => {
        escalationPending = false
        try {
          // The short delay bounds PID-reuse exposure; only signal when this
          // process group still exists.
          if (grouped && child.pid) process.kill(-child.pid, 0)
          kill("SIGKILL")
        } catch (error) {
          if (error?.code !== "ESRCH") {
            // Cleanup is best-effort after the caller has already been told.
          }
        }
      }, 500)
      killTimer.unref?.()
    }
    signal?.addEventListener("abort", abort, { once: true })
    const collect = (target) => (chunk) => {
      size += chunk.length
      if (size > MAX_OUTPUT) {
        overflow = true
        try { kill("SIGTERM") } catch {}
        return
      }
      target.push(chunk)
    }
    child.stdout.on("data", collect(stdout))
    child.stderr.on("data", collect(stderr))
    child.on("error", (error) => finish(reject, error))
    child.on("close", (code, killedBy) => {
      if (overflow) return finish(reject, operationError("Bay output exceeded 1 MiB"))
      const out = Buffer.concat(stdout).toString("utf8").trim()
      const err = Buffer.concat(stderr).toString("utf8").trim()
      if (signal?.aborted || killedBy) return finish(reject, signal?.reason ?? new DOMException("Aborted", "AbortError"))
      if (code === 0) return finish(resolve, { out, err })
      let detail
      try { detail = JSON.parse(err)?.error } catch {}
      const kind = detail?.code
      finish(reject, operationError(detail?.message || err || `Bay exited with status ${code}`, kind === "unpublished_work" ? true : undefined))
    })
    if (signal?.aborted) abort()
  })
}

function parse(text, description) {
  try {
    // Bay's underlying jj operation may emit status before its final envelope.
    const value = JSON.parse(text.split("\n").at(-1))
    if (!value || value.schema !== 1) throw new Error("unsupported schema")
    return value
  } catch (error) {
    throw operationError(`Invalid Bay ${description} JSON: ${error.message}`)
  }
}

async function list(sourceDirectory, signal) {
  const value = parse((await run(["list", sourceDirectory, "--json"], signal)).out, "list")
  if (!Array.isArray(value.workspaces)) throw operationError("Invalid Bay list JSON: workspaces is not an array")
  return value.workspaces.flatMap((entry) => {
    if (!entry || entry.path === null || typeof entry.path !== "string") return []
    return [{ directory: entry.path, type: entry.kind === "main" ? "root" : "worktree" }]
  })
}

export default {
  id: "dotfiles-bay-worktrees",
  async setup(ctx) {
    // Worktree strategies are process-global and last-registration-wins. Probe the
    // location before registering so a Git-only OpenCode location retains Git.
    const canonical = ctx.location?.project?.canonical ?? ctx.location?.directory
    if (!canonical) return
    let entries
    try { entries = await list(canonical, new AbortController().signal) } catch { return }
    if (!entries.some((entry) => path.resolve(entry.directory) === path.resolve(canonical))) return

    await ctx.worktree.transform((editor) => editor.add({
      id: "bay",
      async list(sourceDirectory, { signal }) {
        return list(sourceDirectory, signal)
      },
      async create(input, { signal }) {
        const name = path.basename(path.resolve(input.directory))
        if (!name || name === "." || name === ".." || name.includes("..") || !/^[A-Za-z0-9._-]+$/.test(name)) {
          throw operationError(`Invalid Bay workspace name: ${JSON.stringify(name)}`)
        }
        const args = ["add", name, "--repo", input.sourceDirectory]
        if (input.branch) args.push("-r", input.branch)
        args.push("--json")
        const output = (await run(args, signal)).out
        try {
          const value = parse(output, "add")
          if (typeof value.workspace?.path === "string") return { directory: value.workspace.path }
        } catch {}
        // Older Bay builds may forward jj's status output despite --json. Read
        // the authoritative post-create inventory rather than guessing layout.
        const created = (await list(input.sourceDirectory, signal)).find((entry) =>
          entry.type === "worktree" && path.basename(entry.directory) === name
        )
        if (!created) throw operationError("Invalid Bay add result: created workspace is not discoverable")
        return { directory: created.directory }
      },
      async remove(input, { signal }) {
        const args = ["rm", input.directory]
        if (input.force) args.push("--force")
        args.push("--json")
        await run(args, signal)
      },
    }))
  },
}

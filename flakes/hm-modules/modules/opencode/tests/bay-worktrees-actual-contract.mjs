import assert from "node:assert/strict"
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { spawnSync } from "node:child_process"
import { pathToFileURL } from "node:url"

const [source, bay, jj] = process.argv.slice(2)
assert(source && bay && jj, "usage: bay-worktrees-actual-contract.mjs PLUGIN BAY JJ")
const temporary = await mkdtemp(path.join(os.tmpdir(), "bay-worktrees-actual-"))
const home = path.join(temporary, "home")
const projects = path.join(temporary, "projects")
const repo = path.join(projects, "demo")
await mkdir(path.join(home, ".config", "bay"), { recursive: true })
await mkdir(repo, { recursive: true })
process.env.HOME = home
process.env.XDG_CONFIG_HOME = path.join(home, ".config")
await writeFile(path.join(home, ".config", "bay", "config.toml"), `schema = 1\n[[groups]]\npath = ${JSON.stringify(projects)}\nworkspaces = "ws"\n`)
function command(binary, args, cwd = repo) {
  const result = spawnSync(binary, args, { cwd, encoding: "utf8" })
  assert.equal(result.status, 0, `${binary} ${args.join(" ")}\n${result.stderr}`)
}
command(jj, ["config", "set", "--user", "user.name", "contract"])
command(jj, ["config", "set", "--user", "user.email", "contract@example.invalid"])
command(jj, ["git", "init", repo])
let text = (await readFile(source, "utf8"))
  .replace('import { Worktree } from "@opencode/plugin"', 'class E extends Error { constructor(x){super(x.message);Object.assign(this,x)} }; const Worktree={OperationError:E}')
  .replaceAll("@bay@", bay)
const rendered = path.join(temporary, "plugin.mjs")
await writeFile(rendered, text)
const plugin = (await import(pathToFileURL(rendered))).default
let definition
await plugin.setup({ location: { directory: repo, project: { canonical: repo } }, worktree: { async transform(fn) { fn({ add(value) { definition = value } }) } } })
assert(definition, "actual Bay recognized the temporary jj repository")
const signal = new AbortController().signal
assert((await definition.list(repo, { signal })).some((entry) => entry.type === "root" && entry.directory === repo))
const created = await definition.create({ sourceDirectory: repo, directory: path.join(temporary, "requested", "task"), branch: "@" }, { signal })
assert(created.directory.endsWith("/ws/demo/task"), "Bay returned its managed path")
await writeFile(path.join(created.directory, "unpublished.txt"), "work\n")
await assert.rejects(definition.remove({ directory: created.directory, force: false }, { signal }), (error) => error.forceRequired === true)
await definition.remove({ directory: created.directory, force: true }, { signal })
const trash = path.join(projects, "ws", "demo", ".trash")
assert((await import("node:fs")).existsSync(trash), "forced removal remains recoverable in Bay trash")
console.log("Rendered plugin + actual Bay contract passed")

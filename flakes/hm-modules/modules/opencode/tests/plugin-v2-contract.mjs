import assert from "node:assert/strict"
import { chmod, copyFile, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { pathToFileURL } from "node:url"

const [direnvSource, rustSource] = process.argv.slice(2)
assert(direnvSource && rustSource, "usage: plugin-v2-contract.mjs DIRENV_PLUGIN RUST_PLUGIN")

const temporary = await mkdtemp(path.join(os.tmpdir(), "opencode-v2-plugin-test-"))
const fakeDirenv = path.join(temporary, "direnv")
await writeFile(fakeDirenv, `#!/bin/sh
count="$PWD/.direnv-calls"
n=0
[ ! -f "$count" ] || n=$(cat "$count")
printf '%s' $((n + 1)) > "$count"
[ ! -f "$PWD/.blocked" ] || exit 1
printf '{"PROJECT_ROOT":"%s","REMOVE_ME":null}' "$PWD"
`)
await chmod(fakeDirenv, 0o755)

const rendered = path.join(temporary, "dotfiles-direnv.mjs")
await writeFile(rendered, (await readFile(direnvSource, "utf8")).replaceAll("@direnv@", fakeDirenv))
const rustRendered = path.join(temporary, "dotfiles-rust-cache.mjs")
await copyFile(rustSource, rustRendered)

async function activate(file) {
  const plugin = (await import(pathToFileURL(file))).default
  assert.equal(typeof plugin.id, "string")
  assert.equal(typeof plugin.setup, "function")
  let callback
  await plugin.setup({
    shell: {
      async hook(name, value) {
        assert.equal(name, "create.before")
        callback = value
        return { dispose() {} }
      },
    },
  })
  assert.equal(typeof callback, "function")
  return callback
}

const direnvHook = await activate(rendered)
const rootA = path.join(temporary, "a")
const rootB = path.join(temporary, "b")
await Promise.all([rootA, rootB].map(async (root) => {
  await mkdir(root)
  await writeFile(path.join(root, ".envrc"), "use flake")
}))

const eventA = { cwd: rootA, env: { REMOVE_ME: "inherited" } }
const eventB = { cwd: rootB, env: {} }
await Promise.all([direnvHook(eventA), direnvHook(eventB)])
assert.equal(eventA.env.PROJECT_ROOT, rootA)
assert.equal(eventA.env.REMOVE_ME, "")
assert.equal(eventB.env.PROJECT_ROOT, rootB)
assert.equal(await readFile(path.join(rootA, ".direnv-calls"), "utf8"), "1")

await direnvHook({ cwd: rootA, env: {} })
assert.equal(await readFile(path.join(rootA, ".direnv-calls"), "utf8"), "1", "warm result is cached")
await new Promise((resolve) => setTimeout(resolve, 20))
await writeFile(path.join(rootA, "flake.nix"), "{}")
await direnvHook({ cwd: rootA, env: {} })
assert.equal(await readFile(path.join(rootA, ".direnv-calls"), "utf8"), "2", "watched file invalidates cache")

const blocked = path.join(temporary, "blocked")
await mkdir(blocked)
await Promise.all([writeFile(path.join(blocked, ".envrc"), "blocked"), writeFile(path.join(blocked, ".blocked"), "")])
const blockedEvent = { cwd: blocked, env: { SAFE: "kept" } }
await direnvHook(blockedEvent)
assert.deepEqual(blockedEvent.env, { SAFE: "kept" })

const rustHook = await activate(rustRendered)
const rustEvent = { cwd: rootA, env: { CARGO_INCREMENTAL: "1" } }
await rustHook(rustEvent)
assert.equal(rustEvent.env.CARGO_INCREMENTAL, "0")

console.log(`OpenCode V2 plugin contract passed; fixtures: ${temporary}`)

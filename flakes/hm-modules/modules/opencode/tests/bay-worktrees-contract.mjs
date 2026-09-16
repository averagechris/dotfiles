import assert from "node:assert/strict"
import { chmod, mkdtemp, readFile, writeFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { pathToFileURL } from "node:url"

const source = process.argv[2]
assert(source, "usage: bay-worktrees-contract.mjs PLUGIN")
const temporary = await mkdtemp(path.join(os.tmpdir(), "bay-worktrees-test-"))
const fakeBay = path.join(temporary, "bay")
const calls = path.join(temporary, "calls")
const marker = path.join(temporary, "descendant-marker")
const descendantPid = path.join(temporary, "descendant-pid")
await writeFile(fakeBay, `#!/usr/bin/env node
const fs=require("fs"); const a=process.argv.slice(2); fs.appendFileSync(${JSON.stringify(calls)},JSON.stringify(a)+"\\n");
const ok=x=>console.log(JSON.stringify({schema:1,...x}));
if(a[0]==="list") { if(a[1].includes("non-jj")) process.exit(3); if(a[1].includes("malformed")) return console.log("noise"); if(a[1].includes("hang")) { const {spawn}=require("child_process"); const c=spawn(process.execPath,["-e",${JSON.stringify(`process.on("SIGTERM",()=>{});require("fs").writeFileSync(${JSON.stringify(descendantPid)},String(process.pid));setTimeout(()=>require("fs").writeFileSync(${JSON.stringify(marker)},"escaped"),800);setInterval(()=>{},1000)`)}],{stdio:"ignore"}); return setInterval(()=>{},1000); } ok({workspaces:[{path:a[1],kind:"main"},{path:"/managed/task",kind:"workspace"},{path:null,kind:"workspace"}]}); }
else if(a[0]==="add") ok({workspace:{path:"/managed/actual"}});
else if(a[0]==="rm" && a[1].includes("dirty")) { console.error(JSON.stringify({schema:1,error:{code:"unpublished_work",message:"unpublished"}})); process.exit(4); }
else ok({removed:{}});
`)
await chmod(fakeBay, 0o755)
const rendered = path.join(temporary, "plugin.mjs")
let text = await readFile(source, "utf8")
text = text.replace('import { Worktree } from "@opencode/plugin"', 'class E extends Error { constructor(x){super(x.message);Object.assign(this,x)} }; const Worktree={OperationError:E}')
  .replaceAll("@bay@", fakeBay)
await writeFile(rendered, text)
const plugin = (await import(pathToFileURL(rendered))).default

async function setup(location) {
  let definition
  await plugin.setup({ location: { directory: location, project: { canonical: location } }, worktree: { async transform(fn) { fn({ add(value) { definition = value } }) } } })
  return definition
}
assert.equal(await setup(path.join(temporary, "non-jj")), undefined)
const root = path.join(temporary, "repo")
const definition = await setup(root)
assert.equal(definition.id, "bay")
const signal = new AbortController().signal
assert.deepEqual(await definition.list(root, { signal }), [{ directory: root, type: "root" }, { directory: "/managed/task", type: "worktree" }])
assert.deepEqual(await definition.create({ sourceDirectory: root, directory: "/requested/task", branch: "main@origin" }, { signal }), { directory: "/managed/actual" })
await definition.create({ sourceDirectory: root, directory: "/requested/no-branch" }, { signal })
await definition.remove({ directory: "/managed/task", force: true }, { signal })
await assert.rejects(definition.remove({ directory: "/managed/dirty", force: false }, { signal }), (error) => error.forceRequired === true)
await assert.rejects(definition.create({ sourceDirectory: root, directory: "/requested/bad..name" }, { signal }), /Invalid Bay workspace name/)
await assert.rejects(definition.list(path.join(temporary, "malformed"), { signal }), /Invalid Bay list JSON/)
const controller = new AbortController()
const hanging = definition.list(path.join(temporary, "hang"), { signal: controller.signal })
for (let attempt = 0; attempt < 100; attempt++) {
  try { await readFile(descendantPid); break } catch (error) { if (error.code !== "ENOENT") throw error }
  await new Promise((resolve) => setTimeout(resolve, 10))
}
await readFile(descendantPid)
controller.abort()
await assert.rejects(hanging, (error) => error.name === "AbortError")
await new Promise((resolve) => setTimeout(resolve, 900))
await assert.rejects(readFile(marker), (error) => error.code === "ENOENT", "aborted descendants cannot mutate later")
const orphan = Number(await readFile(descendantPid, "utf8"))
assert.throws(() => process.kill(orphan, 0), (error) => error.code === "ESRCH", "no descendant is left running")
const argv = (await readFile(calls, "utf8")).trim().split("\n").map(JSON.parse)
assert(argv.some((a) => JSON.stringify(a) === JSON.stringify(["add","task","--repo",root,"-r","main@origin","--json"])))
assert(argv.some((a) => JSON.stringify(a) === JSON.stringify(["add","no-branch","--repo",root,"--json"])))
assert(argv.some((a) => JSON.stringify(a) === JSON.stringify(["rm","/managed/task","--force","--json"])))
assert(argv.some((a) => JSON.stringify(a) === JSON.stringify(["list",root,"--json"])))
console.log("Bay worktree plugin contract passed")

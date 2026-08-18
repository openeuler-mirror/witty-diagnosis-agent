/**
 * 技能暴露对账的场景验证。
 *
 * 覆盖的历史缺陷：插件换 checkout 后，项目级 .opencode/skills 里的软链
 * 仍指向旧仓库且永不自愈——插件是新的、技能是旧的，报告因此用了过期的 skill。
 *
 * 运行：npx tsx test/skills/exposure.test.ts
 */
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import assert from "node:assert/strict"

import {
  discoverSkills,
  exposeSkillsToOpenCode,
  gatedSkillsDir,
  inspectSkillExposure,
} from "../../src/witty/skills/discovery"

const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "witty-expose-"))
const MARKER = ".witty-managed"
const GATED = "euler-rag-json-search"

let failed = 0
function scenario(name: string, fn: () => void) {
  try {
    fn()
    console.log(`  ✅ ${name}`)
  } catch (err: any) {
    failed++
    console.error(`  ❌ ${name}\n     ${err.message}`)
  }
}

/** 造一份 checkout（含 package.json，使归属判定成立）。 */
function makeCheckout(
  name: string,
  skillNames: string[],
  opts: { gated?: string[]; pkgName?: string } = {},
) {
  const root = path.join(ROOT, name)
  fs.mkdirSync(root, { recursive: true })
  fs.writeFileSync(path.join(root, "package.json"), JSON.stringify({ name: opts.pkgName ?? "witty-diagnosis-agent" }))
  const write = (base: string, s: string) => {
    const d = path.join(root, base, s)
    fs.mkdirSync(d, { recursive: true })
    fs.writeFileSync(path.join(d, "SKILL.md"), `---\nname: ${s}\ndescription: test\n---\n`)
  }
  for (const s of skillNames) write("skills", s)
  for (const s of opts.gated ?? []) write("skills-gated", s)
  return path.join(root, "skills")
}

let projectSeq = 0
function makeProject() {
  const p = path.join(ROOT, `proj-${++projectSeq}`)
  fs.mkdirSync(path.join(p, ".opencode"), { recursive: true })
  return p
}

const links = (p: string) => path.join(p, ".opencode", "skills")
const isLink = (p: string) => fs.lstatSync(p, { throwIfNoEntry: false })?.isSymbolicLink() ?? false
const isDir = (p: string) => {
  const st = fs.lstatSync(p, { throwIfNoEntry: false })
  return !!st && !st.isSymbolicLink() && st.isDirectory()
}

const CUR = makeCheckout("cur", ["disk", "net"], { gated: [GATED] })
const OLD = makeCheckout("old", ["disk", "net", "removed-skill"], { gated: [GATED] })
const THIRD = makeCheckout("third-party", ["net"], { pkgName: "someone-else" })
const skills = discoverSkills(CUR)
// 与 doctor 一致：已知集合须含门控技能，否则会被误判为孤儿
const names = new Set([...skills, ...discoverSkills(gatedSkillsDir(CUR))].map((s) => s.name))
const expose = (proj: string, known = false) =>
  exposeSkillsToOpenCode(skills, proj, CUR, { knownIssueEnabled: known })

console.log(`发现技能: ${skills.map((s) => s.name).join(", ")}\n`)
console.log("场景验证")

scenario("① 全新项目 → 建立目录级软链（1 条，而非 N 条）", () => {
  const p = makeProject()
  const r = expose(p)
  assert.equal(r.mode, "directory")
  assert.equal(r.unmanaged, false)
  assert.ok(isLink(links(p)), ".opencode/skills 应是软链")
  assert.equal(fs.readlinkSync(links(p)), CUR)
  assert.equal(r.exposed.length, skills.length)
  // 技能可通过该软链访问
  assert.ok(fs.existsSync(path.join(links(p), "disk", "SKILL.md")))
})

scenario("② 旧版逐技能软链（指向旧 checkout）→ 迁移为目录级软链", () => {
  const p = makeProject()
  fs.mkdirSync(links(p), { recursive: true })
  for (const n of ["disk", "net", "removed-skill"]) {
    fs.symlinkSync(path.join(OLD, n), path.join(links(p), n), "dir")
  }
  const r = expose(p)
  assert.equal(r.mode, "directory")
  assert.ok(isLink(links(p)))
  assert.equal(fs.readlinkSync(links(p)), CUR)
  assert.equal(r.pruned.length, 3, "三条旧链接都应被回收")
  // 旧 checkout 独有的技能不再可见
  assert.equal(fs.existsSync(path.join(links(p), "removed-skill")), false)
})

scenario("③ 目录级软链指向旧 checkout → 重指到当前安装", () => {
  const p = makeProject()
  fs.symlinkSync(OLD, links(p), "dir")
  const r = expose(p)
  assert.equal(fs.readlinkSync(links(p)), CUR)
  assert.deepEqual(r.repointed, ["skills"])
})

scenario("④ 悬空的目录级软链（安装根被删）→ 重指", () => {
  const p = makeProject()
  fs.symlinkSync(path.join(ROOT, "gone", "skills"), links(p), "dir")
  const r = expose(p)
  assert.equal(fs.readlinkSync(links(p)), CUR)
  assert.equal(r.unmanaged, false)
})

scenario("⑤ 默认（门控关闭）→ 目录级软链，且门控技能天然不可见", () => {
  const p = makeProject()
  const r = expose(p, false)
  assert.equal(r.mode, "directory", "这是默认路径，必须是目录级软链")
  assert.deepEqual(r.withheld, [GATED])
  assert.equal(fs.existsSync(path.join(links(p), GATED)), false, "门控技能必须不可见")
  assert.ok(fs.existsSync(path.join(links(p), "disk", "SKILL.md")))
})

scenario("⑥ 门控开启 → 退回逐技能模式，写入独占标记，门控技能暴露", () => {
  const p = makeProject()
  const r = expose(p, true)
  assert.equal(r.mode, "per-skill")
  assert.ok(isDir(links(p)), "应为真实目录")
  assert.ok(fs.existsSync(path.join(links(p), MARKER)), "应写入独占标记")
  assert.deepEqual(r.withheld, [])
  assert.ok(fs.existsSync(path.join(links(p), GATED)), "门控技能应暴露")
  assert.equal(r.exposed.length, skills.length + 1)
})

scenario("⑦ 形态往返切换：directory ⇄ per-skill，无残留", () => {
  const p = makeProject()
  expose(p, false)
  assert.ok(isLink(links(p)), "默认应是目录级软链")

  const on = expose(p, true)
  assert.equal(on.mode, "per-skill")
  assert.ok(isDir(links(p)), "软链应被拆除，换成独占真实目录")
  assert.ok(fs.existsSync(path.join(links(p), GATED)))

  const off = expose(p, false)
  assert.equal(off.mode, "directory")
  assert.ok(isLink(links(p)), "真实目录应被回收，变回软链")
  assert.equal(fs.readlinkSync(links(p)), CUR)
  assert.ok(off.pruned.length > 0, "旧逐技能链接应记入 pruned")
  assert.equal(fs.existsSync(path.join(links(p), GATED)), false, "门控技能重新不可见")
})

scenario("⑧ 用户自有真实目录（含真实内容）→ 一律不动，标记 unmanaged", () => {
  const p = makeProject()
  const mine = path.join(links(p), "my-own-skill")
  fs.mkdirSync(mine, { recursive: true })
  fs.writeFileSync(path.join(mine, "SKILL.md"), "用户自己的技能")
  const r = expose(p)
  assert.equal(r.unmanaged, true)
  assert.equal(r.exposed.length, 0)
  assert.equal(r.skipped.length, skills.length)
  assert.equal(fs.readFileSync(path.join(mine, "SKILL.md"), "utf8"), "用户自己的技能")
  assert.ok(isDir(links(p)), "不得被替换为软链")
})

scenario("⑨ 用户自有软链指向第三方仓库 → 不动", () => {
  const p = makeProject()
  fs.symlinkSync(THIRD, links(p), "dir")
  const r = expose(p)
  assert.equal(r.unmanaged, true)
  assert.equal(fs.readlinkSync(links(p)), THIRD, "第三方软链必须原样保留")
})

scenario("⑩ 幂等：连续两次结果一致，无重复重指/清理", () => {
  const p = makeProject()
  expose(p)
  const r = expose(p)
  assert.deepEqual(r.repointed, [])
  assert.deepEqual(r.pruned, [])
  assert.equal(fs.readlinkSync(links(p)), CUR)

  const q = makeProject()
  expose(q, false)
  const r2 = expose(q, false)
  assert.deepEqual(r2.repointed, [])
  assert.deepEqual(r2.pruned, [])
})

console.log("\ndoctor 自检（inspectSkillExposure）")

scenario("⑪ 未暴露 → absent", () => {
  const st = inspectSkillExposure(makeProject(), CUR, names)
  assert.equal(st.mode, "absent")
  assert.equal(st.matchesInstall, false)
})

scenario("⑫ 目录级软链且来自当前安装 → matchesInstall=true", () => {
  const p = makeProject()
  expose(p)
  const st = inspectSkillExposure(p, CUR, names)
  assert.equal(st.mode, "directory")
  assert.equal(st.target, CUR)
  assert.equal(st.matchesInstall, true)
  assert.equal(st.danglingCount, 0)
})

scenario("⑬ 指向旧 checkout → 能报出「技能来自其他安装」", () => {
  const p = makeProject()
  fs.symlinkSync(OLD, links(p), "dir")
  const st = inspectSkillExposure(p, CUR, names)
  assert.equal(st.mode, "directory")
  assert.equal(st.target, OLD)
  assert.equal(st.matchesInstall, false, "这正是此前无从得知、拖了很久的那个状态")
})

scenario("⑭ 悬空软链 → danglingCount=1", () => {
  const p = makeProject()
  fs.symlinkSync(path.join(ROOT, "gone", "skills"), links(p), "dir")
  const st = inspectSkillExposure(p, CUR, names)
  assert.equal(st.danglingCount, 1)
})

scenario("⑮ per-skill 形态含孤儿/悬空 → 如实计数", () => {
  const p = makeProject()
  expose(p, true)
  fs.symlinkSync(path.join(OLD, "removed-skill"), path.join(links(p), "removed-skill"), "dir")
  fs.symlinkSync(path.join(ROOT, "gone", "skills", "x"), path.join(links(p), "x"), "dir")
  const st = inspectSkillExposure(p, CUR, names)
  assert.equal(st.mode, "per-skill")
  assert.equal(st.orphanCount, 2, "removed-skill 与 x 都不在当前安装中")
  assert.equal(st.danglingCount, 1)
  assert.equal(st.matchesInstall, false)
})

scenario("⑯ 用户自有目录 → foreign 且带说明", () => {
  const p = makeProject()
  fs.mkdirSync(path.join(links(p), "mine"), { recursive: true })
  fs.writeFileSync(path.join(links(p), "mine", "SKILL.md"), "x")
  const st = inspectSkillExposure(p, CUR, names)
  assert.equal(st.mode, "foreign")
  assert.ok(st.detail && st.detail.length > 0)
})

fs.rmSync(ROOT, { recursive: true, force: true })
if (failed > 0) {
  console.error(`\n${failed} 项失败`)
  process.exit(1)
}
console.log("\n全部通过")

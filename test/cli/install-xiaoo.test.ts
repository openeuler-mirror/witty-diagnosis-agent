/**
 * xiaoO 安装路径的场景验证。
 *
 * 背景：rpm 不附带 install.sh，xiaoO 的安装能力此前只存在于源码安装脚本里，
 * 导致 rpm 装完只能用 OpenCode——而 xiaoO 资源明明打进了包。本测试覆盖
 * 移植进 CLI 后的行为，重点是拷贝形态特有的两个腐化点：权限位与陈旧技能。
 *
 * 运行：npx tsx test/cli/install-xiaoo.test.ts
 */
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import assert from "node:assert/strict"

const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "witty-xiaoo-"))
const HOME = path.join(ROOT, "home")
const CONFIG = path.join(ROOT, "config")
process.env.XIAOO_HOME = HOME
process.env.XIAOO_CONFIG_DIR = CONFIG

const { runXiaooInstall } = await import("../../src/witty/cli/install-xiaoo")

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

const cfgFile = path.join(CONFIG, "config.toml")
const skillCount = (d: string) =>
  fs.existsSync(d) ? fs.readdirSync(d).filter((n) => fs.existsSync(path.join(d, n, "SKILL.md"))).length : 0

console.log("xiaoO 安装场景")

scenario("① 首次安装：技能 / 门控技能 / command / tools / config 全部就位", () => {
  const r = runXiaooInstall()
  assert.equal(r.skills, 45)
  assert.equal(r.gatedSkills, 1)
  assert.equal(r.configCreated, true, "配置不存在时应写入模板")
  assert.equal(skillCount(path.join(HOME, "skills")), 45)
  assert.equal(skillCount(path.join(HOME, "skills-gated")), 1)
  assert.ok(fs.readdirSync(path.join(HOME, "command")).length > 0)
  assert.ok(fs.readdirSync(path.join(HOME, "tools")).length > 0)
  assert.ok(fs.existsSync(cfgFile))
})

scenario("② 可执行位保留（拷贝形态最易丢的东西）", () => {
  const src = path.join(process.cwd(), "skills")
  const want = fs
    .readdirSync(src)
    .flatMap((s) => {
      const d = path.join(src, s, "scripts")
      return fs.existsSync(d) ? fs.readdirSync(d).map((f) => path.join(d, f)) : []
    })
    .filter((f) => /\.(py|sh)$/.test(f) && fs.statSync(f).mode & 0o100)
  assert.ok(want.length > 0, "源中应存在带 x 位的脚本")
  const got = want.filter((f) => {
    const rel = path.relative(src, f)
    const t = path.join(HOME, "skills", rel)
    return fs.existsSync(t) && fs.statSync(t).mode & 0o100
  })
  assert.equal(got.length, want.length, `${want.length} 个可执行脚本应全部保留 x 位`)
})

scenario("③ 写入技能清单，且不含用户自放技能", () => {
  const manifest = path.join(HOME, "skills", ".witty-skills-manifest")
  assert.ok(fs.existsSync(manifest))
  const names = fs.readFileSync(manifest, "utf8").trim().split("\n")
  assert.equal(names.length, 45)
  assert.ok(!names.includes("my-own-skill"))
})

scenario("④ 幂等：重复安装不产生变化、不误删", () => {
  const before = fs.readdirSync(path.join(HOME, "skills")).sort().join(",")
  const r = runXiaooInstall()
  assert.deepEqual(r.removedSkills, [])
  assert.equal(r.configCreated, false, "配置已存在 ⇒ 走合并分支")
  assert.equal(fs.readdirSync(path.join(HOME, "skills")).sort().join(","), before)
})

scenario("⑤ 配置合并：用户自有段保留，witty 段不重复累积", () => {
  // 模拟用户自有配置
  const user = '[llm]\nprovider = "deepseek"\n\n[hooker]\nplugins = ["/x/y.json"]\n'
  fs.writeFileSync(cfgFile, user)
  runXiaooInstall()
  let text = fs.readFileSync(cfgFile, "utf8")
  assert.ok(text.includes("[llm]"), "用户 [llm] 段必须保留")
  assert.ok(text.includes("[hooker]"), "用户 [hooker] 段必须保留")
  assert.ok(text.includes("[agent.baize]"), "witty agent 段应被合并进来")

  runXiaooInstall()
  text = fs.readFileSync(cfgFile, "utf8")
  const markers = (text.match(/# >>> witty-diagnosis-agent xiaoO config >>>/g) || []).length
  assert.equal(markers, 1, "重复安装不得累积多份 witty 段")
  assert.equal((text.match(/^\[agent\.baize\]$/gm) || []).length, 1, "agent.baize 只应有一份")
  assert.equal((text.match(/^\[llm\]$/gm) || []).length, 1, "用户段不得被复制")
})

scenario("⑥ 对账：源中已删的技能被移除，用户自放技能保留", () => {
  const dst = path.join(HOME, "skills")
  fs.mkdirSync(path.join(dst, "my-own-skill"), { recursive: true })
  fs.writeFileSync(path.join(dst, "my-own-skill", "SKILL.md"), "用户自己的")
  // 伪造清单：声称上次装过一个现已不存在的技能
  const manifest = path.join(dst, ".witty-skills-manifest")
  fs.appendFileSync(manifest, "ghost-skill\n")
  fs.mkdirSync(path.join(dst, "ghost-skill"), { recursive: true })
  fs.writeFileSync(path.join(dst, "ghost-skill", "SKILL.md"), "上次装的")

  const r = runXiaooInstall()
  assert.ok(r.removedSkills.includes("ghost-skill"), "源中已无 ⇒ 应移除")
  assert.equal(fs.existsSync(path.join(dst, "ghost-skill")), false)
  assert.ok(fs.existsSync(path.join(dst, "my-own-skill", "SKILL.md")), "用户自放技能不在清单中 ⇒ 不得删")
})

scenario("⑦ dry-run 不落盘", () => {
  const probe = path.join(ROOT, "dry", "home")
  process.env.XIAOO_HOME = probe
  process.env.XIAOO_CONFIG_DIR = path.join(ROOT, "dry", "config")
  const r = runXiaooInstall({ dryRun: true })
  assert.equal(r.skills, 45)
  assert.equal(fs.existsSync(probe), false, "dry-run 不应创建任何目录")
  process.env.XIAOO_HOME = HOME
  process.env.XIAOO_CONFIG_DIR = CONFIG
})

fs.rmSync(ROOT, { recursive: true, force: true })
if (failed > 0) {
  console.error(`\n${failed} 项失败`)
  process.exit(1)
}
console.log("\n全部通过")

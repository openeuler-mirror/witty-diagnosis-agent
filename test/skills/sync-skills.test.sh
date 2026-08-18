#!/usr/bin/env bash
# install.sh 中 sync_skills() 的场景验证：权限位保留 + 按清单对账。
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 抽出 sync_skills 及其依赖（print_success 打桩）
print_success() { :; }
eval "$(awk '/^SKILLS_MANIFEST=/,/^}$/' "$REPO/install.sh" | sed -n '1,/^}$/p')"

fail=0
ok()  { echo "  ✅ $1"; }
bad() { echo "  ❌ $1"; fail=$((fail+1)); }

mk_skill() { mkdir -p "$1/$2"; printf -- '---\nname: %s\n---\n' "$2" > "$1/$2/SKILL.md"; }

SRC="$TMP/src"; DST="$TMP/dst"
mk_skill "$SRC" alpha; mk_skill "$SRC" beta; mk_skill "$SRC" gamma
printf '#!/bin/sh\necho hi\n' > "$SRC/alpha/run.sh"; chmod 755 "$SRC/alpha/run.sh"

echo "sync_skills 场景验证"

sync_skills "$SRC" "$DST"
[ -f "$DST/alpha/SKILL.md" ] && [ -f "$DST/gamma/SKILL.md" ] \
  && ok "① 首次同步：技能全部拷入" || bad "① 首次同步"
[ -x "$DST/alpha/run.sh" ] && ok "② 可执行位保留（cp -a，原 cp -R 会丢）" || bad "② 可执行位丢失"
[ -f "$DST/.witty-skills-manifest" ] && ok "③ 写入技能清单" || bad "③ 未写清单"
[ "$(wc -l < "$DST/.witty-skills-manifest" | tr -d ' ')" = "3" ] \
  && ok "④ 清单含 3 个技能" || bad "④ 清单条目数不对"

# 用户自行放入的技能不得被删
mk_skill "$DST" my-own
# 源中删除 beta，模拟技能被移除
rm -rf "$SRC/beta"
sync_skills "$SRC" "$DST"
[ ! -d "$DST/beta" ] && ok "⑤ 源中已删除的技能被移除（原 cp -R 会永久残留）" || bad "⑤ beta 仍残留"
[ -f "$DST/my-own/SKILL.md" ] && ok "⑥ 用户自行放入的技能保留不动" || bad "⑥ 误删用户技能"
[ -f "$DST/alpha/SKILL.md" ] && [ -f "$DST/gamma/SKILL.md" ] \
  && ok "⑦ 其余技能不受影响" || bad "⑦ 其余技能受损"

# 内容更新应覆盖
printf -- '---\nname: alpha\nv: 2\n---\n' > "$SRC/alpha/SKILL.md"
sync_skills "$SRC" "$DST"
grep -q "v: 2" "$DST/alpha/SKILL.md" && ok "⑧ 内容变更被覆盖同步" || bad "⑧ 内容未更新"

# 幂等
before="$(find "$DST" | sort | md5)"
sync_skills "$SRC" "$DST"
[ "$(find "$DST" | sort | md5)" = "$before" ] && ok "⑨ 幂等：重复执行无变化" || bad "⑨ 非幂等"

# 目标目录不存在时应能创建
sync_skills "$SRC" "$TMP/fresh/skills"
[ -f "$TMP/fresh/skills/alpha/SKILL.md" ] && ok "⑩ 目标目录不存在时自动创建" || bad "⑩ 未创建目标目录"

[ "$fail" -eq 0 ] && { echo; echo "全部通过"; exit 0; } || { echo; echo "$fail 项失败"; exit 1; }

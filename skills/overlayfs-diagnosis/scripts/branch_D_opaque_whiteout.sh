#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_D_opaque_whiteout.sh
# 用途：Opaque Whiteout 诊断 —— 文件在 overlay 中"消失"的问题
# 场景：挂载成功但 merged 中某些文件/目录不显示；upper 中有 whiteout 节点
# 使用：bash branch_D_opaque_whiteout.sh [mount_point] [container_id]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"
CONTAINER="${2:-}"

echo "=================================================================="
echo " 分支D：Opaque Whiteout 诊断 —— 文件\"消失\"问题"
echo "=================================================================="

# --------------------------------------------------------------------------
# D1. 基础检查：确认 overlay 挂载状态
# --------------------------------------------------------------------------
echo ""
echo "【D1】Overlay 挂载状态"
echo "------------------------------------------------------------------"

if [[ -n "${TARGET}" && -d "${TARGET}" ]]; then
  echo "挂载点正常: ${TARGET}"
  mount | grep -E "^overlay" | grep "${TARGET}" || echo "  （目标未在 mount 表中？）"
else
  echo "挂载点: ${TARGET:-"（未指定，自动检测）"}"
  mount | grep -E "^overlay" | head -3
fi

# --------------------------------------------------------------------------
# D2. Whiteout 扫描
# --------------------------------------------------------------------------
echo ""
echo "【D2】Whiteout 节点扫描"
echo "------------------------------------------------------------------"

# 定位 upperdir
UPPER_DIRS=""
for line in $(mount | grep -E "^overlay" | awk '{print $1, $3}'); do
  OPTIONS=$(mount | grep -E "^overlay" | grep "$line" | grep -oP 'upperdir=[^, ]+' | head -1 | cut -d'=' -f2 2>/dev/null || true)
  [[ -n "${OPTIONS}" ]] && UPPER_DIRS="${UPPER_DIRS} ${OPTIONS}"
done

if [[ -z "${UPPER_DIRS}" && -d /var/lib/docker/overlay2 ]]; then
  # Docker 场景：检查所有 diff 目录
  UPPER_DIRS=$(find /var/lib/docker/overlay2 -maxdepth 2 -name "diff" -type d 2>/dev/null | head -10)
fi

if [[ -z "${UPPER_DIRS}" && -n "${TARGET}" ]]; then
  echo "未定位到 upperdir，尝试从挂载信息提取..."
  mount | grep overlay | grep -oP 'upperdir=[^, ]+' | cut -d'=' -f2
fi

echo ""
echo "--- 扫描 Whiteout 文件（传统 .wh. 前缀） ---"
UPPER_ROOT=$(echo "${UPPER_DIRS}" | awk '{print $1}')
if [[ -n "${UPPER_ROOT}" ]]; then
  WH_COUNT=$(find "${UPPER_ROOT}" -name ".wh.*" 2>/dev/null | wc -l)
  echo "找到 ${WH_COUNT} 个 whiteout 文件"
  if [[ "${WH_COUNT}" -gt 0 ]]; then
    echo ""
    echo "Top 20 whiteout 路径："
    find "${UPPER_ROOT}" -name ".wh.*" 2>/dev/null | head -20
  fi
fi

echo ""
echo "--- 扫描 Whiteout 文件（通过 xattr） ---"
XATTR_WH_COUNT=$(find ${UPPER_DIRS} -exec getfattr -d -m trusted.overlay.whiteout {} \; 2>/dev/null | grep -c "trusted.overlay.whiteout" || echo 0)
if [[ "${XATTR_WH_COUNT}" -gt 0 ]]; then
  echo "找到 ${XATTR_WH_COUNT} 个 xattr whiteout 文件"
fi

echo ""
echo "--- 扫描 Opaque 目录标记 ---"
OPAQUE_COUNT=$(find ${UPPER_DIRS} -exec getfattr -d -m trusted.overlay.opaque {} \; 2>/dev/null | grep -c "trusted.overlay.opaque" || echo 0)
if [[ "${OPAQUE_COUNT}" -gt 0 ]]; then
  echo "找到 ${OPAQUE_COUNT} 个 opaque 标记目录"
  echo ""
  echo "Opaque 目录列表："
  find ${UPPER_DIRS} -exec getfattr -d -m trusted.overlay.opaque {} \; 2>/dev/null | grep -B1 "trusted.overlay.opaque" | grep "file:" | head -20
fi

# --------------------------------------------------------------------------
# D3. 模拟文件可见性测试
# --------------------------------------------------------------------------
echo ""
echo "【D3】文件可见性交叉验证"
echo "------------------------------------------------------------------"

for upper_root in ${UPPER_DIRS}; do
  if [[ ! -d "${upper_root}" ]]; then
    continue
  fi

  echo "检查 upper 目录: ${upper_root}"

  # 找 upper 中的 visible 文件（非 whiteout）
  VISIBLE_FILES=$(find "${upper_root}" -not -name ".wh.*" -type f 2>/dev/null | head -10)
  if [[ -n "${VISIBLE_FILES}" ]]; then
    echo "  upper 中存在可见文件："
    echo "${VISIBLE_FILES}" | head -5 | while IFS= read -r f; do
      echo "    ${f}"
    done
  fi

  # 找 whiteout 遮盖的文件——对比 upper 和 merged
  if [[ -n "${TARGET}" && -d "${TARGET}" ]]; then
    echo ""
    echo "  whiteout 遮盖的文件（检查 merged 中是否存在）："
    find "${upper_root}" -name ".wh.*" 2>/dev/null | head -10 | while IFS= read -r wh; do
      WH_NAME=$(basename "${wh}" | sed 's/^\.wh\.//')
      # 在 merged 中查找
      MERGED_FILE=$(find "${TARGET}" -name "${WH_NAME}" 2>/dev/null | head -1)
      if [[ -z "${MERGED_FILE}" ]]; then
        echo "    ✓ $(basename ${wh}) → merged 中不可见（预期行为）"
      else
        echo "    ⚠️ $(basename ${wh}) → merged 中仍可见 ${MERGED_FILE}（可能 whiteout 未生效）"
      fi
    done
  fi
done

# --------------------------------------------------------------------------
# D4. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【D4】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

根据检查结果选择应对措施：

场景1：不期望的 whiteout 导致文件消失（误删除）
  恢复：移除 upper 中的 whiteout 节点
    rm -f /upper/path/.wh.filename
  注意：这只是让文件在 merged 中再次可见，实际是重新暴露 lower 文件

场景2：不期望的 opaque 目录导致子目录内容消失
  恢复：移除 opaque 标记
    setfattr -x trusted.overlay.opaque /upper/dir
  或：
    attr -r trusted.overlay.opaque /upper/dir

场景3：Docker 容器中文件异常消失
  方案：
    ① 确认容器层中是否有异常 whiteout
       docker diff <container> | grep "C\|A" | head -20
    ② 检查是否由于容器内删除操作留下的 whiteout
    ③ 考虑重建容器而非修复 whiteout
    ④ Docker 场景建议：docker export + docker import 重建纯净层

场景4：误判——预期行为（确实想删除 lower 文件）
  说明：whiteout 是 overlay 的正确行为机制。
  如果文件是在 merged 中删除的，内核自动在 upper 创建 whiteout。
  这是预期行为，不是故障。
FIX_SUGGESTIONS

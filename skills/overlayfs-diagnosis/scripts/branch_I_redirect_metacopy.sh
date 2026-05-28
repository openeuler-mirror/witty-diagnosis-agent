#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_I_redirect_metacopy.sh
# 用途：redirect_dir / metacopy 冲突诊断
# 场景：符号链接行为异常、目录重命名后文件丢失、readlink 返回异常路径
# 使用：bash branch_I_redirect_metacopy.sh [mount_point]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"

echo "=================================================================="
echo " 分支I：redirect_dir / metacopy 冲突诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# I1. 确认 overlay 模块参数
# --------------------------------------------------------------------------
echo ""
echo "【I1】Overlay 模块参数与挂载选项"
echo "------------------------------------------------------------------"

echo "--- /sys/module/overlay/parameters/ ---"
for param in /sys/module/overlay/parameters/*; do
  [[ -f "${param}" ]] && echo "  $(basename ${param}) = $(cat ${param})"
done 2>/dev/null || echo "  （无法访问，可能是内置模块）"

echo ""
echo "--- 当前挂载选项 ---"
if [[ -n "${TARGET}" ]]; then
  mount | grep overlay | grep "${TARGET}" || true
else
  mount | grep overlay | head -5
fi

# --------------------------------------------------------------------------
# I2. Redirect xattr 检查
# --------------------------------------------------------------------------
echo ""
echo "【I2】Redirect xattr 扫描"
echo "------------------------------------------------------------------"

# 尝试从挂载中提取 upperdir
UPPER_DIRS=$(mount | grep overlay | grep -oP 'upperdir=[^, ]+' | cut -d'=' -f2 2>/dev/null || true)
if [[ -z "${UPPER_DIRS}" && -d /var/lib/docker/overlay2 ]]; then
  UPPER_DIRS=$(find /var/lib/docker/overlay2 -maxdepth 2 -name "diff" -type d 2>/dev/null | head -5)
fi

for upper in ${UPPER_DIRS}; do
  if [[ ! -d "${upper}" ]]; then
    continue
  fi
  echo "扫描 upper 目录: ${upper}"
  REDIRECT_COUNT=$(find "${upper}" -exec getfattr -d -m trusted.overlay.redirect {} \; 2>/dev/null | grep -c "trusted.overlay.redirect" || echo 0)
  if [[ "${REDIRECT_COUNT}" -gt 0 ]]; then
    echo "  找到 ${REDIRECT_COUNT} 个 redirect 标记"
    echo "  redirect 目录："
    find "${upper}" -exec getfattr -d -m trusted.overlay.redirect {} \; 2>/dev/null | \
      grep -B1 "trusted.overlay.redirect" | grep "file:" | head -10
    echo ""
    echo "  redirect 值："
    find "${upper}" -exec getfattr -n trusted.overlay.redirect {} \; 2>/dev/null | \
      grep -v "^$" | head -10
  else
    echo "  （无 redirect 标记）"
  fi
  echo ""
done

# --------------------------------------------------------------------------
# I3. Metacopy xattr 检查
# --------------------------------------------------------------------------
echo ""
echo "【I3】Metacopy xattr 扫描"
echo "------------------------------------------------------------------"

for upper in ${UPPER_DIRS}; do
  if [[ ! -d "${upper}" ]]; then
    continue
  fi
  echo "扫描 upper 目录: ${upper}"
  METACOPY_COUNT=$(find "${upper}" -exec getfattr -d -m trusted.overlay.metacopy {} \; 2>/dev/null | grep -c "trusted.overlay.metacopy" || echo 0)
  if [[ "${METACOPY_COUNT}" -gt 0 ]]; then
    echo "  找到 ${METACOPY_COUNT} 个 metacopy 标记文件"
    find "${upper}" -exec getfattr -n trusted.overlay.metacopy {} \; 2>/dev/null | \
      grep -v "^$" | head -10
  else
    echo "  （无 metacopy 标记，或内核未启用 metacopy）"
  fi
  echo ""
done

# --------------------------------------------------------------------------
# I4. 功能测试：目录重命名与访问
# --------------------------------------------------------------------------
echo ""
echo "【I4】功能测试：目录重命名行为"
echo "------------------------------------------------------------------"

if [[ -z "${TARGET}" || ! -d "${TARGET}" ]]; then
  TARGET=$(mount | grep overlay | head -1 | awk '{print $3}')
fi

if [[ -n "${TARGET}" && -d "${TARGET}" ]]; then
  echo "测试挂载点: ${TARGET}"

  TEST_BASE="${TARGET}/.redirect_test_$(date +%s)"
  mkdir -p "${TEST_BASE}/dir1"
  echo "original" > "${TEST_BASE}/dir1/file.txt"

  echo "  创建原目录: ${TEST_BASE}/dir1/"
  echo "  重命名为 dir2..."
  mv "${TEST_BASE}/dir1" "${TEST_BASE}/dir2" 2>&1 || echo "  重命名失败"

  if [[ -f "${TEST_BASE}/dir2/file.txt" ]]; then
    echo "  ✓ 重命名后文件可访问"
    echo "  ✓ 文件内容: $(cat "${TEST_BASE}/dir2/file.txt")"
  else
    echo "  ✗ 重命名后文件不可访问"
  fi

  echo ""
  echo "  检查 upper 中的 redirect xattr："
  for upper in ${UPPER_DIRS}; do
    getfattr -d -m trusted.overlay.redirect "${upper}/.redirect_test_"* 2>/dev/null | head -5
  done

  rm -rf "${TEST_BASE}" 2>/dev/null || true
  echo ""
  echo "  测试清理完成"
else
  echo "  挂载点不可用，跳过功能测试。"
fi

# --------------------------------------------------------------------------
# I5. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【I5】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

redirect_dir / metacopy 问题处理：

场景1：redirect_dir 行为不符合预期
  确认内核版本（redirect_dir 在 v4.18+ 支持）
  确认内核模块运行时参数：cat /sys/module/overlay/parameters/redirect_dir
  ⚠️ 部分环境（如 WSL2）默认 redirect_dir=N，即使不指定挂载选项也会禁用
    此为内核模块参数默认值，非故障，需通过显式挂载选项覆盖
  若确认关闭，显式指定 redirect_dir 策略：
    mount -t overlay overlay \
      -o lowerdir=/lower,upperdir=/upper,workdir=/work,\
         redirect_dir=on /merged
  redirect_dir 模式说明：
    on       - 启用（默认 v4.18+），允许目录重命名跨层追踪
    off      - 禁用，目录重命名后无法追踪
    follow   - 跟随 redirect 到新位置
    nofollow - 不跟随 redirect

场景2：手动删除/修改 redirect xattr 导致问题
  修复：重新设置正确的 redirect 值
    setfattr -n trusted.overlay.redirect -v "/new/relative/path" /upper/dir

场景3：metacopy 导致文件访问异常（如打开文件获错误内容）
  确认内核版本 >= v5.10
  如问题持续，尝试禁用 metacopy：
    mount -t overlay overlay \
      -o lowerdir=/lower,upperdir=/upper,workdir=/work,\
         metacopy=off /merged

场景4：Docker 场景下的 redirect/metacopy
  Docker 使用默认参数处理 redirect_dir 和 metacopy
  不建议手动修改 Docker 管理的 overlay 层中的 xattr
  如果容器出现相关异常，重建容器通常是最简单的修复方式
    docker stop <container>
    docker rm <container>
    docker run ... (重新创建)
FIX_SUGGESTIONS

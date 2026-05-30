#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_J_permission.sh
# 用途：OverlayFS 元数据/权限问题诊断
# 场景：文件写入报 "Read-only file system" 但 upperdir 可写；权限检查异常
# 使用：bash branch_J_permission.sh [mount_point]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"

echo "=================================================================="
echo " 分支J：OverlayFS 元数据/权限问题诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# J1. 挂载选项检查
# --------------------------------------------------------------------------
echo ""
echo "【J1】挂载选项检查"
echo "------------------------------------------------------------------"

if [[ -n "${TARGET}" ]]; then
  echo "目标挂载点: ${TARGET}"
  mount | grep overlay | grep "${TARGET}" || echo "  （mount 表中未找到）"
  findmnt -t overlay "${TARGET}" 2>/dev/null | head -5 || true
else
  echo "所有 overlay 挂载："
  mount | grep -E "^overlay" | head -5
fi

echo ""
echo "--- 检查 ro/rw 选项 ---"
for mnt in $(mount | grep -E "^overlay" | awk '{print $3}'); do
  if mount | grep "${mnt}" | grep -q "ro," || mount | grep "${mnt}" | grep -q "(ro,"; then
    echo "  ✗ ${mnt} → 只读挂载（ro）"
  else
    echo "  ✓ ${mnt} → 读写挂载（rw）"
  fi
done

# --------------------------------------------------------------------------
# J2. 权限逐层检查
# --------------------------------------------------------------------------
echo ""
echo "【J2】各层目录权限检查"
echo "------------------------------------------------------------------"

while IFS= read -r line; do
  OPTIONS=$(echo "$line" | awk -F ' - ' '{print $2}' 2>/dev/null || echo "$line")

  for dir_param in "upperdir" "lowerdir" "workdir"; do
    DIR_VAL=$(echo "$OPTIONS" | grep -oP "${dir_param}=\K[^, ]+" 2>/dev/null || true)
    if [[ -n "${DIR_VAL}" ]]; then
      FIRST_DIR=$(echo "${DIR_VAL}" | cut -d':' -f1)
      if [[ -e "${FIRST_DIR}" ]]; then
        PERM=$(stat -c "%A (%a)" "${FIRST_DIR}" 2>/dev/null)
        OWNER=$(stat -c "%U:%G" "${FIRST_DIR}" 2>/dev/null)
        echo "  ${dir_param}: ${FIRST_DIR} → ${PERM} owner=${OWNER}"

        # 写权限检查
        if [[ "${dir_param}" == "upperdir" || "${dir_param}" == "workdir" ]]; then
          TEST_FILE="${FIRST_DIR}/.perm_test_$(date +%s)"
          if touch "${TEST_FILE}" 2>/dev/null; then
            echo "    ✓ 可写"
            rm -f "${TEST_FILE}" 2>/dev/null || true
          else
            echo "    ✗ 不可写！检查权限或 ACL"
            ls -ld "${FIRST_DIR}"
          fi
        fi
      else
        echo "  ${dir_param}: ${FIRST_DIR} → [路径不存在]"
      fi
    fi
  done
done < <(mount | grep -E "^overlay" 2>/dev/null || echo "${TARGET}")

# --------------------------------------------------------------------------
# J3. ACL 与 SELinux 检查
# --------------------------------------------------------------------------
echo ""
echo "【J3】ACL 与 SELinux 检查"
echo "------------------------------------------------------------------"

if command -v getfacl &>/dev/null; then
  echo "ACL 状态（overlay 相关目录）："
  for dir in /merged /upper /work; do
    [[ -d "${dir}" ]] && getfacl "${dir}" 2>/dev/null | head -10 && echo ""
  done
else
  echo "  getfacl 未安装。"
fi

if command -v getenforce &>/dev/null; then
  echo "SELinux 状态: $(getenforce 2>/dev/null)"
  if [[ -n "${TARGET}" ]]; then
    echo "上下文件类型:"
    ls -Z "${TARGET}" 2>/dev/null | head -5 || echo "  （不可用）"
  fi
else
  echo "  SELinux 未启用或不可用。"
fi

# --------------------------------------------------------------------------
# J4. 实际写入测试
# --------------------------------------------------------------------------
echo ""
echo "【J4】merged 层写入测试"
echo "------------------------------------------------------------------"

if [[ -z "${TARGET}" || ! -d "${TARGET}" ]]; then
  TARGET=$(mount | grep overlay | head -1 | awk '{print $3}')
fi

if [[ -n "${TARGET}" && -d "${TARGET}" ]]; then
  echo "测试挂载点: ${TARGET}"

  # 写入新文件
  echo "  测试1: 创建新文件"
  echo "test" > "${TARGET}/.write_test_$(date +%s)" 2>&1 && echo "    ✓ 成功" || echo "    ✗ 失败"

  # 修改已有文件
  EXISTING=$(find "${TARGET}" -type f 2>/dev/null | head -1)
  if [[ -n "${EXISTING}" ]]; then
    echo "  测试2: 修改已有文件（${EXISTING}）"
    touch "${EXISTING}" 2>&1 && echo "    ✓ 成功" || echo "    ✗ 失败"
  fi

  # 创建目录
  echo "  测试3: 创建目录"
  mkdir -p "${TARGET}/.dir_test_$(date +%s)" 2>&1 && echo "    ✓ 成功" || echo "    ✗ 失败"

  # 清理
  rm -rf "${TARGET}/.write_test_"* "${TARGET}/.dir_test_"* 2>/dev/null || true
  echo "  清理完成"
fi

# --------------------------------------------------------------------------
# J5. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【J5】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

OverlayFS 权限问题处理：

场景1：upperdir 可写但 merged 报只读
  可能原因：挂载时指定了 ro 选项
  修复：
    # 重新挂载为读写
    mount -o remount,rw /merged
    # 或卸载后重新挂载（去掉 ro 选项）

场景2：SELinux 标签导致无法访问
  修复：
    # 方式 A：恢复标签
    restorecon -R /merged
    # 方式 B：设置 Allow 或临时关闭（仅调试时）
    setenforce 0
    # 确认问题是否由 SELinux 引起

场景3：文件系统 ACL 拒绝访问
  修复：
    setfacl -m u:container_user:rwx /upperdir/path

场景4：Docker 场景下的权限问题
  Docker 自动处理 upper/work 目录的所有权和权限
  如果需要手动修复特定容器的权限：
    docker exec -u root <container> chown -R user:group /path
  ⚠️ 不建议直接修改 /var/lib/docker/overlay2 下的权限
FIX_SUGGESTIONS

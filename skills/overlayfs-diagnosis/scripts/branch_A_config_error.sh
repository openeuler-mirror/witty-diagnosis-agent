#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_A_config_error.sh
# 用途：OverlayFS 配置错误诊断 —— upper/lower/work 目录配置问题
# 场景：mount 失败，dmesg 含 "failed to get directory" / "not supported as upperdir"
#       / "failed to create workdir" / "failed to get kernel config"
# 使用：bash branch_A_config_error.sh [mount_point] [container_id]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"
CONTAINER="${2:-}"

# 自动检测挂载点（若未指定）
if [[ -z "${TARGET}" ]]; then
  TARGET=$(mount | grep overlay | head -1 | awk '{print $3}')
fi

# 若 mount 表中无 overlay 记录（挂载失败场景），尝试从 dmesg 提取路径
if [[ -z "${TARGET}" ]]; then
  DMESG_DIR=$(dmesg 2>/dev/null | grep -oP "upperdir=\K[^, ]+" | head -1 || true)
  if [[ -n "${DMESG_DIR}" ]]; then
    TARGET=$(dirname "${DMESG_DIR}" 2>/dev/null || true)
    echo "  （从 dmesg 提取到 upperdir 路径: ${DMESG_DIR}）"
  fi
fi

echo "=================================================================="
echo " 分支A：OverlayFS 配置错误诊断"
echo " 目标：${TARGET:-"（未检测到 overlay 挂载，分析错误现场）"}"
echo "=================================================================="

# --------------------------------------------------------------------------
# A1. 系统态诊断：确认配置状态
# --------------------------------------------------------------------------
echo ""
echo "【A1】配置状态检查"
echo "------------------------------------------------------------------"

if [[ -n "${TARGET}" ]]; then
  echo "挂载点存在，运行中配置："
  cat /proc/self/mountinfo | grep overlay | grep "${TARGET}" || echo "  （mountinfo 中未找到）"
  echo ""
fi

# 检查 dmesg 中的配置错误
echo "dmesg 中最近的 overlay 相关错误："
dmesg 2>/dev/null | grep -iE "overlay.*failed|overlay.*error|overlay.*not supported|overlay.*config" | tail -10 || echo "  （无）"

# --------------------------------------------------------------------------
# A2. 逐项配置检查
# --------------------------------------------------------------------------
echo ""
echo "【A2】逐项配置验证"
echo "------------------------------------------------------------------"

# 遍历所有 overlay 挂载的目录检查
while IFS= read -r line; do
  OPTIONS=$(echo "$line" | awk -F ' - ' '{print $2}' 2>/dev/null || echo "$line")

  for dir_param in "upperdir" "lowerdir" "workdir"; do
    DIR_VAL=$(echo "$OPTIONS" | grep -oP "${dir_param}=\K[^, ]+" 2>/dev/null || true)
    if [[ -n "${DIR_VAL}" ]]; then
      echo "检查 ${dir_param}=${DIR_VAL}"

      if [[ -e "${DIR_VAL}" ]]; then
        echo "  ✓ 路径存在"

        # 权限检查
        if [[ -r "${DIR_VAL}" ]]; then
          echo "  ✓ 可读"
        else
          echo "  ✗ 不可读"
        fi

        if [[ "${dir_param}" == "upperdir" || "${dir_param}" == "workdir" ]]; then
          if [[ -w "${DIR_VAL}" ]]; then
            echo "  ✓ 可写"
          else
            echo "  ✗ 不可写（必须可写）"
          fi
        fi

        # 文件系统类型
        FS_TYPE=$(df -hT "${DIR_VAL}" 2>/dev/null | tail -1 | awk '{print $2}')
        echo "  文件系统: ${FS_TYPE}"

        # xattr 支持检查（仅 upperdir）
        if [[ "${dir_param}" == "upperdir" ]]; then
          TEST_FILE="${DIR_VAL}/.overlay_test_$(date +%s)"
          if touch "${TEST_FILE}" 2>/dev/null; then
            if setfattr -n trusted.overlay.test -v "1" "${TEST_FILE}" 2>/dev/null &&
               getfattr -n trusted.overlay.test "${TEST_FILE}" 2>/dev/null | grep -q "trusted.overlay.test"; then
              echo "  ✓ xattr（trusted 命名空间）支持"
            else
              echo "  ✗ xattr（trusted 命名空间）不支持！overlay 必需的"
            fi
            rm -f "${TEST_FILE}" 2>/dev/null || true
          else
            echo "  ✗ 无法在 upperdir 创建测试文件（磁盘满或权限不足）"
          fi
        fi
      else
        echo "  ✗ 路径不存在！"
      fi
      echo ""
    fi
  done

  # upperdir 和 workdir 同设备检查
  UPPER=$(echo "$OPTIONS" | grep -oP 'upperdir=\K[^, ]+' 2>/dev/null || true)
  WORK=$(echo "$OPTIONS" | grep -oP 'workdir=\K[^, ]+' 2>/dev/null || true)
  if [[ -n "${UPPER}" && -n "${WORK}" && -e "${UPPER}" && -e "${WORK}" ]]; then
    UPPER_DEV=$(stat -c "%d" "${UPPER}" 2>/dev/null)
    WORK_DEV=$(stat -c "%d" "${WORK}" 2>/dev/null)
    if [[ "${UPPER_DEV}" == "${WORK_DEV}" ]]; then
      echo "  ✓ upper/work 在同一设备（设备号: ${UPPER_DEV}）"
    else
      echo "  ✗ upper/work 跨设备（upper:${UPPER_DEV} vs work:${WORK_DEV}）— 必须同一设备"
    fi
  fi
done < <(mount | grep -E "^overlay" 2>/dev/null || echo "${TARGET}")

# --------------------------------------------------------------------------
# A3. Kernel 配置检查
# --------------------------------------------------------------------------
echo ""
echo "【A3】内核配置检查"
echo "------------------------------------------------------------------"

if [[ -f /proc/config.gz ]]; then
  zcat /proc/config.gz 2>/dev/null | grep CONFIG_OVERLAY_FS | head -20 || echo "  /proc/config.gz 中未找到 overlay 配置"
elif [[ -f /boot/config-$(uname -r) ]]; then
  grep CONFIG_OVERLAY_FS "/boot/config-$(uname -r)" 2>/dev/null || echo "  内核配置文件中未找到 overlay 配置"
else
  echo "  无法访问内核配置文件（/proc/config.gz 不可用）"
  echo "  提示：若 CONFIG_OVERLAY_FS 未编译，需重新编译内核或换用支持 overlay 的发行版"
fi

# --------------------------------------------------------------------------
# A4. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【A4】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

根据上述检查结果选择对应的修复措施：

问题1：upperdir/workdir 路径不存在或权限不足
  修复：
    mkdir -p /path/to/upper /path/to/work
    chmod 755 /path/to/upper /path/to/work

问题2：upperdir/workdir 跨设备
  修复：
    将 upperdir 和 workdir 放在同一文件系统：
    mount --bind /same/fs/dir /path/to/upper
    mount --bind /same/fs/dir /path/to/work

问题3：upperdir 文件系统不支持 trusted xattr
  修复：
    换用 ext4/xfs 等本地文件系统；
    或确认挂载时未用 -o noxattr

问题4：CONFIG_OVERLAY_FS 未编译
  修复：
    重新编译内核启用 CONFIG_OVERLAY_FS=y 或 =m
    或使用支持 overlay 的发行版内核

问题5：内核版本太旧（< 3.18）
  修复：
    升级内核至 3.18+（推荐 4.0+）
FIX_SUGGESTIONS

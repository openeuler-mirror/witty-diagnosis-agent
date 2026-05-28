#!/usr/bin/env bash
# =============================================================================
# 脚本：cleanup_all.sh
# 用途：OverlayFS 故障注入测试 —— 全局清理
# 说明：
#   1. 停止并删除所有故障注入测试容器
#   2. 清理宿主机上的测试残留（临时文件、loop 设备、挂载点）
#   3. 可选删除基础镜像
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

CONTAINER_PREFIX="overlayfs-fault"

echo ""
echo "======================================================================"
echo " OverlayFS 故障注入 — 全局清理"
echo "======================================================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. 清理所有测试容器
# ─────────────────────────────────────────────────────────────────────────────

echo "▸ 步骤 1/4: 清理测试容器"
echo "----------------------------------------------------------------------"

for key in A B C D E F G H I J K Z; do
    name="${CONTAINER_PREFIX}-${key}"
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "  清理容器: ${name}"
        docker rm -f "${name}" >/dev/null 2>&1 || warn "  容器 ${name} 移除失败"
    fi
done

# 清理任何其他以 overlayfs-fault 开头的容器
echo ""
echo "  检查其他 overlayfs-fault 容器..."
for name in $(docker ps -a --format '{{.Names}}' | grep "^${CONTAINER_PREFIX}" 2>/dev/null || true); do
    echo "  清理残留容器: ${name}"
    docker rm -f "${name}" >/dev/null 2>&1 || true
done

echo "  ✓ 容器清理完成"

# ─────────────────────────────────────────────────────────────────────────────
# 2. 清理宿主机上的临时文件
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "▸ 步骤 2/4: 清理临时文件"
echo "----------------------------------------------------------------------"

# 清理测试输出目录
TEST_OUTPUT_DIRS=(
    "/tmp/overlayfs_fault_test"
    "/tmp/overlay_test_"*
    "/tmp/overlayfs_diagnosis_"*
)

for dir_pattern in "${TEST_OUTPUT_DIRS[@]}"; do
    for dir in $(ls -d ${dir_pattern} 2>/dev/null || true); do
        if [[ -d "${dir}" ]]; then
            echo "  删除临时目录: ${dir}"
            rm -rf "${dir}" 2>/dev/null || warn "  无法删除 ${dir}"
        fi
    done
done

# 清理容器内可能残留的临时文件（通过再次启动容器清理的方式比较重）
# 改为通过 Docker 卷或直接清理

echo "  ✓ 临时文件清理完成"

# ─────────────────────────────────────────────────────────────────────────────
# 3. 清理 Loop 设备
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "▸ 步骤 3/4: 检查并清理 loop 设备"
echo "----------------------------------------------------------------------"

# 列出当前使用的 loop 设备
LOOP_DEVICES=$(losetup -a 2>/dev/null | grep -o '/dev/loop[0-9]*' || true)
if [[ -n "${LOOP_DEVICES}" ]]; then
    echo "  当前活跃 loop 设备:"
    echo "${LOOP_DEVICES}" | while read -r dev; do
        echo "    ${dev}"
    done

    # 注意：不要随意 detach 所有 loop 设备，只清理测试中创建的镜像
    # 查找 /tmp 目录下的镜像文件对应的 loop 设备
    echo ""
    echo "  检查 /tmp 中测试镜像关联的 loop 设备..."
    for img in /tmp/loop_dev_*.img /tmp/vfat_img /tmp/xattr_test.img; do
        if [[ -f "${img}" ]]; then
            DEV=$(losetup -j "${img}" 2>/dev/null | grep -o '/dev/loop[0-9]*' || true)
            if [[ -n "${DEV}" ]]; then
                echo "    解绑: ${DEV} ← ${img}"
                losetup -d "${DEV}" 2>/dev/null || warn "    解绑 ${DEV} 失败"
            fi
            echo "    删除镜像文件: ${img}"
            rm -f "${img}" 2>/dev/null || true
        fi
    done
else
    echo "  无活跃 loop 设备"
fi

echo "  ✓ Loop 设备清理完成"

# ─────────────────────────────────────────────────────────────────────────────
# 4. 可选：删除基础镜像
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "▸ 步骤 4/4: Docker 镜像管理"
echo "----------------------------------------------------------------------"

if docker image inspect overlayfs-fault-base:latest &>/dev/null; then
    echo "  Docker 镜像 overlayfs-fault-base:latest 存在"
    read -r -p "  是否删除？(y/N) " confirm
    if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
        docker rmi overlayfs-fault-base:latest >/dev/null 2>&1 && \
            echo "  ✓ 镜像已删除" || warn "  镜像删除失败"
    else
        echo "  保留镜像"
    fi
else
    echo "  无 overlayfs-fault-base 镜像"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 完成
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "======================================================================"
echo " 清理完成"
echo "======================================================================"
echo ""
echo "清理内容汇总:"
echo "  • Docker 容器: 已移除所有 ${CONTAINER_PREFIX}-* 容器"
echo "  • 临时文件:   已清理 /tmp 下的测试数据"
echo "  • Loop 设备:  已检查并清理"
echo "  • Docker 镜像: $(docker image inspect overlayfs-fault-base:latest &>/dev/null && echo '保留' || echo '已删除')"
echo ""
echo "如遇到残留问题，可手动执行:"
echo "  docker ps -a | grep overlayfs-fault  # 检查残留容器"
echo "  losetup -a                            # 检查残留 loop 设备"
echo "  rm -rf /tmp/overlay_test_*            # 强制清理测试目录"
echo "======================================================================"

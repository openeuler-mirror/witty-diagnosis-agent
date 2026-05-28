#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_Z_general.sh
# 用途：OverlayFS 通用诊断 —— 无明确匹配时的兜底分支
# 场景：无法匹配到特定分支类型，或需要完整系统检查
# 使用：bash branch_Z_general.sh [mount_point]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"

echo "=================================================================="
echo " 分支Z：OverlayFS 通用故障诊断"
echo " 使用场景：无明确匹配分支时的全面检查"
echo "=================================================================="

# --------------------------------------------------------------------------
# Z1. 系统级健康检查
# --------------------------------------------------------------------------
echo ""
echo "【Z1】系统级健康检查"
echo "------------------------------------------------------------------"

echo "--- CPU 与内存 ---"
echo "  CPU 负载: $(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')"
echo "  内存: $(free -h 2>/dev/null | grep Mem | awk '{print $3 " / " $2}')"

echo ""
echo "--- 磁盘 I/O（overlay 相关分区）---"
for mp in /var/lib/docker / /merged; do
  if [[ -d "${mp}" ]]; then
    DEV=$(df -h "${mp}" 2>/dev/null | tail -1 | awk '{print $1}')
    echo "  ${mp} (${DEV}): "
    iostat -x "${DEV}" 1 1 2>/dev/null | tail -3 | head -1 || echo "    iostat 不可用"
  fi
done

echo ""
echo "--- 打开文件描述符（overlay 相关）---"
if command -v lsof &>/dev/null; then
  OVL_FDS=$(lsof 2>/dev/null | grep -c "overlay" || echo 0)
  echo "  overlay 相关打开文件: ${OVL_FDS}"
else
  echo "  lsof 不可用"
fi

# --------------------------------------------------------------------------
# Z2. 全量 dmesg 扫描
# --------------------------------------------------------------------------
echo ""
echo "【Z2】dmesg 全量扫描"
echo "------------------------------------------------------------------"

echo "最近 50 条内核消息："
dmesg 2>/dev/null | tail -50

echo ""
echo "--- 异常关键字扫描 ---"
dmesg 2>/dev/null | grep -iE "error|fail|warning|bug|panic|corrupt|iowait|timeout" | tail -20 || echo "  无异常关键词"

# --------------------------------------------------------------------------
# Z3. 控制变量实验：最小化复现环境
# --------------------------------------------------------------------------
echo ""
echo "【Z3】最小化复现环境指引"
echo "------------------------------------------------------------------"

TMPDIR="${TMPDIR:-/tmp}/overlay_minimal_test_$(date +%s)"
cat << 'REPRODUCE'

若上述检查未定位到根因，搭建最小化 OverlayFS 环境进行控制变量实验：

Step 1: 创建隔离测试环境
  TMPDIR=/tmp/overlay_test
  mkdir -p $TMPDIR/{lower,upper,work,merged}
  echo "Hello from lower" > $TMPDIR/lower/test.txt

Step 2: 用相同参数挂载
  mount -t overlay overlay \
    -o lowerdir=$TMPDIR/lower,upperdir=$TMPDIR/upper,workdir=$TMPDIR/work \
    $TMPDIR/merged

Step 3: 验证基本功能
  cat $TMPDIR/merged/test.txt     # 预期: "Hello from lower"
  echo "modified" > $TMPDIR/merged/test.txt  # 写入触发 copy-up
  ls -la $TMPDIR/upper/            # 检查 copy-up 结果

Step 4: 逐步引入复杂配置复现原问题
  添加更多 lower 层:
    mkdir -p $TMPDIR/lower2
    mount -t overlay overlay \
      -o lowerdir=$TMPDIR/lower2:$TMPDIR/lower,...
  启用 redirect_dir:
    ... -o redirect_dir=on ...
  启用 metacopy:
    ... -o metacopy=on ...

Step 5: 测试完成后清理
  umount $TMPDIR/merged
  rm -rf $TMPDIR

REPRODUCE

echo "自动创建最小化环境..."
mkdir -p "${TMPDIR}"/{lower,upper,work,merged}
echo "test content" > "${TMPDIR}/lower/test.txt"
echo "  测试目录: ${TMPDIR}"

if mount -t overlay overlay -o lowerdir="${TMPDIR}/lower",upperdir="${TMPDIR}/upper",workdir="${TMPDIR}/work" "${TMPDIR}/merged" 2>/dev/null; then
  echo "  ✓ 最小化 overlay 挂载成功"

  echo "  基本功能验证:"
  cat "${TMPDIR}/merged/test.txt" 2>/dev/null && echo "    ✓ 读取 OK" || echo "    ✗ 读取失败"
  echo "write test" > "${TMPDIR}/merged/test.txt" 2>/dev/null && echo "    ✓ 写入 OK" || echo "    ✗ 写入失败"

  # 验证 copy-up
  if [[ -f "${TMPDIR}/upper/test.txt" ]]; then
    echo "    ✓ Copy-up 成功（文件已出现在 upper）"
    echo "    upper 内容: $(cat ${TMPDIR}/upper/test.txt)"
  fi

  umount "${TMPDIR}/merged" 2>/dev/null
else
  echo "  ✗ 最小化 overlay 挂载失败"
  dmesg 2>/dev/null | grep -i overlay | tail -5
fi

rm -rf "${TMPDIR}" 2>/dev/null || true
echo "  测试环境清理完成"

# --------------------------------------------------------------------------
# Z4. 诊断结论汇总
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【Z4】诊断结论汇总"
echo "=================================================================="
cat << 'SUMMARY'

完成以上检查后，汇总发现的问题：

1. 是否有配置错误？
   [ ] upperdir/lowerdir/workdir 路径错误
   [ ] 跨设备 overlay
   [ ] 文件系统不兼容

2. 是否有 xattr 异常？
   [ ] 异常 whiteout
   [ ] 异常 opaque 标记
   [ ] redirect 标记异常
   [ ] metacopy 标记异常

3. 是否有性能问题？
   [ ] Copy-up 延迟
   [ ] readdir 缓慢
   [ ] inode 耗尽

4. 是否有功能受限？
   [ ] inotify 不工作
   [ ] 权限拒绝

5. 是否属于预期行为？
   [ ] OverlayFS 内核限制（需文档确认）
   [ ] 用户预期偏差

根据汇总结果：
  - 找到明确根因 → 执行对应修复建议
  - 无法确定 → 在最小化环境中逐步复现
  - 疑似内核 Bug → 检查内核邮件列表或提交 Bug report

SUMMARY

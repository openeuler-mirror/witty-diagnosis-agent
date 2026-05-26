#!/usr/bin/env python3
# H3C iBMC - Step4: 故障汇总分析（纯原生 Python，无第三方依赖）
# 用法: python3 step4_summary.py [日志根目录]

import os
import sys
import re
import glob
from datetime import datetime

LOG_DIR = sys.argv[1] if len(sys.argv) > 1 else "."

CRITICAL_KEYWORDS = {
    "hardware":    ["degraded", "offline", "rebuild", "failed", "missing",
                    "pd failed", "vd degraded", "phy reset", "link down",
                    "reallocated sector", "uncorrectable", "pending sector",
                    "comm lost", "assert"],
    "bios":        ["no bootable device", "boot device not found", "secure boot violation",
                    "uefi variable", "no boot", "pxe boot"],
    "grub":        ["grub rescue", "no such partition", "unknown filesystem",
                    "error: file not found", "grub>", "error: unknown command",
                    "error: no such device"],
    "filesystem":  ["read-only file system", "i/o error", "ext4-fs error",
                    "xfs error", "no space left", "superblock", "fsck"],
    "kernel":      ["kernel panic", "not syncing", "call trace", "oops",
                    "kernel not found", "no init found", "initramfs unpacking failed"],
}

SCAN_FILES = [
    "current_event.txt", "RAID_Controller_Info.txt",
    "LSI_RAID_Controller_Log", "arm_fdm_log", "fdm_me_log",
    "security_log", "User_dfl.log", "kbox_info",
]

def scan_file(filepath, max_lines=400):
    results = []
    try:
        with open(filepath, "r", errors="replace") as f:
            for i, line in enumerate(f):
                if i >= max_lines:
                    break
                ll = line.lower()
                for layer, keywords in CRITICAL_KEYWORDS.items():
                    for kw in keywords:
                        if kw in ll:
                            results.append({
                                "layer": layer,
                                "keyword": kw,
                                "line": line.strip()[:120],
                                "source": os.path.basename(filepath),
                                "lineno": i + 1,
                            })
    except Exception:
        pass
    return results

# ── 主程序 ──────────────────────────────────────────
print("=" * 60)
print("H3C iBMC GRUB 故障汇总分析")
print(f"分析时间 : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print(f"日志目录 : {os.path.realpath(LOG_DIR)}")
print("=" * 60)

# 1. 目录结构探测
print("\n【日志包结构探测】")
key_dirs = ["LogDump", "AppDump", "RTOSDump", "OSDump", "SpLogDump"]
for d in key_dirs:
    hits = glob.glob(os.path.join(LOG_DIR, "**", d), recursive=True)
    if hits:
        fcount = len(os.listdir(hits[0])) if os.path.isdir(hits[0]) else 0
        print(f"  ✓ {d:<15} ({fcount} 文件) → {hits[0]}")
    else:
        print(f"  ✗ {d:<15} [未找到]")

# systemcom.tar 特别提示
syscom = glob.glob(os.path.join(LOG_DIR, "**/systemcom.tar"), recursive=True)
if syscom:
    print(f"\n  [重要] 控制台日志包: {syscom[0]}")
    print("         → 已由 step3_grub_os_check.sh 解压分析，请参考其输出")

# SMART 汇总
print("\n【磁盘 SMART 状态汇总】")
smart_files = glob.glob(os.path.join(LOG_DIR, "**/PD_SMART_INFO_C*"), recursive=True)
if smart_files:
    bad_attrs = ["reallocated sector", "uncorrectable", "pending sector",
                 "offline uncorrectable", "spin retry"]
    for sf in smart_files:
        disk_id = os.path.basename(sf)
        issues = []
        try:
            with open(sf, errors='replace') as f:
                content = f.read().lower()
            for attr in bad_attrs:
                if attr in content:
                    # 找原始行，检查数值是否非零
                    for raw_line in content.split('\n'):
                        if attr in raw_line:
                            nums = re.findall(r'\d+', raw_line)
                            # 取最后3个数字（通常是value/worst/raw）
                            if nums and any(int(n) > 0 for n in nums[-3:] if int(n) < 10**9):
                                issues.append(f"{attr.title()}: {raw_line.strip()[:60]}")
        except Exception:
            pass
        if issues:
            print(f"  ⚠️  {disk_id}")
            for issue in issues[:3]:
                print(f"       {issue}")
        else:
            print(f"  ✓  {disk_id}: SMART 未见明显异常")
else:
    print("  [INFO] 未找到 SMART 文件")

# 全量扫描
all_findings = []
scanned = []
for fname in SCAN_FILES:
    for fpath in glob.glob(os.path.join(LOG_DIR, "**", fname), recursive=True):
        scanned.append(fpath)
        all_findings.extend(scan_file(fpath))

print(f"\n【扫描文件数】{len(scanned)} 个")

# 分层输出
by_layer = {layer: [] for layer in CRITICAL_KEYWORDS}
for item in all_findings:
    by_layer[item["layer"]].append(item)

print("\n【分层故障证据】")
priority_order = ["hardware", "bios", "grub", "filesystem", "kernel"]
active_layers = []
for layer in priority_order:
    items = by_layer[layer]
    if not items:
        print(f"  [{layer.upper():12}] ── 无异常")
        continue
    active_layers.append(layer)
    print(f"\n  [{layer.upper():12}] ── {len(items)} 条异常 ⚠️")
    seen = set()
    shown = 0
    for item in items:
        sig = item["keyword"] + item["line"][:40]
        if sig in seen or shown >= 8:
            continue
        seen.add(sig)
        shown += 1
        print(f"    来源: {item['source']} (行 {item['lineno']})")
        print(f"    关键字: '{item['keyword']}'  内容: {item['line']}")

# 诊断方向
print("\n【初步诊断方向】")
if not active_layers:
    print("  ⚪ 未发现明显关键字，建议重点检查 systemcom.tar 和 current_event.txt")
else:
    top = active_layers[0]
    msgs = {
        "hardware":   "🔴 硬件层异常 → 优先检查RAID控制器状态和磁盘SMART数据",
        "bios":       "🟠 固件层异常 → 检查BIOS启动顺序/Secure Boot配置",
        "grub":       "🟡 GRUB层异常 → 重点检查 systemcom.tar 中的控制台输出",
        "filesystem": "🟡 文件系统异常 → 检查分区完整性和kbox_info",
        "kernel":     "🟡 内核层异常 → 检查kbox_info和截图文件",
    }
    print(f"  {msgs[top]}")
    if len(active_layers) > 1:
        print(f"  → 次要异常层: {', '.join(active_layers[1:])}")

print("\n" + "=" * 60)
print("请将以上完整输出提供给 AI 进行深度故障链分析。")
print("=" * 60)

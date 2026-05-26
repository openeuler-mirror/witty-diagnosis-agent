#!/usr/bin/env python3
# 华为 iBMC - Step4: 故障汇总分析（纯原生 Python，无第三方依赖）
# 用法: python3 step4_summary.py [日志根目录]
# 输出: 结构化故障摘要（直接打印，可重定向到文件）

import os
import sys
import re
import glob
from datetime import datetime

LOG_DIR = sys.argv[1] if len(sys.argv) > 1 else "."

# 各层关键字定义（越靠前优先级越高）
CRITICAL_KEYWORDS = {
    "hardware":    ["offline", "degraded", "comm lost", "rebuild", "missing disk",
                    "pd failed", "vd failed", "assert", "drive failure"],
    "bios":        ["boot device not found", "no bootable device", "secure boot",
                    "uefi variable", "boot order", "legacy mode"],
    "grub":        ["grub rescue", "no such partition", "unknown filesystem",
                    "error: file not found", "grub>", "error: unknown command"],
    "filesystem":  ["read-only file system", "i/o error", "ext4-fs error",
                    "xfs error", "no space left", "superblock"],
    "kernel":      ["kernel panic", "not syncing", "call trace", "oops",
                    "kernel not found", "no init found", "initramfs unpacking failed"],
}

# 扫描目标文件
SCAN_FILES = [
    "fdm_output", "fdm_output.txt",
    "sel.db", "sel.log",
    "RAID_Controller_Info.txt",
    "StorageMgnt_dfl.log",
    "BMC_dfl.log",
    "BIOS_dfl.log",
    "card_manage_dfl.log",
    "dmesg_info", "dmesg",
    "df_info",
    "agentless_dfl.log",
]

def scan_file(filepath, max_lines=500):
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
print("华为 iBMC GRUB 故障汇总分析")
print(f"分析时间 : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print(f"日志目录 : {os.path.realpath(LOG_DIR)}")
print("=" * 60)

# 1. 目录结构探测
print("\n【日志包结构探测】")
key_dirs = ["OSDump", "AppDump", "BMCDump"]
for d in key_dirs:
    hits = glob.glob(os.path.join(LOG_DIR, "**", d), recursive=True)
    status = f"✓ 发现 {hits[0]}" if hits else "✗ 未找到"
    print(f"  {d:<15} {status}")

# systemcom.tar 特别提示
syscom = glob.glob(os.path.join(LOG_DIR, "**/systemcom.tar"), recursive=True)
if syscom:
    print(f"\n  [重要] 控制台日志包: {syscom[0]}")
    print("         → 已由 step3_grub_os_check.sh 解压分析，请参考其输出")

# 2. 全量扫描
all_findings = []
scanned = []
for fname in SCAN_FILES:
    for fpath in glob.glob(os.path.join(LOG_DIR, "**", fname), recursive=True):
        scanned.append(fpath)
        all_findings.extend(scan_file(fpath))

print(f"\n【扫描文件数】{len(scanned)} 个")
for f in scanned:
    print(f"  - {os.path.relpath(f, LOG_DIR)}")

# 3. 按层次归类
by_layer = {layer: [] for layer in CRITICAL_KEYWORDS}
for item in all_findings:
    by_layer[item["layer"]].append(item)

# 4. 输出分层证据
print("\n【分层故障证据】")
priority_order = ["hardware", "bios", "grub", "filesystem", "kernel"]
active_layers = []
for layer in priority_order:
    items = by_layer[layer]
    if not items:
        print(f"\n  [{layer.upper():12}] ── 无异常")
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
        print(f"    关键字: '{item['keyword']}'")
        print(f"    内容: {item['line']}")
        print()

# 5. 初步诊断方向
print("\n【初步诊断方向】")
if not active_layers:
    print("  ⚪ 未在已知文件中发现明显关键字")
    print("     建议: 重点人工检查 OSDump/systemcom.tar 控制台输出")
else:
    top = active_layers[0]
    icons = {"hardware": "🔴", "bios": "🟠", "grub": "🟡", "filesystem": "🟡", "kernel": "🟡"}
    msgs = {
        "hardware":   "硬件层异常 → 优先排查磁盘/RAID状态，底层故障可能导致所有上层症状",
        "bios":       "固件层异常 → 排查BIOS启动顺序/UEFI配置/Secure Boot",
        "grub":       "GRUB层异常 → 排查引导器配置、分区UUID或GRUB文件完整性",
        "filesystem": "文件系统异常 → 排查分区损坏/满盘/挂载失败",
        "kernel":     "内核层异常 → 排查内核镜像完整性/initramfs生成",
    }
    print(f"  {icons[top]} 主要方向: {msgs[top]}")
    if len(active_layers) > 1:
        print(f"  → 同时存在: {', '.join(active_layers[1:])} 层异常，请结合故障链综合判断")

print("\n" + "=" * 60)
print("请将以上完整输出提供给 AI 进行深度故障链分析。")
print("=" * 60)

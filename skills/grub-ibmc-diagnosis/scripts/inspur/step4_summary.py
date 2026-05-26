#!/usr/bin/env python3
# 浪潮 Inspur iBMC - Step4: 故障汇总分析（纯原生 Python，无第三方依赖）
# 用法: python3 step4_summary.py [日志根目录]

import os
import sys
import re
import json
import glob
import csv
from datetime import datetime

LOG_DIR = sys.argv[1] if len(sys.argv) > 1 else "."

CRITICAL_KEYWORDS = {
    "hardware":    ["degraded", "offline", "rebuild", "failed", "missing",
                    "pd failed", "vd failed", "comm lost", "assert", "drive failure",
                    "critical", "non-recoverable"],
    "bios":        ["no bootable", "boot device not found", "secure boot violation",
                    "uefi variable", "boot order changed", "no boot"],
    "grub":        ["grub rescue", "no such partition", "unknown filesystem",
                    "error: file not found", "grub>", "error: unknown command"],
    "filesystem":  ["read-only file system", "i/o error", "ext4-fs error",
                    "xfs error", "no space left", "superblock", "fsck"],
    "kernel":      ["kernel panic", "not syncing", "call trace", "oops",
                    "kernel not found", "no init found", "initramfs unpacking failed",
                    "dracut-initqueue"],
}

SCAN_FILES = [
    "selelist.csv", "ErrorAnalyReport.json",
    "BMCUart.log", "solHostCaptured.log",
    "dmesg", "rundatainfo.log", "component.log",
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
print("浪潮 iBMC GRUB 故障汇总分析")
print(f"分析时间 : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print(f"日志目录 : {os.path.realpath(LOG_DIR)}")
print("=" * 60)

# 1. 目录结构探测
print("\n【日志包结构探测】")
onekeylog = glob.glob(os.path.join(LOG_DIR, "**/onekeylog"), recursive=True)
if onekeylog:
    base = onekeylog[0]
    print(f"  ✓ onekeylog/ 发现于: {base}")
    for sub in ["log", "sollog", "runningdata", "component"]:
        p = os.path.join(base, sub)
        if os.path.isdir(p):
            fcount = len(os.listdir(p))
            print(f"    ✓ {sub}/ ({fcount} 文件)")
        else:
            print(f"    ✗ {sub}/ [未找到]")
else:
    print("  ✗ 未发现 onekeylog/ 目录，请确认日志包路径")

# 2. 解析 ErrorAnalyReport.json（浪潮核心诊断文件）
print("\n【ErrorAnalyReport 自动诊断结果】")
err_files = glob.glob(os.path.join(LOG_DIR, "**/ErrorAnalyReport.json"), recursive=True)
if err_files:
    try:
        with open(err_files[0]) as f:
            report = json.load(f)
        def extract_errors(obj, depth=0):
            if depth > 5:
                return
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if any(kw in str(k).lower() for kw in ['error', 'fail', 'fault', 'status', 'result', 'code']):
                        val_str = str(v)[:100]
                        if val_str.lower() not in ['ok', 'normal', 'none', 'null', '0', 'true', 'false', '']:
                            print(f"  {k}: {val_str}")
                    extract_errors(v, depth + 1)
            elif isinstance(obj, list):
                for item in obj[:10]:
                    extract_errors(item, depth + 1)
        extract_errors(report)
    except Exception as e:
        print(f"  JSON 解析失败: {e}，尝试文本模式")
        with open(err_files[0], errors='replace') as f:
            for line in f:
                if any(kw in line.lower() for kw in ['error', 'fail', 'fault', 'critical', 'offline']):
                    print(f"  {line.strip()[:100]}")
else:
    print("  ✗ 未找到 ErrorAnalyReport.json")

# 3. 解析 SEL CSV
print("\n【SEL 关键告警事件（最近 20 条）】")
sel_files = glob.glob(os.path.join(LOG_DIR, "**/selelist.csv"), recursive=True)
if sel_files:
    try:
        with open(sel_files[0], errors='replace') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            if header:
                print(f"  字段: {', '.join(header[:6])}")
            count = 0
            for row in reader:
                row_str = ','.join(row).lower()
                if any(kw in row_str for kw in
                       ['critical', 'non-recoverable', 'error', 'assert', 'drive', 'raid', 'disk']):
                    print(f"  {','.join(str(c) for c in row[:6])}")
                    count += 1
                    if count >= 20:
                        break
        if count == 0:
            print("  [INFO] 未发现严重级别 SEL 告警")
    except Exception as e:
        print(f"  解析失败: {e}")
else:
    print("  ✗ 未找到 selelist.csv")

# 4. 全量扫描
all_findings = []
scanned = []
for fname in SCAN_FILES:
    for fpath in glob.glob(os.path.join(LOG_DIR, "**", fname), recursive=True):
        scanned.append(fpath)
        all_findings.extend(scan_file(fpath))

print(f"\n【扫描文件数】{len(scanned)} 个")

# 5. 分层输出
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

# 6. 诊断方向
print("\n【初步诊断方向】")
if not active_layers:
    print("  ⚪ 未发现明显关键字，建议重点检查 solHostCaptured.log 和 BMCUart.log")
else:
    top = active_layers[0]
    msgs = {
        "hardware":   "🔴 硬件层异常 → 优先排查RAID/磁盘，底层故障会导致所有上层启动失败",
        "bios":       "🟠 固件层异常 → 检查BIOS启动顺序/UEFI配置",
        "grub":       "🟡 GRUB层异常 → 检查引导配置/分区UUID，结合 solHostCaptured.log",
        "filesystem": "🟡 文件系统异常 → 检查分区完整性/满盘",
        "kernel":     "🟡 内核层异常 → 检查内核镜像/initramfs，结合 dmesg",
    }
    print(f"  {msgs[top]}")
    if len(active_layers) > 1:
        print(f"  → 次要异常层: {', '.join(active_layers[1:])}")

print("\n" + "=" * 60)
print("请将以上完整输出提供给 AI 进行深度故障链分析。")
print("=" * 60)

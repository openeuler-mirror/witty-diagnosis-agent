#!/usr/bin/env python3
import os
import sys
import re
import argparse
import json
from datetime import datetime
from collections import defaultdict

TIME_PATTERNS = [
    (r'(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})', "MMM D HH:MM:SS (Syslog)"),
    (r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})', "YYYY-MM-DD HH:MM:SS (ISO)"),
    (r'(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})', "MM/DD/YYYY HH:MM:SS (SEL)"),
]

# 内存相关的InfoCollect文件类型
MEMORY_INFO_FILES = {
    "meminfo": ["meminfo.txt", "proc/meminfo", "memory_info.txt"],
    "slabinfo": ["slabinfo.txt", "proc/slabinfo"],
    "dmesg": ["dmesg.txt", "dmesg.log"],
    "vmstat": ["vmstat.txt", "proc/vmstat"],
    "numa": ["numa.txt", "numastat.txt"],
    "smaps": ["smaps.txt", "proc/self/smaps"],
    "buddyinfo": ["buddyinfo.txt", "proc/buddyinfo"],
}

# 内存错误关键词 (InfoCollect 层面)
MEMORY_ERROR_KEYWORDS = [
    ("ECC error", "内存ECC错误"),
    ("Uncorrectable memory error", "不可纠正内存错误"),
    ("Correctable memory error", "可纠正内存错误"),
    ("Out of memory", "系统内存不足(OOM)"),
    ("OOM.*killer", "OOM Killer 触发"),
    ("Killed process", "进程被强制终止"),
    ("page allocation failure", "内核页分配失败"),
    ("memory corruption", "内存数据损坏"),
    ("stack smashing", "栈溢出保护触发"),
    ("segfault", "分段错误(Segfault)"),
    ("page fault", "缺页异常"),
]

def find_infocollect_files(root_dir):
    """查找InfoCollect相关的内存日志文件"""
    infocollect_files = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            if any(pattern in file_lower for pattern in ['infocollect', 'meminfo', 'slab', 'dmesg', 'vmstat', 'numa']):
                infocollect_files.append(os.path.join(root, file))
            elif 'system' in root.lower() and file_lower.endswith('.txt'):
                infocollect_files.append(os.path.join(root, file))
    return infocollect_files

def classify_memory_file(file_path):
    """根据文件名或内容分类内存日志文件"""
    filename = os.path.basename(file_path).lower()
    for file_type, patterns in MEMORY_INFO_FILES.items():
        for pattern in patterns:
            if pattern in filename: return file_type
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read(1024).lower()
            if 'memtotal' in content: return "meminfo"
            if 'active_objs' in content: return "slabinfo"
            if 'nr_free_pages' in content: return "vmstat"
    except: pass
    return "other"

def analyze_meminfo(file_path):
    """分析 meminfo 文件提取关键指标"""
    results = []
    mem_info = {"MemTotal": 0, "MemFree": 0, "MemAvailable": 0, "Buffers": 0, "Cached": 0, "Slab": 0, "SwapTotal": 0, "SwapFree": 0}
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                match = re.search(r'(\w+):\s+(\d+)\s+kB', line)
                if match:
                    key, val = match.groups()
                    if key in mem_info: mem_info[key] = int(val)
        
        # 计算使用率
        if mem_info["MemTotal"] > 0:
            usage = 100 * (1 - (mem_info["MemAvailable"] / mem_info["MemTotal"]))
            mem_info["UsagePercent"] = f"{usage:.1f}%"
            
        results.append({
            "file": os.path.basename(file_path),
            "type": "MEMINFO",
            "info": mem_info
        })
    except: pass
    return results

def analyze_dmesg(file_path, keywords, date_filter=None):
    """分析 dmesg 文件查找内存错误，支持日期过滤"""
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                if date_filter and date_filter.lower() not in line.lower():
                    continue
                line_lower = line.lower()
                for pattern, description in keywords:
                    if re.search(pattern, line_lower, re.IGNORECASE):
                        ts = None
                        for tp, _ in TIME_PATTERNS:
                            m = re.search(tp, line)
                            if m: ts = m.group(1); break
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "DMESG_ERROR",
                            "line_num": line_num,
                            "timestamp": ts,
                            "description": description,
                            "line": line.strip()
                        })
                        break
    except: pass
    return results

def analyze_infocollect_logs(log_dir, keywords=None, date_filter=None):
    print(f"🔍 开始InfoCollect日志分析: {log_dir}")
    print("=" * 60)
    files = find_infocollect_files(log_dir)
    if not files:
        print("❌ 未找到InfoCollect相关日志文件")
        return []
    
    file_categories = defaultdict(list)
    for fp in files:
        file_categories[classify_memory_file(fp)].append(fp)
    
    # 构建搜索关键词
    search_keywords = []
    if keywords:
        for k in keywords:
            search_keywords.append((re.escape(k), f"自定义搜索: {k}"))
    else:
        search_keywords = MEMORY_ERROR_KEYWORDS

    print("📁 文件分类统计:")
    for cat, fls in sorted(file_categories.items()):
        print(f"  - {cat}: {len(fls)} 个文件")
    print("-" * 60)
    
    all_results = []
    if file_categories["meminfo"]:
        print("📊 分析内存配置 (meminfo):")
        for fp in file_categories["meminfo"][:2]:
            res = analyze_meminfo(fp)
            all_results.extend(res)
            if res:
                info = res[0]["info"]
                print(f"    总物理内存: {info['MemTotal']/1024/1024:.2f} GB")
                print(f"    可用内存:   {info['MemAvailable']/1024/1024:.2f} GB ({info['UsagePercent']} 已用)")
                print(f"    Slab 占用:  {info['Slab']/1024:.2f} MB")
                
    if file_categories["dmesg"]:
        print("\n📊 分析内核日志 (dmesg):")
        res = []
        for fp in file_categories["dmesg"][:3]:
            res.extend(analyze_dmesg(fp, search_keywords, date_filter))
        all_results.extend(res)
        if res:
            print(f"    发现 {len(res)} 条严重内存相关报错")
            for r in res[:10]:
                print(f"    - [{r.get('timestamp','?')}] {r['description']}")
        else:
            print("    ✅ 未发现内核层内存报错")
            
    save_results(all_results, log_dir)
    print("=" * 60)
    print("✅ InfoCollect日志分析完成")
    return all_results

def save_results(results, log_dir):
    """整合分析结果到 JSON 文件"""
    output_file = "/tmp/memory_analysis_results.json"
    existing_data = {}
    if os.path.exists(output_file):
        try:
            with open(output_file, 'r', encoding='utf-8') as f: existing_data = json.load(f)
        except: pass
    
    mem_info = existing_data.get('memory_info', {})
    for r in results:
        if r["type"] == "MEMINFO": mem_info = r["info"]
        
    all_results_list = existing_data.get('all_results', [])
    all_results_list.extend(results)
    
    results_summary = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "memory_info": mem_info,
        "all_results": all_results_list
    }
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results_summary, f, ensure_ascii=False, indent=2)
    except: pass

def main():
    parser = argparse.ArgumentParser(description='内存故障诊断 - InfoCollect分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('-k', '--keywords', nargs='+', help='自定义关键字过滤')
    parser.add_argument('-d', '--date', help='日期过滤 (如 "2025-07-21")')
    args = parser.parse_args()
    if not os.path.exists(args.log_dir): sys.exit(1)
    analyze_infocollect_logs(args.log_dir, keywords=args.keywords, date_filter=args.date)

if __name__ == '__main__':
    main()
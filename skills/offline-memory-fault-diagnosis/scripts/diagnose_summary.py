#!/usr/bin/env python3
import os
import sys
import re
import argparse
from datetime import datetime
from collections import defaultdict

TIME_PATTERNS = [
    (r'(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})', "MMM D HH:MM:SS (Syslog)"),
    (r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})', "YYYY-MM-DD HH:MM:SS (ISO)"),
    (r'(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})', "MM/DD/YYYY HH:MM:SS (SEL)"),
]

# 内存故障相关关键词
MEMORY_ERROR_KEYWORDS = [
    # 硬件错误
    "Memory", "DIMM", "ECC", "CE", "UCE", "Correctable", "Uncorrectable", "SPD", "Presence",
    # 内存资源与分配
    "Out of memory", "OOM", "killer", "Killed process", "allocation failure", "page allocation",
    # 内存损坏
    "corruption", "segfault", "page fault", "general protection fault", "stack smashing",
    # 内存泄漏相关
    "leak", "SUnreclaim", "slab", "Cache", "growing",
    # 性能与配置
    "swap", "swapping", "NUMA", "imbalance", "latency", "bandwidth", "frequency",
    # 通用错误
    "error", "fail", "failed", "failure", "critical", "warning", "panic", "Oops"
]

def find_files(root_dir, filename_patterns):
    """查找匹配模式的文件"""
    matches = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            for pattern in filename_patterns:
                if re.match(pattern, file, re.IGNORECASE):
                    matches.append(os.path.join(root, file))
                    break
    return matches

def get_time_info(file_path):
    """获取文件的时间范围信息"""
    min_dt = None
    max_dt = None
    detected_fmt = "Unknown"
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            if not lines: 
                return None, None, "Empty"
            
            # 从文件开头查找最早时间
            for line in lines[:500]:  # 检查前500行
                for pattern, fmt_name in TIME_PATTERNS:
                    match = re.search(pattern, line)
                    if match:
                        ts_str = match.group(1)
                        detected_fmt = fmt_name
                        fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
                        for f_str in fmts:
                            try:
                                if f_str == "%b %d %H:%M:%S":
                                    # 为不带年份的格式添加当前年份
                                    dt = datetime.strptime(f"{datetime.now().year} {ts_str}", f"%Y {f_str}")
                                else:
                                    dt = datetime.strptime(ts_str, f_str)
                                
                                if min_dt is None or dt < min_dt: 
                                    min_dt = dt
                                break
                            except: 
                                continue
                        if min_dt: 
                            break
            
            # 从文件末尾查找最晚时间
            for line in reversed(lines[-500:]):  # 检查后500行
                for pattern, fmt_name in TIME_PATTERNS:
                    match = re.search(pattern, line)
                    if match:
                        ts_str = match.group(1)
                        fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
                        for f_str in fmts:
                            try:
                                if f_str == "%b %d %H:%M:%S":
                                    # 为不带年份的格式添加当前年份
                                    dt = datetime.strptime(f"{datetime.now().year} {ts_str}", f"%Y {f_str}")
                                else:
                                    dt = datetime.strptime(ts_str, f_str)
                                
                                if max_dt is None or dt > max_dt: 
                                    max_dt = dt
                                break
                            except: 
                                continue
                        if max_dt: 
                            break
            
            return min_dt, max_dt, detected_fmt
    except Exception as e:
        return None, None, f"Error: {str(e)}"

def count_keywords(file_path, keywords, date_filter=None, start_time=None, end_time=None):
    """统计关键词在文件中出现的次数，支持时间过滤"""
    counts = defaultdict(int)
    st, et = None, None
    if start_time:
        try: st = datetime.strptime(start_time, "%Y-%m-%d %H:%M:%S")
        except: pass
    if end_time:
        try: et = datetime.strptime(end_time, "%Y-%m-%d %H:%M:%S")
        except: pass
        
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if date_filter and date_filter.lower() not in line.lower(): continue
                if st or et:
                    timestamp = None
                    for pattern, _ in TIME_PATTERNS:
                        match = re.search(pattern, line)
                        if match:
                            ts_str = match.group(1)
                            for fmt in ["%Y-%m-%d %H:%M:%S", "%b %d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"]:
                                try:
                                    ts = datetime.strptime(ts_str, fmt)
                                    if fmt == "%b %d %H:%M:%S": ts = ts.replace(year=datetime.now().year)
                                    timestamp = ts
                                    break
                                except: continue
                            break
                    if timestamp:
                        if st and timestamp < st: continue
                        if et and timestamp > et: continue
                lower_line = line.lower()
                for keyword in keywords:
                    # 对于短关键词使用单词边界匹配，防止 SUCCESS 匹配到 CE
                    if len(keyword) <= 3:
                        if re.search(r'\b' + re.escape(keyword) + r'\b', line, re.IGNORECASE):
                            counts[keyword] += 1
                    else:
                        if keyword.lower() in lower_line:
                            counts[keyword] += 1
        return counts
    except: return defaultdict(int)

def classify_file_type(file_path):
    """根据文件路径和内容判断文件类型"""
    filename = os.path.basename(file_path).lower()
    if any(p in filename for p in ['ibmc', 'sel', 'bmc', 'ipmi', 'event']): return "iBMC"
    if any(p in filename for p in ['infocollect', 'meminfo', 'slabinfo', 'dmesg', 'vmstat', 'numa']): return "InfoCollect"
    if any(p in filename for p in ['messages', 'syslog', 'journal']): return "Messages"
    if any(p in filename for p in ['mem', 'ecc', 'dimm', 'oom']): return "Memory_Specific"
    dir_path = os.path.dirname(file_path).lower()
    if 'ibmc' in dir_path: return "iBMC"
    elif 'infocollect' in dir_path: return "InfoCollect"
    elif 'messages' in dir_path: return "Messages"
    return "Other"

def analyze_log_directory(log_dir, keywords=None, date_filter=None, start_time=None, end_time=None):
    """分析日志目录"""
    if keywords is None: keywords = MEMORY_ERROR_KEYWORDS
    print(f"📊 分析日志目录: {log_dir}")
    print("=" * 60)
    text_files = []
    for root, dirs, files in os.walk(log_dir):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                with open(file_path, 'rb') as f:
                    chunk = f.read(1024)
                    if chunk and chunk.count(b'\x00') / len(chunk) < 0.1:
                        text_files.append(file_path)
            except: continue
    
    print(f"找到 {len(text_files)} 个文本文件")
    file_types = defaultdict(list)
    for file_path in text_files:
        file_types[classify_file_type(file_path)].append(file_path)
    
    print("📁 文件类型统计:")
    for file_type, files in sorted(file_types.items()):
        print(f"  {file_type}: {len(files)} 个文件")
    print("-" * 60)
    
    print("⏰ 时间范围分析 (抽样前10个):")
    time_info_by_type = defaultdict(list)
    keyword_totals = defaultdict(int)
    keyword_by_file = defaultdict(lambda: defaultdict(int))
    
    for file_type, files in file_types.items():
        for file_path in files[:10]:
            min_dt, max_dt, fmt = get_time_info(file_path)
            if min_dt and max_dt:
                time_info_by_type[file_type].append((min_dt, max_dt))
                fname = os.path.basename(file_path)
                print(f"  {fname[:30]:<30} {min_dt.strftime('%Y-%m-%d %H:%M:%S')} 到 {max_dt.strftime('%Y-%m-%d %H:%M:%S')}")
    
    all_times = [t for times in time_info_by_type.values() for t in times]
    if all_times:
        overall_min, overall_max = min(t[0] for t in all_times), max(t[1] for t in all_times)
        print(f"📅 总体时间范围: {overall_min.strftime('%Y-%m-%d %H:%M:%S')} 到 {overall_max.strftime('%Y-%m-%d %H:%M:%S')}")
    else:
        print("⚠️  无法确定时间范围")
    print("-" * 60)
    
    for file_type, files in file_types.items():
        type_keyword_totals = defaultdict(int)
        for file_path in files[:5]:
            counts = count_keywords(file_path, keywords, date_filter, start_time, end_time)
            for keyword, count in counts.items():
                if count > 0:
                    keyword_totals[keyword] += count
                    type_keyword_totals[keyword] += count
                    keyword_by_file[os.path.basename(file_path)][keyword] = count
        if type_keyword_totals:
            print(f"\n  {file_type} 文件类型 (前10关键词):")
            for keyword, count in sorted(type_keyword_totals.items(), key=lambda x: x[1], reverse=True)[:10]:
                print(f"    {keyword:<20} {count:>4} 次")
    
    print("-" * 60)
    if keyword_totals:
        print("📈 总体关键词统计 (前20名):")
        for keyword, count in sorted(keyword_totals.items(), key=lambda x: x[1], reverse=True)[:20]:
            print(f"  {keyword:<20} {count:>4} 次")
    else:
        print("ℹ️  未找到内存故障相关关键词")
    
    print("-" * 60)
    error_files = []
    for filename, keyword_counts in keyword_by_file.items():
        total_errors = sum(keyword_counts.values())
        if total_errors > 0: error_files.append((filename, total_errors, keyword_counts))
    
    if error_files:
        print("🚨 包含错误关键词的文件 (前10名):")
        for filename, total_errors, keyword_counts in sorted(error_files, key=lambda x: x[1], reverse=True)[:10]:
            top_k = sorted(keyword_counts.items(), key=lambda x: x[1], reverse=True)[:3]
            k_str = ", ".join([f"{k}({v})" for k, v in top_k])
            print(f"  {filename[:30]:<30} {total_errors:>4} 个错误 - 主要关键词: {k_str}")
    
    print("=" * 60)
    print("📋 Step 0 完成: 故障日志采集完毕")
    print("下一步: 执行场景分类 (Step 1)")
    print("参考指南: references/MEMORY_fault_scenarios.md")

def main():
    parser = argparse.ArgumentParser(description='内存故障诊断 - 日志概览分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('-o', '--overview', action='store_true', help='概览模式（Step 0 专用）')
    parser.add_argument('-k', '--keywords', nargs='+', help='自定义关键词过滤')
    parser.add_argument('-d', '--date', help='日期过滤（如 "Mar 16"）')
    parser.add_argument('-s', '--start-time', help='开始时间（格式: YYYY-MM-DD HH:MM:SS）')
    parser.add_argument('-e', '--end-time', help='结束时间（格式: YYYY-MM-DD HH:MM:SS）')
    args = parser.parse_args()
    if not os.path.isdir(args.log_dir):
        print(f"❌ 错误: 目录 '{args.log_dir}' 不存在")
        sys.exit(1)
    analyze_log_directory(args.log_dir, keywords=args.keywords, date_filter=args.date, start_time=args.start_time, end_time=args.end_time)

if __name__ == '__main__':
    main()
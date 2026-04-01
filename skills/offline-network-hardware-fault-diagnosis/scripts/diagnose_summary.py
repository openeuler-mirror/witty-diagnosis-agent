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

# 网络硬件故障相关关键词
NETWORK_ERROR_KEYWORDS = [
    # 硬件错误
    "NIC", "PCIe", "AER Error", "Hardware failure", "Bus Error", "Link training failed", "Fatal Error",
    # 链路相关
    "link down", "lost carrier", "link up", "negotiation failed", "autoneg", "flap", "CRC error",
    # 驱动相关
    "driver", "firmware", "failed to load firmware", "reset adapter", "TX unit hang", "ixgbe", "i40e", "mlx5",
    # 性能相关
    "dropped", "overruns", "fifo errors", "crc errors", "collisions", "buffer overflow", "packet loss",
    # 中断相关
    "IRQ", "MSI", "MSI-X", "interrupt storm", "affinity",
    # 配置相关
    "IP conflict", "duplicate address", "VLAN", "MTU mismatch",
    # 温度相关
    "temperature", "thermal", "overheat",
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
            for line in lines[:500]:
                for pattern, fmt_name in TIME_PATTERNS:
                    match = re.search(pattern, line)
                    if match:
                        ts_str = match.group(1)
                        detected_fmt = fmt_name
                        fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
                        for f_str in fmts:
                            try:
                                dt = datetime.strptime(ts_str, f_str)
                                if f_str == "%b %d %H:%M:%S": 
                                    dt = dt.replace(year=datetime.now().year)
                                if min_dt is None or dt < min_dt: 
                                    min_dt = dt
                                break
                            except: continue
                        if min_dt: break
            
            # 从文件末尾查找最晚时间
            for line in reversed(lines[-500:]):
                for pattern, fmt_name in TIME_PATTERNS:
                    match = re.search(pattern, line)
                    if match:
                        ts_str = match.group(1)
                        fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
                        for f_str in fmts:
                            try:
                                dt = datetime.strptime(ts_str, f_str)
                                if f_str == "%b %d %H:%M:%S": 
                                    dt = dt.replace(year=datetime.now().year)
                                if max_dt is None or dt > max_dt: 
                                    max_dt = dt
                                break
                            except: continue
                        if max_dt: break
            
            return min_dt, max_dt, detected_fmt
    except:
        return None, None, "Error"

def count_keywords(file_path, keywords, date_filter=None, start_time=None, end_time=None):
    """统计关键词在文件中出现的次数"""
    counts = defaultdict(int)
    st = None
    et = None
    if start_time:
        try: st = datetime.strptime(start_time, "%Y-%m-%d %H:%M:%S")
        except: pass
    if end_time:
        try: et = datetime.strptime(end_time, "%Y-%m-%d %H:%M:%S")
        except: pass
        
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if date_filter and date_filter.lower() not in line.lower():
                    continue
                
                # 时间过滤（简化版，逻辑同CPU版）
                if st or et:
                    timestamp = None
                    for pattern, _ in TIME_PATTERNS:
                        match = re.search(pattern, line)
                        if match:
                            try:
                                ts_str = match.group(1)
                                for fmt in ["%Y-%m-%d %H:%M:%S", "%b %d %H:%M:%S"]:
                                    try:
                                        ts = datetime.strptime(ts_str, fmt)
                                        if fmt == "%b %d %H:%M:%S": ts = ts.replace(year=datetime.now().year)
                                        timestamp = ts
                                        break
                                    except: continue
                            except: pass
                            break
                    if timestamp:
                        if st and timestamp < st: continue
                        if et and timestamp > et: continue

                lower_line = line.lower()
                for keyword in keywords:
                    if keyword.lower() in lower_line:
                        counts[keyword] += 1
        return counts
    except:
        return defaultdict(int)

def classify_file_type(file_path):
    filename = os.path.basename(file_path).lower()
    if any(p in filename for p in ['ibmc', 'sel', 'bmc']): return "iBMC"
    if any(p in filename for p in ['infocollect', 'ethtool', 'ifconfig', 'ip_addr', 'route', 'sar_net']): return "InfoCollect"
    if any(p in filename for p in ['messages', 'syslog', 'journal']): return "Messages"
    return "Other"

def analyze_log_directory(log_dir, keywords=None, date_filter=None, start_time=None, end_time=None):
    if keywords is None: keywords = NETWORK_ERROR_KEYWORDS
    
    print(f"📊 分析日志目录: {log_dir}")
    print("=" * 60)
    
    text_files = []
    for root, dirs, files in os.walk(log_dir):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                with open(file_path, 'rb') as f:
                    chunk = f.read(1024)
                    if chunk.count(b'\x00') / (len(chunk) or 1) < 0.1:
                        text_files.append(file_path)
            except: continue
    
    print(f"找到 {len(text_files)} 个文本文件")
    
    file_types = defaultdict(list)
    for file_path in text_files:
        file_types[classify_file_type(file_path)].append(file_path)
    
    print("-" * 60)
    print("📁 文件类型统计:")
    for f_type, files in sorted(file_types.items()):
        print(f"  {f_type}: {len(files)} 个文件")
    
    print("-" * 60)
    print("📅 时间范围分析:")
    all_times = []
    for f_type, files in file_types.items():
        for f_path in files[:5]:
            min_dt, max_dt, _ = get_time_info(f_path)
            if min_dt and max_dt:
                all_times.append((min_dt, max_dt))
                print(f"  {os.path.basename(f_path)[:30]:<30} {min_dt.strftime('%Y-%m-%d %H:%M:%S')} 到 {max_dt.strftime('%Y-%m-%d %H:%M:%S')}")
    
    if all_times:
        print(f"\n📅 总体时间范围: {min(t[0] for t in all_times).strftime('%Y-%m-%d %H:%M:%S')} 到 {max(t[1] for t in all_times).strftime('%Y-%m-%d %H:%M:%S')}")
    
    print("-" * 60)
    print("📈 错误关键词统计 (前10名):")
    keyword_totals = defaultdict(int)
    for f_type, files in file_types.items():
        for f_path in files[:5]:
            counts = count_keywords(f_path, keywords, date_filter, start_time, end_time)
            for kw, count in counts.items():
                keyword_totals[kw] += count
    
    sorted_totals = sorted(keyword_totals.items(), key=lambda x: x[1], reverse=True)[:10]
    for kw, count in sorted_totals:
        print(f"  {kw:<20} {count:>4} 次")
    
    print("=" * 60)
    print("📋 Step 0 完成: 故障日志采集完毕")
    print("下一步: 执行场景分类 (Step 1)")

def main():
    parser = argparse.ArgumentParser(description='网络故障诊断 - 日志概览分析')
    parser.add_argument('log_dir')
    parser.add_argument('-o', '--overview', action='store_true')
    parser.add_argument('-k', '--keywords', nargs='+')
    parser.add_argument('-d', '--date')
    parser.add_argument('-s', '--start-time')
    parser.add_argument('-e', '--end-time')
    args = parser.parse_args()
    if not os.path.isdir(args.log_dir):
        sys.exit(1)
    analyze_log_directory(args.log_dir, args.keywords, args.date, args.start_time, args.end_time)

if __name__ == '__main__':
    main()
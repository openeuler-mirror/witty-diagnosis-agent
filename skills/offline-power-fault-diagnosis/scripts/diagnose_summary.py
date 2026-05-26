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

# 电源故障相关关键词
POWER_ERROR_KEYWORDS = [
    # 掉电相关
    "power loss", "power lost", "AC lost", "AC loss", "input lost", "unexpected shutdown", "unexpected reboot",
    # 电源模块相关
    "PSU", "Power Supply", "PSU failure", "PSU fault", "PSU absent", "PSU error",
    # 电压相关
    "voltage", "under voltage", "over voltage", "voltage out of range", "voltage sensor", "Vout", "Vin",
    # 冗余相关
    "redundancy", "redundant", "redundancy lost", "redundancy degraded",
    # 过载相关
    "overload", "current overload", "wattage", "power consumption", "high power",
    # 温度与冷却相关
    "temperature high", "fan failure", "over temperature", "thermal", "cooling",
    # 通用错误
    "error", "fail", "failed", "failure", "critical", "warning", "alarm", "alert"
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
                                dt = datetime.strptime(ts_str, f_str)
                                if f_str == "%b %d %H:%M:%S": 
                                    dt = dt.replace(year=datetime.now().year)
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
                                dt = datetime.strptime(ts_str, f_str)
                                if f_str == "%b %d %H:%M:%S": 
                                    dt = dt.replace(year=datetime.now().year)
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
    
    # 转换时间范围
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
                # 检查日期过滤
                if date_filter and date_filter.lower() not in line.lower():
                    continue
                
                # 检查时间范围点
                if st or et:
                    timestamp = None
                    for pattern, _ in TIME_PATTERNS:
                        match = re.search(pattern if isinstance(pattern, str) else pattern[0], line)
                        if match:
                            try:
                                ts_str = match.group(1)
                                for fmt in ["%Y-%m-%d %H:%M:%S", "%b %d %H:%M:%S", "%m/%d/%Y %H:%M:%S"]:
                                    try:
                                        ts = datetime.strptime(ts_str, fmt)
                                        if fmt == "%b %d %H:%M:%S":
                                            ts = ts.replace(year=datetime.now().year)
                                        timestamp = ts
                                        break
                                    except: continue
                            except: pass
                            break
                    
                    if timestamp:
                        if st and timestamp < st: continue
                        if et and timestamp > et: continue

                # 统计关键词
                lower_line = line.lower()
                for keyword in keywords:
                    if keyword.lower() in lower_line:
                        counts[keyword] += 1
                        
        return counts
    except:
        return defaultdict(int)

def classify_file_type(file_path):
    """根据文件路径和内容判断文件类型"""
    filename = os.path.basename(file_path).lower()
    
    # iBMC相关文件
    if any(pattern in filename for pattern in ['ibmc', 'sel', 'bmc', 'ipmi', 'psu', 'sensor']):
        return "iBMC"
    
    # InfoCollect相关文件
    if any(pattern in filename for pattern in ['infocollect', 'power', 'monitor', 'temp', 'thermal', 'sensor_info', 'dmesg']):
        return "InfoCollect"
    
    # 系统消息文件
    if any(pattern in filename for pattern in ['messages', 'syslog', 'journal']):
        return "Messages"
    
    # 根据目录路径判断
    dir_path = os.path.dirname(file_path).lower()
    if 'ibmc' in dir_path:
        return "iBMC"
    elif 'infocollect' in dir_path:
        return "InfoCollect"
    elif 'messages' in dir_path:
        return "Messages"
    
    return "Other"

def analyze_log_directory(log_dir, keywords=None, date_filter=None, start_time=None, end_time=None):
    """分析日志目录"""
    if keywords is None:
        keywords = POWER_ERROR_KEYWORDS
    
    print(f"📊 分析日志目录: {log_dir}")
    print("=" * 60)
    
    # 查找所有文本文件
    text_files = []
    for root, dirs, files in os.walk(log_dir):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                # 简单检查是否为文本文件
                with open(file_path, 'rb') as f:
                    chunk = f.read(1024)
                    if chunk.count(b'\x00') / (len(chunk) or 1) < 0.1:
                        text_files.append(file_path)
            except:
                continue
    
    print(f"找到 {len(text_files)} 个文本文件")
    print("-" * 60)
    
    # 按文件类型分组
    file_types = defaultdict(list)
    for file_path in text_files:
        file_type = classify_file_type(file_path)
        file_types[file_type].append(file_path)
    
    # 输出文件类型统计
    print("📁 文件类型统计:")
    for file_type, files in sorted(file_types.items()):
        print(f"  {file_type}: {len(files)} 个文件")
    print("-" * 60)
    
    # 分析时间范围
    print("⏰ 时间范围分析:")
    time_info_by_type = defaultdict(list)
    keyword_totals = defaultdict(int)
    keyword_by_file = defaultdict(lambda: defaultdict(int))
    
    for file_type, files in file_types.items():
        for file_path in files[:10]:
            min_dt, max_dt, fmt = get_time_info(file_path)
            if min_dt and max_dt:
                time_info_by_type[file_type].append((min_dt, max_dt))
                filename = os.path.basename(file_path)
                if len(filename) > 30:
                    filename = filename[:27] + "..."
                print(f"  {filename:<30} {min_dt.strftime('%Y-%m-%d %H:%M:%S')} 到 {max_dt.strftime('%Y-%m-%d %H:%M:%S')}")
    
    print("-" * 60)
    
    # 输出总体时间范围
    all_times = []
    for times in time_info_by_type.values():
        all_times.extend(times)
    
    if all_times:
        overall_min = min(t[0] for t in all_times)
        overall_max = max(t[1] for t in all_times)
        print(f"📅 总体时间范围: {overall_min.strftime('%Y-%m-%d %H:%M:%S')} 到 {overall_max.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"   时间跨度: {(overall_max - overall_min).days} 天")
    else:
        print("⚠️  无法确定时间范围")
    
    print("-" * 60)
    
    # 输出关键词统计
    if date_filter or start_time or end_time:
        print(f"应用过滤条件: 日期={date_filter or '无'}，范围={start_time or '开始'} 至 {end_time or '结束'}")
        print("-" * 60)
        
    for file_type, files in file_types.items():
        type_keyword_totals = defaultdict(int)
        for file_path in files[:10]:
            counts = count_keywords(file_path, keywords, date_filter, start_time, end_time)
            filename = os.path.basename(file_path)
            
            for keyword, count in counts.items():
                if count > 0:
                    keyword_totals[keyword] += count
                    type_keyword_totals[keyword] += count
                    keyword_by_file[filename][keyword] = count
        
        if type_keyword_totals:
            print(f"\n  {file_type} 文件类型:")
            sorted_keywords = sorted(type_keyword_totals.items(), key=lambda x: x[1], reverse=True)[:10]
            for keyword, count in sorted_keywords:
                print(f"    {keyword:<20} {count:>4} 次")
    
    print("-" * 60)
    
    if keyword_totals:
        print("📈 总体关键词统计 (前20名):")
        sorted_totals = sorted(keyword_totals.items(), key=lambda x: x[1], reverse=True)[:20]
        for keyword, count in sorted_totals:
            print(f"  {keyword:<20} {count:>4} 次")
    else:
        print("ℹ️  未找到电源故障相关关键词")
    
    print("-" * 60)
    
    error_files = []
    for filename, keyword_counts in keyword_by_file.items():
        total_errors = sum(keyword_counts.values())
        if total_errors > 0:
            error_files.append((filename, total_errors, keyword_counts))
    
    if error_files:
        print("🚨 包含错误关键词的文件:")
        error_files.sort(key=lambda x: x[1], reverse=True)
        for filename, total_errors, keyword_counts in error_files[:10]:
            top_keywords = sorted(keyword_counts.items(), key=lambda x: x[1], reverse=True)[:3]
            keyword_str = ", ".join([f"{k}({v})" for k, v in top_keywords])
            print(f"  {filename:<30} {total_errors:>4} 个错误 - 主要关键词: {keyword_str}")
    else:
        print("✅ 未发现包含错误关键词的文件")
    
    print("=" * 60)
    print("📋 Step 0 完成: 故障日志采集完毕")
    print("下一步: 执行场景分类 (Step 1)")
    print("参考指南: references/Power_fault_scenarios.md")

def main():
    parser = argparse.ArgumentParser(description='电源故障诊断 - 日志概览分析')
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
    
    analyze_log_directory(
        args.log_dir,
        keywords=args.keywords,
        date_filter=args.date,
        start_time=args.start_time,
        end_time=args.end_time
    )

if __name__ == '__main__':
    main()
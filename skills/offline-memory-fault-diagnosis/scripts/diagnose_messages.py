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

# 内存相关的系统消息关键词
MEMORY_MESSAGE_KEYWORDS = [
    # 硬件错误
    ("Memory.*error", "内存错误"),
    ("ECC.*error", "ECC错误"),
    ("Correctable.*Error", "可纠正错误(CE)"),
    ("Uncorrectable.*Error", "不可纠正错误(UCE)"),
    ("DIMM.*fail", "DIMM故障"),
    
    # 资源状态
    ("Out of memory", "系统内存不足(OOM)"),
    ("OOM.*killer", "OOM Killer 触发"),
    ("Killed process", "进程被强制终止"),
    ("page allocation failure", "内核页分配失败"),
    
    # 内存损坏
    ("memory corruption", "内存数据损坏"),
    ("segfault", "分段错误(Segfault)"),
    ("page fault", "缺页异常"),
    ("stack smashing", "栈溢出保护触发"),
    
    # 交换空间 (Swap)
    ("swap.*full", "交换空间耗尽"),
    ("swapping.*in", "内存换入"),
    ("swapping.*out", "内存换出"),
    
    # NUMA
    ("NUMA.*imbalance", "NUMA 节点不平衡"),
    ("NUMA.*allocation", "NUMA 分配异常"),
]

def find_message_files(root_dir):
    """查找系统消息文件"""
    message_files = []
    # 如果路径本身包含 messages，则放宽文件过滤条件
    dir_is_messages = "messages" in root_dir.lower()
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            if any(p in file_lower for p in ['messages', 'syslog', 'journal', 'kern.log']):
                message_files.append(os.path.join(root, file))
            elif (dir_is_messages or "messages" in root.lower()) and file_lower.endswith('.log'):
                message_files.append(os.path.join(root, file))
    return message_files

def parse_timestamp(line):
    """解析时间戳"""
    for pattern, _ in TIME_PATTERNS:
        match = re.search(pattern, line)
        if match:
            ts_str = match.group(1)
            for fmt in ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]:
                try:
                    dt = datetime.strptime(ts_str, fmt)
                    if fmt == "%b %d %H:%M:%S": dt = dt.replace(year=datetime.now().year)
                    return dt, ts_str
                except: continue
    return None, None

def analyze_messages_file(file_path, keywords, date_filter=None):
    """分析系统消息文件中的内存记录"""
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                if date_filter and date_filter.lower() not in line.lower():
                    continue
                line_lower = line.lower()
                for pattern, description in keywords:
                    if re.search(pattern, line_lower, re.IGNORECASE):
                        dt, ts_str = parse_timestamp(line)
                        severity = "INFO"
                        if any(k in line_lower for k in ['error', 'fail', 'fatal', 'panic', 'killed']): severity = "ERROR"
                        elif any(k in line_lower for k in ['warning', 'warn']): severity = "WARNING"
                        
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "MESSAGE",
                            "line_num": line_num,
                            "timestamp": ts_str,
                            "timestamp_dt": dt,
                            "severity": severity,
                            "description": description,
                            "line": line.strip()
                        })
                        break
    except: pass
    return results

def analyze_messages_logs(log_dir, keywords=None, date_filter=None):
    print(f"🔍 开始系统消息日志分析: {log_dir}")
    print("=" * 60)
    files = find_message_files(log_dir)
    if not files:
        print("❌ 未找到系统消息日志文件")
        return []
    
    # 构建搜索关键词
    search_keywords = []
    if keywords:
        for k in keywords:
            search_keywords.append((re.escape(k), f"自定义搜索: {k}"))
    else:
        search_keywords = MEMORY_MESSAGE_KEYWORDS

    all_results = []
    for fp in files[:10]: # 增加抽样数量
        print(f"📊 分析文件: {os.path.basename(fp)}")
        res = analyze_messages_file(fp, search_keywords, date_filter)
        all_results.extend(res)
        if res:
            print(f"  找到 {len(res)} 条内存相关消息")
            for r in [r for r in res if r['severity'] != 'INFO'][:10]:
                print(f"  [{r.get('timestamp','?')}] {r['description']}: {r['line'][:100]}...")
        else:
            print(f"  ✅ 未发现内存相关报错")
            
    save_results(all_results, log_dir)
    print("=" * 60)
    print("✅ 系统消息日志分析完成")
    return all_results

def save_results(results, log_dir):
    """保存并合并结果"""
    output_file = "/tmp/memory_analysis_results.json"
    existing_data = {}
    if os.path.exists(output_file):
        try:
            with open(output_file, 'r', encoding='utf-8') as f: existing_data = json.load(f)
        except: pass
    
    # 转换日期为字符串以便序列化
    serializable_results = []
    for r in results:
        r_copy = r.copy()
        if 'timestamp_dt' in r_copy: del r_copy['timestamp_dt']
        serializable_results.append(r_copy)

    all_results_list = existing_data.get('all_results', [])
    all_results_list.extend(serializable_results)
    
    results_summary = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "memory_info": existing_data.get('memory_info', {}),
        "all_results": all_results_list
    }
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results_summary, f, ensure_ascii=False, indent=2)
    except: pass

def main():
    parser = argparse.ArgumentParser(description='内存故障诊断 - 系统消息分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('-k', '--keywords', nargs='+', help='自定义关键字过滤')
    parser.add_argument('-d', '--date', help='日期过滤 (如 "Mar 16")')
    args = parser.parse_args()
    if not os.path.exists(args.log_dir): sys.exit(1)
    analyze_messages_logs(args.log_dir, keywords=args.keywords, date_filter=args.date)

if __name__ == '__main__':
    main()
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

# 网络相关的系统消息关键词
NETWORK_MESSAGE_KEYWORDS = [
    (r"link\s+down|link\s+is\s+down|lost\s+carrier", "网口链路断开"),
    (r"TX\s+unit\s+hang|reset\s+adapter", "适配器挂死/重置"),
    (r"failed\s+to\s+load\s+firmware|firmware\s+failed", "固件加载失败"),
    (r"IP\s+conflict|duplicate\s+address", "IP地址冲突"),
    (r"AER\s+Error|PCIe\s+Bus\s+Error", "PCIe总线严重错误"),
    (r"driver\s+version\s+mismatch", "驱动版本不匹配"),
    (r"netpool.*exhausted", "网络内存池耗尽"),
    (r"Oops|Kernel\s+panic", "内核崩溃"),
    (r"NMI\s+watchdog", "NMI 看门狗超时"),
    (r"ethtool.*command\s+failed", "ethtool 命令失败"),
    (r"vlan.*failed", "VLAN 配置失败"),
    (r"bonding:.*failover|bonding:.*enslave", "Bond 网卡主备切换/成员变动"),
    (r"ICMP\s+fragmentation\s+needed|MTU\s+mismatch", "MTU 不一致/大包丢弃"),
    (r"udev.*persistent-net\.rules|udev.*eth\d+.*renamed", "网卡命名/枚举乱序"),
    (r"arp\s+reply.*conflict|duplicate\s+address", "ARP 冲突/IP 冲突"),
]

def find_message_files(root_dir):
    """查找系统消息日志文件"""
    message_files = []
    # 增加对常见消息日志目录和文件名的宽松识别
    patterns = ['messages', 'syslog', 'journal', 'kern.log', 'dmesg', 'boot.log']
    for root, dirs, files in os.walk(root_dir):
        # 只要在 messages/ 或 syslog/ 目录下，就认为可能包含消息日志
        if any(p in root.lower() for p in ['messages', 'syslog']):
            for file in files:
                if not any(file.lower().endswith(ext) for ext in ['.exe', '.bin', '.dll', '.so']):
                    message_files.append(os.path.join(root, file))
        else:
            for file in files:
                file_lower = file.lower()
                if any(p in file_lower for p in patterns):
                    message_files.append(os.path.join(root, file))
    return message_files

def parse_timestamp(line):
    """解析时间戳"""
    for pattern, _ in TIME_PATTERNS:
        match = re.search(pattern, line)
        if match:
            ts_str = match.group(1)
            fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
            for fmt in fmts:
                try:
                    dt = datetime.strptime(ts_str, fmt)
                    if fmt == "%b %d %H:%M:%S": dt = dt.replace(year=datetime.now().year)
                    return dt, ts_str
                except: continue
    return None, None

def analyze_messages_file(file_path, keywords=None):
    """分析单个消息文件"""
    results = []
    if keywords is None: keywords = NETWORK_MESSAGE_KEYWORDS
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                line_lower = line.lower()
                for pattern, desc in keywords:
                    if re.search(pattern, line_lower, re.IGNORECASE):
                        ts_dt, ts_str = parse_timestamp(line)
                        severity = "INFO"
                        if any(k in line_lower for k in ['error', 'fail', 'fatal', 'panic', 'critical']):
                            severity = "ERROR"
                        elif 'warn' in line_lower:
                            severity = "WARNING"
                            
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "MESSAGE",
                            "line_num": line_num,
                            "timestamp": ts_str,
                            "timestamp_dt": ts_dt,
                            "severity": severity,
                            "description": desc,
                            "line": line.strip()
                        })
                        break
    except: pass
    return results

def analyze_messages_logs(log_dir):
    print(f"🔍 开始系统消息日志分析: {log_dir}")
    print("=" * 60)
    files = find_message_files(log_dir)
    if not files:
        print("❌ 未找到系统消息日志文件")
        return []
    
    print(f"找到 {len(files)} 个系统消息文件")
    all_results = []
    for f_path in files[:10]:
        results = analyze_messages_file(f_path)
        all_results.extend(results)
        
    if all_results:
        print(f"  ✅ 分析完成: 发现 {len(all_results)} 条网络相关消息")
        
    save_results(all_results, log_dir)
    return all_results

def save_results(results, log_dir):
    output_file = "/tmp/network_analysis_results.json"
    existing_data = {}
    if os.path.exists(output_file):
        try:
            with open(output_file, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
        except: pass
    
    error_summary = existing_data.get('error_summary', {'critical_errors': [], 'total_errors': 0})
    all_results_list = existing_data.get('all_results', [])
    
    # 提取错误到摘要
    new_crit = [r for r in results if r["severity"] in ["ERROR", "CRITICAL"]]
    
    error_summary['critical_errors'].extend(new_crit)
    error_summary['total_errors'] += len(results)
    all_results_list.extend(results)
    
    final_data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "error_summary": error_summary,
        "all_results": all_results_list
    }
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
    except: pass

def main():
    parser = argparse.ArgumentParser(description='网络故障诊断 - 系统消息分析')
    parser.add_argument('log_dir')
    args = parser.parse_args()
    analyze_messages_logs(args.log_dir)

if __name__ == '__main__':
    main()
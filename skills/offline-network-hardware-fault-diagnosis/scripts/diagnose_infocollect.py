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

# 网络相关的InfoCollect文件类型
NETWORK_INFO_FILES = {
    "ethtool": ["ethtool.txt", "ethtool_S.txt", "ethtool_i.txt", "ethtool_k.txt"],
    "ip_addr": ["ip_addr.txt", "ifconfig.txt", "ip.txt"],
    "route": ["route.txt", "ip_route.txt"],
    "sar_net": ["sar_net.txt", "sar.txt"],
    "dmesg": ["dmesg.txt", "dmesg.log"],
    "lsmod": ["lsmod.txt", "modules.txt"],
    "lspci": ["lspci.txt", "pci.txt"],
    "vlan": ["vlan.txt", "proc/net/vlan/"],
}

def find_infocollect_files(root_dir):
    """查找InfoCollect相关文件"""
    infocollect_files = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            if any(p in file_lower for p in ['ethtool', 'ifconfig', 'ip_addr', 'route', 'sar_net', 'lspci', 'lsmod', 'netstat', 'dmesg']):
                infocollect_files.append(os.path.join(root, file))
    return infocollect_files

def classify_network_file(file_path):
    """分类网络相关文件"""
    filename = os.path.basename(file_path).lower()
    for f_type, patterns in NETWORK_INFO_FILES.items():
        for p in patterns:
            if p in filename: return f_type
    return "other"

def analyze_ethtool(file_path):
    """分析 ethtool 统计信息"""
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            errors = re.findall(r'(?:rx_|tx_)?(errors|dropped|overruns|crc_errors|fifo_errors|collisions):\s*([1-9]\d*)', content)
            for err_type, count in errors:
                results.append({
                    "file": os.path.basename(file_path),
                    "type": "ETHTOOL_STAT",
                    "error_type": err_type,
                    "count": int(count),
                    "description": f"发现网卡计数器异常: {err_type}={count}"
                })
    except: pass
    return results

def analyze_ip_addr(file_path):
    """分析 IP 地址和接口状态"""
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            # 简单的接口切割
            interfaces = re.split(r'\d+:\s+', content)
            for iface in interfaces:
                if not iface.strip(): continue
                name_match = re.search(r'^([a-z0-9]+):\s+', iface)
                if name_match:
                    name = name_match.group(1)
                    if 'state DOWN' in iface or 'NO-CARRIER' in iface:
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "INTERFACE_DOWN",
                            "interface": name,
                            "description": f"接口 {name} 处于 DOWN 或 NO-CARRIER 状态"
                        })
    except: pass
    return results

def analyze_infocollect_logs(log_dir):
    print(f"🔍 开始InfoCollect日志分析: {log_dir}")
    print("=" * 60)
    files = find_infocollect_files(log_dir)
    if not files:
        print("❌ 未找到网络相关日志文件")
        return []
    
    print(f"找到 {len(files)} 个相关文件")
    all_results = []
    
    for f_path in files:
        f_type = classify_network_file(f_path)
        if f_type == "ethtool":
            all_results.extend(analyze_ethtool(f_path))
        elif f_type == "ip_addr":
            all_results.extend(analyze_ip_addr(f_path))
            
    # 输出汇总
    err_count = len(all_results)
    print(f"  ✅ 分析完成: 发现 {err_count} 条潜在异常记录")
    
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
    new_crit = [r for r in results if r["type"] in ["ETHTOOL_STAT", "INTERFACE_DOWN"]]
    
    error_summary['critical_errors'].extend(new_crit)
    error_summary['total_errors'] += len(new_crit)
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
    parser = argparse.ArgumentParser(description='网络故障诊断 - InfoCollect分析')
    parser.add_argument('log_dir')
    args = parser.parse_args()
    analyze_infocollect_logs(args.log_dir)

if __name__ == '__main__':
    main()
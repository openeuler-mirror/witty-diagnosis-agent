#!/usr/bin/env python3
import os
import sys
import re
import argparse
import tarfile
import sqlite3
import json
from datetime import datetime
from collections import defaultdict

TIME_PATTERNS = [
    (r'(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})', "MMM D HH:MM:SS (Syslog)"),
    (r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})', "YYYY-MM-DD HH:MM:SS (ISO)"),
    (r'(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})', "MM/DD/YYYY HH:MM:SS (SEL)"),
]

# 网络相关的iBMC SEL事件关键词
NETWORK_SEL_KEYWORDS = [
    ("NIC.*failure", "网卡故障"),
    ("NIC.*hardware.*fault", "网卡硬件故障"),
    ("PCIe.*error", "PCIe总线错误"),
    ("PCIe.*Fatal", "PCIe致命错误"),
    ("NIC.*Temperature.*high", "网卡温度过高"),
    ("NIC.*thermal", "网卡热管理告警"),
    ("NIC.*power.*fail", "网卡电源故障"),
    ("SFP.*failure", "光模块故障"),
    ("network.*port.*down", "网络端口关闭"),
    ("PHY.*error", "PHY芯片错误"),
    ("Link.*training.*failed", "链路训练失败"),
    ("NIC.*presence", "网卡在位检测"),
]

def find_ibmc_files(root_dir):
    """查找iBMC/HDM相关文件"""
    ibmc_files = []
    # 增加对常见带外日志目录名和文件名的识别
    patterns = ['ibmc', 'sel', 'bmc', 'ipmi', 'sensor', 'onekeylog', 'hdm', 'event', 'alarm']
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            if any(p in file_lower for p in patterns) or any(p in root.lower() for p in patterns):
                # 排除明显的非日志文件
                if not any(file_lower.endswith(ext) for ext in ['.exe', '.dll', '.so', '.bin']):
                    ibmc_files.append(os.path.join(root, file))
    return ibmc_files

def analyze_sel_db(file_path):
    results = []
    try:
        conn = sqlite3.connect(file_path)
        cursor = conn.cursor()
        table_names = ['sel', 'SEL', 'sel_log', 'SEL_LOG', 'events', 'EVENTS']
        for table in table_names:
            try:
                cursor.execute(f"SELECT * FROM {table} LIMIT 50")
                rows = cursor.fetchall()
                if rows:
                    cursor.execute(f"PRAGMA table_info({table})")
                    columns = [col[1] for col in cursor.fetchall()]
                    for row in rows:
                        row_dict = dict(zip(columns, row))
                        results.append({"file": os.path.basename(file_path), "type": "SEL_DB", "data": row_dict})
                    break
            except: continue
        conn.close()
    except: pass
    return results

def analyze_sensor_file(file_path):
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line_lower = line.lower()
                if 'nic' in line_lower or 'network' in line_lower:
                    if 'temperature' in line_lower or 'temp' in line_lower:
                        temp_match = re.search(r'(\d+\.?\d*)\s*°?[Cc]', line)
                        if temp_match:
                            temp = float(temp_match.group(1))
                            status = "正常"
                            if temp > 85: status = "警告"
                            if temp > 95: status = "危险"
                            results.append({"file": os.path.basename(file_path), "type": "SENSOR_TEMP", "sensor": "网卡温度", "value": temp, "status": status, "line": line.strip()})
    except: pass
    return results

def analyze_text_file(file_path, keywords=None):
    results = []
    if keywords is None: keywords = NETWORK_SEL_KEYWORDS
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                line_lower = line.lower()
                for pattern, description in keywords:
                    if re.search(pattern, line_lower, re.IGNORECASE):
                        timestamp = None
                        for time_pattern, _ in TIME_PATTERNS:
                            match = re.search(time_pattern, line)
                            if match:
                                timestamp = match.group(1)
                                break
                        results.append({"file": os.path.basename(file_path), "type": "TEXT", "line_num": line_num, "timestamp": timestamp, "description": description, "line": line.strip()})
                        break
    except: pass
    return results

def analyze_ibmc_logs(log_dir, keywords=None):
    print(f"🔍 开始iBMC日志专项分析: {log_dir}")
    ibmc_files = find_ibmc_files(log_dir)
    if not ibmc_files:
        print("❌ 未找到iBMC相关日志文件")
        return []
    
    all_results = []
    for f_path in ibmc_files:
        fname = os.path.basename(f_path).lower()
        if fname.endswith('.db'):
            all_results.extend(analyze_sel_db(f_path))
        elif 'sensor' in fname:
            all_results.extend(analyze_sensor_file(f_path))
        elif 'selelist' in fname or 'sel_log' in fname or 'bmc_log' in fname:
            all_results.extend(analyze_text_file(f_path, keywords))
            
    # 输出汇总
    error_count = len([r for r in all_results if r.get("type") == "TEXT"])
    print(f"  ✅ 分析完成: 发现 {error_count} 条相关硬件记录")
    
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
    
    all_results_list = existing_data.get('all_results', [])
    all_results_list.extend(results)
    
    final_data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "all_results": all_results_list
    }
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
    except: pass

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('log_dir')
    args = parser.parse_args()
    analyze_ibmc_logs(args.log_dir)

if __name__ == '__main__':
    main()
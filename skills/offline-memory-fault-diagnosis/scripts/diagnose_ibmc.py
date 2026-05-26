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

# 内存相关的iBMC SEL事件关键词
MEMORY_SEL_KEYWORDS = [
    # 内存ECC错误
    ("Memory.*Correctable Error", "内存可纠正错误(CE)"),
    ("Memory.*Uncorrectable Error", "内存不可纠正错误(UCE)"),
    ("Memory.*ECC.*error", "内存纠错码异常"),
    ("DIMM.*Machine Check", "内存硬件检查异常"),
    ("MEM.*fatal error", "内存致命错误"),
    
    # 内存槽位/在位
    ("DIMM.*Presence", "内存条不在位/检测失败"),
    ("DIMM.*Configuration", "内存配置不匹配"),
    ("DIMM.*Missing", "找不到内存条"),
    
    # 内存状态/故障
    ("DIMM.*failed", "内存条已进入失效状态"),
    ("DIMM.*Warning", "内存条告警"),
    ("DIMM.*Predictive.*Failure", "内存条预测性故障"),
    
    # 内存电压与SPD
    ("Memory.*Voltage.*error", "内存电压错误"),
    ("SPD.*error", "内存SPD信息读取异常"),
    ("Memory.*Initializ.*Fail", "内存初始化失败"),
]

def find_ibmc_files(root_dir):
    """查找iBMC相关文件"""
    ibmc_files = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            if any(pattern in file_lower for pattern in ['ibmc', 'sel', 'bmc', 'ipmi', 'sensor', 'event']):
                ibmc_files.append(os.path.join(root, file))
    return ibmc_files

def analyze_sel_db(file_path):
    """分析SEL数据库文件"""
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
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "SEL_DB",
                            "data": dict(zip(columns, row))
                        })
                    break
            except: continue
        conn.close()
    except Exception as e:
        print(f"⚠️  无法分析SEL数据库 {file_path}: {str(e)}")
    return results

def analyze_sensor_file(file_path):
    """分析传感器文件"""
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line_lower = line.lower()
                if any(keyword in line_lower for keyword in ['dimm', 'memory', 'mem']):
                    if 'temperature' in line_lower or 'temp' in line_lower:
                        temp_match = re.search(r'(\d+\.?\d*)\s*°?[Cc]', line)
                        if temp_match:
                            temp = float(temp_match.group(1))
                            status = "正常"
                            if temp > 80: status = "警告"
                            if temp > 90: status = "危险"
                            results.append({
                                "file": os.path.basename(file_path),
                                "type": "SENSOR_TEMP",
                                "sensor": "DIMM温度",
                                "value": temp,
                                "unit": "°C",
                                "status": status,
                                "line": line.strip()
                            })
                    elif 'voltage' in line_lower:
                        volt_match = re.search(r'(\d+\.?\d*)\s*[Vv]', line)
                        if volt_match:
                            volt = float(volt_match.group(1))
                            status = "正常"
                            if volt < 1.0 or volt > 1.4: status = "异常"
                            results.append({
                                "file": os.path.basename(file_path),
                                "type": "SENSOR_VOLT",
                                "sensor": "DIMM电压",
                                "value": volt,
                                "unit": "V",
                                "status": status,
                                "line": line.strip()
                            })
    except: pass
    return results

def analyze_ibmc_logs(log_dir, keywords=None, date_filter=None):
    print(f"🔍 开始iBMC日志分析: {log_dir}")
    print("=" * 60)
    ibmc_files = find_ibmc_files(log_dir)
    if not ibmc_files:
        print("❌ 未找到iBMC相关日志文件")
        return []
        
    all_results = []
    # 如果用户提供了自定义关键词，将其转换为元组格式以兼容后续处理
    search_patterns = []
    if keywords:
        for k in keywords:
            search_patterns.append((re.escape(k), f"自定义搜索: {k}"))
    else:
        search_patterns = MEMORY_SEL_KEYWORDS

    for file_path in ibmc_files:
        filename = os.path.basename(file_path).lower()
        if filename.endswith('.db') or 'sel.db' in filename:
            all_results.extend(analyze_sel_db(file_path))
        elif 'sensor' in filename:
            all_results.extend(analyze_sensor_file(file_path))
        else:
            # 传递 date_filter 给 analyze_text_file (需要修改 analyze_text_file)
            all_results.extend(analyze_text_file(file_path, search_patterns, date_filter))
            
    print(f"📊 分析汇总: 找到 {len(all_results)} 条记录")
    
    # 按错误分发统计
    memory_errors = [r for r in all_results if r.get("type") == "TEXT"]
    if memory_errors:
        print(f"🚨 发现 {len(memory_errors)} 条关键内存故障记录:")
        for res in memory_errors[:10]:
            print(f"  [{res.get('timestamp','?')}] {res['description']}: {res['line'][:100]}...")
            
    temp_abnormal = [r for r in all_results if r.get("type") == "SENSOR_TEMP" and r.get("status") != "正常"]
    if temp_abnormal:
        print(f"🌡️  发现 {len(temp_abnormal)} 条内存温度异常记录")
        for res in temp_abnormal[:3]:
            print(f"  - {res['sensor']}: {res['value']}{res['unit']} ({res['status']})")
            
    save_results(all_results, log_dir)
    print("=" * 60)
    print("✅ iBMC日志分析完成")
    return all_results

def analyze_text_file(file_path, keywords, date_filter=None):
    """分析文本文件中的内存相关错误，支持日期过滤"""
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
                            "type": "TEXT",
                            "line_num": line_num,
                            "timestamp": ts,
                            "pattern": pattern,
                            "description": description,
                            "line": line.strip()
                        })
                        break
    except: pass
    return results

def save_results(results, log_dir):
    """保存并将结果整合到 JSON 文件"""
    output_file = "/tmp/memory_analysis_results.json"
    existing_data = {}
    if os.path.exists(output_file):
        try:
            with open(output_file, 'r', encoding='utf-8') as f: existing_data = json.load(f)
        except: pass
    
    ibmc_errors = [r for r in results if r.get("type") == "TEXT" and ("ERROR" in r.get("description", "").upper() or "FAIL" in r.get("description", "").upper())]
    all_results_list = existing_data.get('all_results', [])
    all_results_list.extend(results)
    
    results_summary = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "memory_info": existing_data.get('memory_info', {}),
        "ibmc_error_count": len(ibmc_errors),
        "sensor_alerts": [r for r in results if r.get("status") in ["警告", "危险", "异常"]],
        "all_results": all_results_list
    }
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results_summary, f, ensure_ascii=False, indent=2)
    except: pass

def main():
    parser = argparse.ArgumentParser(description='内存故障诊断 - iBMC日志分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('-k', '--keywords', nargs='+', help='自定义关键字过滤')
    parser.add_argument('-d', '--date', help='日期过滤 (如 "2025-07-21")')
    args = parser.parse_args()
    if not os.path.exists(args.log_dir): sys.exit(1)
    analyze_ibmc_logs(args.log_dir, keywords=args.keywords, date_filter=args.date)

if __name__ == '__main__':
    main()
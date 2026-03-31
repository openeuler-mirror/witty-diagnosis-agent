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

# CPU相关的iBMC SEL事件关键词
CPU_SEL_KEYWORDS = [
    # CPU硬件错误
    ("CPU.*Correctable Error", "CPU可纠正错误"),
    ("CPU.*Uncorrectable Error", "CPU不可纠正错误"),
    ("CPU.*Machine Check", "CPU机器检查异常"),
    ("CPU.*fatal error", "CPU致命错误"),
    ("CPU.*hardware error", "CPU硬件错误"),
    
    # CPU温度相关
    ("CPU.*Thermal Trip", "CPU温度触发保护"),
    ("CPU.*Temperature.*high", "CPU温度过高"),
    ("CPU.*over temperature", "CPU过热"),
    ("CPU.*thermal shutdown", "CPU热关机"),
    
    # CPU电压相关
    ("CPU.*Voltage.*error", "CPU电压错误"),
    ("VRM.*error", "电压调节模块错误"),
    ("CPU.*power.*fail", "CPU电源故障"),
    
    # CPU其他
    ("CPU.*presence", "CPU在位检测"),
    ("CPU.*configuration", "CPU配置错误"),
    ("CPU.*performance", "CPU性能问题"),
]

def find_ibmc_files(root_dir):
    """查找iBMC相关文件"""
    ibmc_files = []
    
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            if any(pattern in file_lower for pattern in ['ibmc', 'sel', 'bmc', 'ipmi', 'sensor']):
                ibmc_files.append(os.path.join(root, file))
    
    return ibmc_files

def analyze_sel_db(file_path):
    """分析SEL数据库文件"""
    results = []
    
    try:
        conn = sqlite3.connect(file_path)
        cursor = conn.cursor()
        
        # 尝试常见的表名
        table_names = ['sel', 'SEL', 'sel_log', 'SEL_LOG', 'events', 'EVENTS']
        
        for table in table_names:
            try:
                cursor.execute(f"SELECT * FROM {table} LIMIT 10")
                rows = cursor.fetchall()
                
                if rows:
                    # 获取列名
                    cursor.execute(f"PRAGMA table_info({table})")
                    columns = [col[1] for col in cursor.fetchall()]
                    
                    for row in rows:
                        row_dict = dict(zip(columns, row))
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "SEL_DB",
                            "data": row_dict
                        })
                    break
            except:
                continue
        
        conn.close()
    except Exception as e:
        print(f"⚠️  无法分析SEL数据库 {file_path}: {str(e)}")
    
    return results

def analyze_sel_tar(file_path):
    """分析SEL压缩文件"""
    results = []
    
    try:
        with tarfile.open(file_path, 'r') as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith('.csv'):
                    try:
                        f = tar.extractfile(member)
                        content = f.read().decode('utf-8', errors='ignore')
                        
                        # 解析CSV内容
                        lines = content.split('\n')
                        for line in lines[:50]:  # 只分析前50行
                            if line.strip():
                                results.append({
                                    "file": os.path.basename(file_path),
                                    "type": "SEL_TAR",
                                    "member": member.name,
                                    "line": line.strip()
                                })
                    except:
                        continue
    except Exception as e:
        print(f"⚠️  无法分析SEL压缩文件 {file_path}: {str(e)}")
    
    return results

def analyze_sensor_file(file_path):
    """分析传感器文件"""
    results = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
            for line in lines:
                line_lower = line.lower()
                
                # 检查CPU相关传感器
                if any(keyword in line_lower for keyword in ['cpu', 'core', 'processor']):
                    # 提取温度、电压、功耗等信息
                    if 'temperature' in line_lower or 'temp' in line_lower:
                        # 尝试提取温度值
                        temp_match = re.search(r'(\d+\.?\d*)\s*°?[Cc]', line)
                        if temp_match:
                            temp = float(temp_match.group(1))
                            status = "正常"
                            if temp > 90:
                                status = "警告"
                            if temp > 100:
                                status = "危险"
                            
                            results.append({
                                "file": os.path.basename(file_path),
                                "type": "SENSOR_TEMP",
                                "sensor": "CPU温度",
                                "value": temp,
                                "unit": "°C",
                                "status": status,
                                "line": line.strip()
                            })
                    
                    elif 'voltage' in line_lower or 'vcore' in line_lower:
                        # 尝试提取电压值
                        volt_match = re.search(r'(\d+\.?\d*)\s*[Vv]', line)
                        if volt_match:
                            volt = float(volt_match.group(1))
                            status = "正常"
                            if volt < 0.8 or volt > 1.5:
                                status = "异常"
                            
                            results.append({
                                "file": os.path.basename(file_path),
                                "type": "SENSOR_VOLT",
                                "sensor": "CPU电压",
                                "value": volt,
                                "unit": "V",
                                "status": status,
                                "line": line.strip()
                            })
                    
                    elif 'power' in line_lower:
                        # 尝试提取功耗值
                        power_match = re.search(r'(\d+\.?\d*)\s*[Ww]', line)
                        if power_match:
                            power = float(power_match.group(1))
                            
                            results.append({
                                "file": os.path.basename(file_path),
                                "type": "SENSOR_POWER",
                                "sensor": "CPU功耗",
                                "value": power,
                                "unit": "W",
                                "line": line.strip()
                            })
    except Exception as e:
        print(f"⚠️  无法分析传感器文件 {file_path}: {str(e)}")
    
    return results

def analyze_text_file(file_path, keywords=None):
    """分析文本文件中的CPU相关错误"""
    results = []
    
    if keywords is None:
        keywords = CPU_SEL_KEYWORDS
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            for line_num, line in enumerate(content.split('\n'), 1):
                line_lower = line.lower()
                
                # 检查每个关键词
                for pattern, description in keywords:
                    if re.search(pattern, line_lower, re.IGNORECASE):
                        # 提取时间戳（如果存在）
                        timestamp = None
                        for time_pattern, fmt_name in TIME_PATTERNS:
                            match = re.search(time_pattern[0], line)
                            if match:
                                timestamp = match.group(1)
                                break
                        
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "TEXT",
                            "line_num": line_num,
                            "timestamp": timestamp,
                            "pattern": pattern,
                            "description": description,
                            "line": line.strip()
                        })
                        break  # 每行只匹配一个关键词
    except Exception as e:
        print(f"⚠️  无法分析文本文件 {file_path}: {str(e)}")
    
    return results

def analyze_ibmc_logs(log_dir, keywords=None, date_filter=None, start_time=None, end_time=None):
    """分析iBMC日志目录"""
    print(f"🔍 开始iBMC日志分析: {log_dir}")
    print("=" * 60)
    
    # 查找iBMC文件
    ibmc_files = find_ibmc_files(log_dir)
    
    if not ibmc_files:
        print("❌ 未找到iBMC相关日志文件")
        return []
    
    print(f"找到 {len(ibmc_files)} 个iBMC相关文件")
    
    # 分类文件
    sel_db_files = []
    sel_tar_files = []
    sensor_files = []
    text_files = []
    
    for file_path in ibmc_files:
        filename = os.path.basename(file_path).lower()
        
        if filename.endswith('.db') or 'sel.db' in filename:
            sel_db_files.append(file_path)
        elif filename.endswith('.tar') or filename.endswith('.tar.gz') or filename.endswith('.tgz'):
            sel_tar_files.append(file_path)
        elif 'sensor' in filename:
            sensor_files.append(file_path)
        else:
            text_files.append(file_path)
    
    print(f"  - SEL数据库文件: {len(sel_db_files)} 个")
    print(f"  - SEL压缩文件: {len(sel_tar_files)} 个")
    print(f"  - 传感器文件: {len(sensor_files)} 个")
    print(f"  - 文本文件: {len(text_files)} 个")
    print("-" * 60)
    
    all_results = []
    
    # 分析SEL数据库文件
    if sel_db_files:
        print("📊 分析SEL数据库文件:")
        for file_path in sel_db_files[:3]:  # 最多分析3个文件
            filename = os.path.basename(file_path)
            print(f"  - {filename}")
            results = analyze_sel_db(file_path)
            all_results.extend(results)
            
            if results:
                print(f"    找到 {len(results)} 条SEL记录")
            else:
                print(f"    未找到有效SEL记录")
    
    # 分析SEL压缩文件
    if sel_tar_files:
        print("\n📊 分析SEL压缩文件:")
        for file_path in sel_tar_files[:2]:  # 最多分析2个文件
            filename = os.path.basename(file_path)
            print(f"  - {filename}")
            results = analyze_sel_tar(file_path)
            all_results.extend(results)
            
            if results:
                print(f"    找到 {len(results)} 条SEL记录")
            else:
                print(f"    未找到有效SEL记录")
    
    # 分析传感器文件
    if sensor_files:
        print("\n📊 分析传感器文件:")
        for file_path in sensor_files[:5]:  # 最多分析5个文件
            filename = os.path.basename(file_path)
            print(f"  - {filename}")
            results = analyze_sensor_file(file_path)
            all_results.extend(results)
            
            if results:
                print(f"    找到 {len(results)} 条传感器记录")
                
                # 输出温度警告
                temp_results = [r for r in results if r["type"] == "SENSOR_TEMP"]
                for temp_result in temp_results:
                    if temp_result["status"] in ["警告", "危险"]:
                        print(f"    ⚠️  {temp_result['sensor']}: {temp_result['value']}{temp_result['unit']} ({temp_result['status']})")
            else:
                print(f"    未找到有效传感器记录")
    
    # 分析文本文件
    if text_files:
        print("\n📊 分析文本文件中的CPU错误:")
        cpu_error_count = 0
        
        for file_path in text_files[:10]:  # 最多分析10个文件
            filename = os.path.basename(file_path)
            results = analyze_text_file(file_path, keywords)
            
            if results:
                cpu_error_count += len(results)
                print(f"  - {filename}: 找到 {len(results)} 条CPU相关错误")
                
                # 输出前3条错误
                for result in results[:3]:
                    print(f"    第{result['line_num']}行: {result['description']}")
                    if result['timestamp']:
                        print(f"      时间: {result['timestamp']}")
        
        if cpu_error_count == 0:
            print("  ✅ 未发现CPU相关错误")
    
    print("-" * 60)
    
    # 汇总分析结果
    if all_results:
        print("📈 iBMC日志分析汇总:")
        
        # 按类型统计
        type_counts = defaultdict(int)
        for result in all_results:
            type_counts[result["type"]] += 1
        
        for type_name, count in sorted(type_counts.items()):
            print(f"  {type_name}: {count} 条记录")
        
        # 检查CPU相关错误
        cpu_errors = []
        for result in all_results:
            if "CPU" in str(result).upper():
                cpu_errors.append(result)
        
        if cpu_errors:
            print(f"\n🚨 发现 {len(cpu_errors)} 条CPU相关错误/警告:")
            
            # 按错误类型分组
            error_types = defaultdict(list)
            for error in cpu_errors:
                if "description" in error:
                    error_types[error["description"]].append(error)
                elif "sensor" in error:
                    error_types[error["sensor"]].append(error)
            
            for error_type, errors in error_types.items():
                print(f"  - {error_type}: {len(errors)} 条")
                
                # 输出严重错误
                severe_errors = [e for e in errors if "status" in e and e["status"] in ["危险", "警告"]]
                if severe_errors:
                    for error in severe_errors[:2]:
                        if "value" in error:
                            print(f"    {error['value']}{error.get('unit', '')} ({error['status']})")
        
        # 检查温度问题
        temp_results = [r for r in all_results if r["type"] == "SENSOR_TEMP"]
        if temp_results:
            high_temps = [t for t in temp_results if t["status"] in ["警告", "危险"]]
            if high_temps:
                print(f"\n🌡️  CPU温度异常:")
                for temp in high_temps[:5]:
                    print(f"  - {temp['sensor']}: {temp['value']}{temp['unit']} ({temp['status']})")
        
        # 检查电压问题
        volt_results = [r for r in all_results if r["type"] == "SENSOR_VOLT"]
        if volt_results:
            abnormal_volts = [v for v in volt_results if v["status"] == "异常"]
            if abnormal_volts:
                print(f"\n⚡ CPU电压异常:")
                for volt in abnormal_volts[:5]:
                    print(f"  - {volt['sensor']}: {volt['value']}{volt['unit']} ({volt['status']})")
    else:
        print("ℹ️  未在iBMC日志中发现有效记录")
    
    print("=" * 60)
    print("✅ iBMC日志分析完成")
    
    # 保存结果到文件以便报告生成
    save_results(all_results, log_dir)
    
    return all_results

def save_results(results, log_dir):
    """保存分析结果到文件"""
    output_file = "/tmp/cpu_analysis_results.json"
    
    # 尝试加载现有结果，如果是其它脚本生成的，我们补充它
    existing_data = {}
    if os.path.exists(output_file):
        try:
            with open(output_file, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
        except:
            pass
            
    # 汇总逻辑
    temp_summary = existing_data.get('temperature_summary', {'high_temps': [], 'total_readings': 0})
    error_summary = existing_data.get('error_summary', {'critical_errors': [], 'total_errors': 0})
    all_results_list = existing_data.get('all_results', [])
    
    # 从本次结果提取
    ibmc_high_temps = [r for r in results if r["type"] == "SENSOR_TEMP" and r["status"] in ["警告", "危险"]]
    ibmc_errors = [r for r in results if r["type"] == "TEXT" and "ERROR" in r.get("description", "").upper()]
    
    temp_summary['high_temps'].extend(ibmc_high_temps)
    temp_summary['total_readings'] += len([r for r in results if r["type"] == "SENSOR_TEMP"])
    error_summary['critical_errors'].extend(ibmc_errors)
    error_summary['total_errors'] += len(ibmc_errors)
    all_results_list.extend(results)
    
    results_summary = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "cpu_info": existing_data.get('cpu_info', {}),
        "temperature_summary": temp_summary,
        "error_summary": error_summary,
        "frequency_summary": existing_data.get('frequency_summary', {'throttling_count': 0, 'total_readings': 0}),
        "all_results": all_results_list
    }
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results_summary, f, ensure_ascii=False, indent=2)
    except:
        pass

def main():
    parser = argparse.ArgumentParser(description='CPU故障诊断 - iBMC日志分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('-o', '--overview', action='store_true', help='概览模式')
    parser.add_argument('-k', '--keywords', nargs='+', help='自定义关键词过滤')
    parser.add_argument('-d', '--date', help='日期过滤（如 "Mar 16"）')
    parser.add_argument('-s', '--start-time', help='开始时间（格式: YYYY-MM-DD HH:MM:SS）')
    parser.add_argument('-e', '--end-time', help='结束时间（格式: YYYY-MM-DD HH:MM:SS）')
    
    args = parser.parse_args()
    
    if not os.path.isdir(args.log_dir):
        print(f"❌ 错误: 目录 '{args.log_dir}' 不存在")
        sys.exit(1)
    
    # 执行iBMC日志分析
    results = analyze_ibmc_logs(
        args.log_dir,
        keywords=args.keywords,
        date_filter=args.date,
        start_time=args.start_time,
        end_time=args.end_time
    )
    
    # 如果有结果，返回成功
    if results:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
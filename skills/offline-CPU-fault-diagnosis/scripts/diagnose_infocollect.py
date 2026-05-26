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

# CPU相关的InfoCollect文件类型
CPU_INFO_FILES = {
    "cpuinfo": ["cpuinfo.txt", "cpu_info.txt", "proc/cpuinfo"],
    "dmesg": ["dmesg.txt", "dmesg.log"],
    "thermal": ["thermal.txt", "temperature.txt", "sensors.txt"],
    "cpufreq": ["cpufreq.txt", "cpu_freq.txt", "frequency.txt"],
    "turbostat": ["turbostat.txt", "cpu_stat.txt"],
    "perf": ["perf.txt", "performance.txt"],
    "microcode": ["microcode.txt", "ucode.txt"],
    "mce": ["mce.txt", "machine_check.txt"],
}

# CPU错误关键词
CPU_ERROR_KEYWORDS = [
    # MCE错误
    ("MCE:.*CPU", "CPU机器检查异常"),
    ("machine check.*CPU", "CPU机器检查"),
    ("CPU.*MCE", "CPU机器检查错误"),
    
    # 缓存错误
    ("cache error.*CPU", "CPU缓存错误"),
    ("CPU.*cache.*error", "CPU缓存错误"),
    ("ECC.*CPU", "CPU ECC错误"),
    ("L1.*error", "L1缓存错误"),
    ("L2.*error", "L2缓存错误"),
    ("L3.*error", "L3缓存错误"),
    
    # 微码错误
    ("microcode.*error", "微码错误"),
    ("CPU.*microcode", "CPU微码问题"),
    ("ucode.*error", "微码错误"),
    
    # 温度错误
    ("CPU.*over temperature", "CPU过热"),
    ("thermal.*CPU", "CPU热管理错误"),
    ("CPU.*throttling", "CPU降频"),
    
    # 其他错误
    ("CPU.*fatal", "CPU致命错误"),
    ("CPU.*panic", "CPU恐慌"),
    ("CPU.*stall", "CPU停滞"),
]

def find_infocollect_files(root_dir):
    """查找InfoCollect相关文件"""
    infocollect_files = []
    
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            # 检查是否是InfoCollect相关文件
            if any(pattern in file_lower for pattern in ['infocollect', 'cpuinfo', 'dmesg', 'thermal', 'cpufreq']):
                infocollect_files.append(os.path.join(root, file))
            # 检查是否在system目录下
            elif 'system' in root.lower() and file_lower.endswith('.txt'):
                infocollect_files.append(os.path.join(root, file))
    
    return infocollect_files

def classify_cpu_file(file_path):
    """分类CPU相关文件"""
    filename = os.path.basename(file_path).lower()
    
    for file_type, patterns in CPU_INFO_FILES.items():
        for pattern in patterns:
            if pattern in filename:
                return file_type
    
    # 根据内容判断
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read(1024).lower()
            
            if 'processor' in content and 'cpu' in content:
                return "cpuinfo"
            elif 'mce' in content or 'machine check' in content:
                return "mce"
            elif 'temperature' in content or 'thermal' in content:
                return "thermal"
            elif 'frequency' in content or 'cpufreq' in content:
                return "cpufreq"
            elif 'microcode' in content:
                return "microcode"
    except:
        pass
    
    return "other"

def analyze_cpuinfo(file_path):
    """分析CPU信息文件"""
    results = []
    cpu_info = {
        "processors": 0,
        "cores_per_socket": 0,
        "sockets": 0,
        "model": "未知",
        "frequency": "未知",
        "cache_size": "未知",
        "microcode": "未知",
    }
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            # 统计处理器数量
            processor_matches = re.findall(r'processor\s*:\s*\d+', content, re.IGNORECASE)
            cpu_info["processors"] = len(processor_matches)
            
            # 提取CPU型号
            model_match = re.search(r'model name\s*:\s*(.+)', content, re.IGNORECASE)
            if model_match:
                cpu_info["model"] = model_match.group(1).strip()
            
            # 提取CPU频率
            freq_match = re.search(r'cpu mhz\s*:\s*(\d+\.?\d*)', content, re.IGNORECASE)
            if freq_match:
                freq = float(freq_match.group(1))
                cpu_info["frequency"] = f"{freq:.2f} MHz"
            
            # 提取缓存大小
            cache_matches = re.findall(r'cache size\s*:\s*(\d+)\s*KB', content, re.IGNORECASE)
            if cache_matches:
                total_cache = sum(int(size) for size in cache_matches)
                cpu_info["cache_size"] = f"{total_cache} KB"
            
            # 提取微码版本
            microcode_match = re.search(r'microcode\s*:\s*(0x[0-9a-f]+)', content, re.IGNORECASE)
            if microcode_match:
                cpu_info["microcode"] = microcode_match.group(1).strip()
            
            # 提取核心和插槽信息
            core_match = re.search(r'cpu cores\s*:\s*(\d+)', content, re.IGNORECASE)
            if core_match:
                cpu_info["cores_per_socket"] = int(core_match.group(1))
            
            if cpu_info["processors"] > 0 and cpu_info["cores_per_socket"] > 0:
                cpu_info["sockets"] = cpu_info["processors"] // cpu_info["cores_per_socket"]
        
        results.append({
            "file": os.path.basename(file_path),
            "type": "CPUINFO",
            "info": cpu_info
        })
        
    except Exception as e:
        print(f"⚠️  无法分析CPU信息文件 {file_path}: {str(e)}")
    
    return results

def analyze_dmesg(file_path, keywords=None):
    """分析dmesg文件中的CPU错误"""
    results = []
    
    if keywords is None:
        keywords = CPU_ERROR_KEYWORDS
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
            for line_num, line in enumerate(lines, 1):
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
                        
                        # 提取CPU编号（如果存在）
                        cpu_match = re.search(r'CPU[:\s]*(\d+)', line, re.IGNORECASE)
                        cpu_num = cpu_match.group(1) if cpu_match else "未知"
                        
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "DMESG_ERROR",
                            "line_num": line_num,
                            "timestamp": timestamp,
                            "cpu": cpu_num,
                            "pattern": pattern,
                            "description": description,
                            "line": line.strip()
                        })
                        break  # 每行只匹配一个关键词
    except Exception as e:
        print(f"⚠️  无法分析dmesg文件 {file_path}: {str(e)}")
    
    return results

def analyze_thermal(file_path):
    """分析温度文件"""
    results = []
    temp_readings = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
            for line in lines:
                line_lower = line.lower()
                
                # 查找CPU温度
                if any(keyword in line_lower for keyword in ['cpu', 'core', 'package']):
                    # 尝试提取温度值
                    temp_match = re.search(r'(\d+\.?\d*)\s*°?[Cc]', line)
                    if temp_match:
                        temp = float(temp_match.group(1))
                        temp_readings.append(temp)
                        
                        # 确定温度状态
                        status = "正常"
                        if temp > 80:
                            status = "注意"
                        if temp > 90:
                            status = "警告"
                        if temp > 100:
                            status = "危险"
                        
                        # 提取传感器名称
                        sensor_name = "未知"
                        name_match = re.search(r'([a-zA-Z0-9_]+)\s*:', line)
                        if name_match:
                            sensor_name = name_match.group(1)
                        
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "THERMAL",
                            "sensor": sensor_name,
                            "temperature": temp,
                            "unit": "°C",
                            "status": status,
                            "line": line.strip()
                        })
        
        # 计算统计信息
        if temp_readings:
            avg_temp = sum(temp_readings) / len(temp_readings)
            max_temp = max(temp_readings)
            min_temp = min(temp_readings)
            
            results.append({
                "file": os.path.basename(file_path),
                "type": "THERMAL_STATS",
                "avg_temperature": avg_temp,
                "max_temperature": max_temp,
                "min_temperature": min_temp,
                "readings_count": len(temp_readings)
            })
        
    except Exception as e:
        print(f"⚠️  无法分析温度文件 {file_path}: {str(e)}")
    
    return results

def analyze_cpufreq(file_path):
    """分析CPU频率文件"""
    results = []
    freq_readings = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
            for line in lines:
                line_lower = line.lower()
                
                # 查找CPU频率
                if 'frequency' in line_lower or 'mhz' in line_lower or 'ghz' in line_lower:
                    # 尝试提取频率值
                    freq_match = re.search(r'(\d+\.?\d*)\s*(MHz|GHz|Mhz|Ghz)', line, re.IGNORECASE)
                    if freq_match:
                        freq = float(freq_match.group(1))
                        unit = freq_match.group(2).upper()
                        
                        # 转换为MHz
                        if unit == 'GHZ':
                            freq = freq * 1000
                        
                        freq_readings.append(freq)
                        
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "CPUFREQ",
                            "frequency": freq,
                            "unit": "MHz",
                            "line": line.strip()
                        })
                
                # 查找降频信息
                elif 'throttling' in line_lower or 'throttle' in line_lower:
                    results.append({
                        "file": os.path.basename(file_path),
                        "type": "THROTTLING",
                        "description": "CPU降频",
                        "line": line.strip()
                    })
        
        # 计算统计信息
        if freq_readings:
            avg_freq = sum(freq_readings) / len(freq_readings)
            max_freq = max(freq_readings)
            min_freq = min(freq_readings)
            
            results.append({
                "file": os.path.basename(file_path),
                "type": "CPUFREQ_STATS",
                "avg_frequency": avg_freq,
                "max_frequency": max_freq,
                "min_frequency": min_freq,
                "readings_count": len(freq_readings)
            })
        
    except Exception as e:
        print(f"⚠️  无法分析CPU频率文件 {file_path}: {str(e)}")
    
    return results

def analyze_microcode(file_path):
    """分析微码文件"""
    results = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            # 查找微码版本
            microcode_matches = re.findall(r'microcode\s*:\s*(0x[0-9a-f]+)', content, re.IGNORECASE)
            for microcode in microcode_matches:
                results.append({
                    "file": os.path.basename(file_path),
                    "type": "MICROCODE",
                    "version": microcode,
                    "description": f"微码版本: {microcode}"
                })
            
            # 查找微码错误
            error_matches = re.findall(r'error|fail|corrupt', content, re.IGNORECASE)
            if error_matches:
                results.append({
                    "file": os.path.basename(file_path),
                    "type": "MICROCODE_ERROR",
                    "error_count": len(error_matches),
                    "description": f"发现 {len(error_matches)} 个微码相关错误"
                })
        
    except Exception as e:
        print(f"⚠️  无法分析微码文件 {file_path}: {str(e)}")
    
    return results

def analyze_mce(file_path):
    """分析MCE文件"""
    results = []
    mce_count = 0
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
            for line_num, line in enumerate(lines, 1):
                line_lower = line.lower()
                
                if 'mce' in line_lower or 'machine check' in line_lower:
                    mce_count += 1
                    
                    # 提取CPU编号
                    cpu_match = re.search(r'CPU[:\s]*(\d+)', line, re.IGNORECASE)
                    cpu_num = cpu_match.group(1) if cpu_match else "未知"
                    
                    # 提取错误类型
                    error_type = "未知"
                    if 'corrected' in line_lower:
                        error_type = "可纠正"
                    elif 'uncorrected' in line_lower:
                        error_type = "不可纠正"
                    elif 'fatal' in line_lower:
                        error_type = "致命"
                    
                    results.append({
                        "file": os.path.basename(file_path),
                        "type": "MCE",
                        "line_num": line_num,
                        "cpu": cpu_num,
                        "error_type": error_type,
                        "line": line.strip()
                    })
        
        if mce_count > 0:
            results.append({
                "file": os.path.basename(file_path),
                "type": "MCE_SUMMARY",
                "total_mce": mce_count,
                "description": f"发现 {mce_count} 个机器检查异常"
            })
        
    except Exception as e:
        print(f"⚠️  无法分析MCE文件 {file_path}: {str(e)}")
    
    return results

def analyze_infocollect_logs(log_dir, keywords=None, date_filter=None, start_time=None, end_time=None):
    """分析InfoCollect日志目录"""
    print(f"🔍 开始InfoCollect日志分析: {log_dir}")
    print("=" * 60)
    
    # 查找InfoCollect文件
    infocollect_files = find_infocollect_files(log_dir)
    
    if not infocollect_files:
        print("❌ 未找到InfoCollect相关日志文件")
        return []
    
    print(f"找到 {len(infocollect_files)} 个InfoCollect相关文件")
    
    # 分类文件
    file_categories = defaultdict(list)
    for file_path in infocollect_files:
        file_type = classify_cpu_file(file_path)
        file_categories[file_type].append(file_path)
    
    # 输出文件分类
    print("📁 文件分类:")
    for file_type, files in sorted(file_categories.items()):
        print(f"  - {file_type}: {len(files)} 个文件")
    print("-" * 60)
    
    all_results = []
    
    # 分析CPU信息文件
    if file_categories["cpuinfo"]:
        print("📊 分析CPU信息文件:")
        for file_path in file_categories["cpuinfo"][:2]:  # 最多分析2个文件
            filename = os.path.basename(file_path)
            print(f"  - {filename}")
            results = analyze_cpuinfo(file_path)
            all_results.extend(results)
            
            if results:
                for result in results:
                    if result["type"] == "CPUINFO":
                        info = result["info"]
                        print(f"    处理器: {info['processors']} 个")
                        print(f"    插槽: {info['sockets']} 个")
                        print(f"    型号: {info['model']}")
                        print(f"    频率: {info['frequency']}")
                        print(f"    缓存: {info['cache_size']}")
                        print(f"    微码: {info['microcode']}")
    
    # 分析dmesg文件
    if file_categories["dmesg"]:
        print("\n📊 分析dmesg文件中的CPU错误:")
        total_errors = 0
        
        for file_path in file_categories["dmesg"][:3]:  # 最多分析3个文件
            filename = os.path.basename(file_path)
            results = analyze_dmesg(file_path, keywords)
            all_results.extend(results)
            
            if results:
                total_errors += len(results)
                print(f"  - {filename}: 找到 {len(results)} 条CPU错误")
                
                # 输出前3条错误
                for result in results[:3]:
                    if result["type"] == "DMESG_ERROR":
                        cpu_info = f"CPU {result['cpu']}" if result['cpu'] != "未知" else "CPU"
                        print(f"    第{result['line_num']}行: {cpu_info} - {result['description']}")
                        if result['timestamp']:
                            print(f"      时间: {result['timestamp']}")
        
        if total_errors == 0:
            print("  ✅ 未在dmesg中发现CPU错误")
    
    # 分析温度文件
    if file_categories["thermal"]:
        print("\n📊 分析温度文件:")
        high_temp_count = 0
        
        for file_path in file_categories["thermal"][:3]:  # 最多分析3个文件
            filename = os.path.basename(file_path)
            results = analyze_thermal(file_path)
            all_results.extend(results)
            
            if results:
                print(f"  - {filename}: 找到 {len(results)} 条温度记录")
                
                # 检查高温记录
                high_temps = [r for r in results if r["type"] == "THERMAL" and r["status"] in ["警告", "危险"]]
                if high_temps:
                    high_temp_count += len(high_temps)
                    for temp in high_temps[:3]:
                        print(f"    ⚠️  {temp['sensor']}: {temp['temperature']}{temp['unit']} ({temp['status']})")
                
                # 输出统计信息
                for result in results:
                    if result["type"] == "THERMAL_STATS":
                        print(f"    平均温度: {result['avg_temperature']:.1f}°C")
                        print(f"    最高温度: {result['max_temperature']:.1f}°C")
                        print(f"    最低温度: {result['min_temperature']:.1f}°C")
        
        if high_temp_count == 0:
            print("  ✅ 未发现CPU高温问题")
    
    # 分析CPU频率文件
    if file_categories["cpufreq"]:
        print("\n📊 分析CPU频率文件:")
        
        for file_path in file_categories["cpufreq"][:2]:  # 最多分析2个文件
            filename = os.path.basename(file_path)
            results = analyze_cpufreq(file_path)
            all_results.extend(results)
            
            if results:
                print(f"  - {filename}: 找到 {len(results)} 条频率记录")
                
                # 检查降频
                throttling = [r for r in results if r["type"] == "THROTTLING"]
                if throttling:
                    print(f"    ⚠️  发现CPU降频")
                
                # 输出统计信息
                for result in results:
                    if result["type"] == "CPUFREQ_STATS":
                        print(f"    平均频率: {result['avg_frequency']:.0f} MHz")
                        print(f"    最高频率: {result['max_frequency']:.0f} MHz")
                        print(f"    最低频率: {result['min_frequency']:.0f} MHz")
    
    # 分析微码文件
    if file_categories["microcode"]:
        print("\n📊 分析微码文件:")
        
        for file_path in file_categories["microcode"][:2]:  # 最多分析2个文件
            filename = os.path.basename(file_path)
            results = analyze_microcode(file_path)
            all_results.extend(results)
            
            if results:
                print(f"  - {filename}")
                
                for result in results:
                    if result["type"] == "MICROCODE":
                        print(f"    {result['description']}")
                    elif result["type"] == "MICROCODE_ERROR":
                        print(f"    ⚠️  {result['description']}")
    
    # 分析MCE文件
    if file_categories["mce"]:
        print("\n📊 分析MCE文件:")
        
        for file_path in file_categories["mce"][:2]:  # 最多分析2个文件
            filename = os.path.basename(file_path)
            results = analyze_mce(file_path)
            all_results.extend(results)
            
            if results:
                print(f"  - {filename}")
                
                for result in results:
                    if result["type"] == "MCE_SUMMARY":
                        print(f"    ⚠️  {result['description']}")
    
    print("-" * 60)
    
    # 汇总分析结果
    if all_results:
        print("📈 InfoCollect日志分析汇总:")
        
        # 统计各类结果
        result_types = defaultdict(int)
        for result in all_results:
            result_types[result["type"]] += 1
        
        for type_name, count in sorted(result_types.items()):
            if count > 0:
                print(f"  {type_name}: {count} 条记录")
        
        # 检查严重问题
        severe_issues = []
        
        # 检查高温问题
        high_temps = [r for r in all_results if r["type"] == "THERMAL" and r["status"] in ["警告", "危险"]]
        if high_temps:
            severe_issues.append(f"CPU高温: {len(high_temps)} 条记录")
        
        # 检查MCE错误
        mce_errors = [r for r in all_results if r["type"] == "MCE"]
        if mce_errors:
            severe_issues.append(f"机器检查异常: {len(mce_errors)} 条记录")
        
        # 检查dmesg错误
        dmesg_errors = [r for r in all_results if r["type"] == "DMESG_ERROR"]
        if dmesg_errors:
            severe_issues.append(f"内核CPU错误: {len(dmesg_errors)} 条记录")
        
        # 检查降频
        throttling = [r for r in all_results if r["type"] == "THROTTLING"]
        if throttling:
            severe_issues.append(f"CPU降频: {len(throttling)} 条记录")
        
        # 检查微码错误
        microcode_errors = [r for r in all_results if r["type"] == "MICROCODE_ERROR"]
        if microcode_errors:
            severe_issues.append(f"微码错误: {len(microcode_errors)} 条记录")
        
        if severe_issues:
            print(f"\n🚨 发现严重问题:")
            for issue in severe_issues:
                print(f"  - {issue}")
        else:
            print(f"\n✅ 未发现严重CPU问题")
    else:
        print("ℹ️  未在InfoCollect日志中发现有效记录")
    
    print("=" * 60)
    print("✅ InfoCollect日志分析完成")
    
    # 保存结果到文件以便报告生成
    save_results(all_results, log_dir)
    
    return all_results

def save_results(results, log_dir):
    """保存并合并分析结果到文件"""
    output_file = "/tmp/cpu_analysis_results.json"
    
    existing_data = {}
    if os.path.exists(output_file):
        try:
            with open(output_file, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
        except:
            pass
            
    temp_summary = existing_data.get('temperature_summary', {'high_temps': [], 'total_readings': 0})
    error_summary = existing_data.get('error_summary', {'critical_errors': [], 'total_errors': 0})
    freq_summary = existing_data.get('frequency_summary', {'throttling_count': 0, 'total_readings': 0})
    all_results_list = existing_data.get('all_results', [])
    
    cpu_info = existing_data.get('cpu_info', {})
    for r in results:
        if r["type"] == "CPUINFO":
            cpu_info = r["info"]
    
    # 从结果中汇总
    new_high_temps = [r for r in results if r["type"] == "THERMAL" and r.get("status") in ["警告", "危险"]]
    new_errors = [r for r in results if r["type"] in ["DMESG_ERROR", "MCE"] and r.get("severity", "ERROR") != "INFO"]
    new_throttling = len([r for r in results if r["type"] == "THROTTLING"])
    
    temp_summary['high_temps'].extend(new_high_temps)
    temp_summary['total_readings'] += len([r for r in results if r["type"] == "THERMAL"])
    error_summary['critical_errors'].extend(new_errors)
    error_summary['total_errors'] += len(new_errors)
    freq_summary['throttling_count'] += new_throttling
    freq_summary['total_readings'] += len([r for r in results if r["type"] == "CPUFREQ"])
    all_results_list.extend(results)
    
    results_summary = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "cpu_info": cpu_info,
        "temperature_summary": temp_summary,
        "error_summary": error_summary,
        "frequency_summary": freq_summary,
        "all_results": all_results_list
    }
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results_summary, f, ensure_ascii=False, indent=2)
    except:
        pass

def main():
    parser = argparse.ArgumentParser(description='CPU故障诊断 - InfoCollect日志分析')
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
    
    # 执行InfoCollect日志分析
    results = analyze_infocollect_logs(
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
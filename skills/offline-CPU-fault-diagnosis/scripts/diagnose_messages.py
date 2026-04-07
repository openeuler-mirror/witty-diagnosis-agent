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

# CPU相关的系统消息关键词
CPU_MESSAGE_KEYWORDS = [
    # 硬件错误
    ("CPU.*error", "CPU错误"),
    ("CPU.*fail", "CPU故障"),
    ("CPU.*fatal", "CPU致命错误"),
    ("CPU.*panic", "CPU恐慌"),
    
    # MCE错误
    ("MCE:.*CPU", "CPU机器检查异常"),
    ("machine check.*CPU", "CPU机器检查"),
    ("MCE.*logged", "记录机器检查异常"),
    ("MCE.*recovery", "机器检查恢复"),
    
    # 缓存错误
    ("cache error", "缓存错误"),
    ("CPU.*cache", "CPU缓存"),
    ("ECC error", "ECC错误"),
    ("corrected error", "可纠正错误"),
    ("uncorrected error", "不可纠正错误"),
    
    # 温度相关
    ("CPU.*temperature", "CPU温度"),
    ("CPU.*over temperature", "CPU过热"),
    ("CPU.*thermal", "CPU热管理"),
    ("CPU.*throttling", "CPU降频"),
    ("thermal.*throttle", "热管理降频"),
    ("CPU.*hot", "CPU过热"),
    
    # 微码相关
    ("microcode.*error", "微码错误"),
    ("CPU.*microcode", "CPU微码"),
    ("microcode.*update", "微码更新"),
    ("ucode.*error", "微码错误"),
    
    # 频率相关
    ("CPU.*frequency", "CPU频率"),
    ("cpufreq", "CPU频率调节"),
    ("frequency.*limit", "频率限制"),
    ("CPU.*slow", "CPU速度慢"),
    
    # 电源管理
    ("CPU.*power", "CPU电源"),
    ("CPU.*C-state", "CPU C状态"),
    ("CPU.*P-state", "CPU P状态"),
    ("CPU.*idle", "CPU空闲"),
    
    # 互连错误
    ("QPI.*error", "QPI总线错误"),
    ("UPI.*error", "UPI总线错误"),
    ("interconnect.*error", "互连错误"),
    ("bus error.*CPU", "CPU总线错误"),
    
    # 电压相关
    ("CPU.*voltage", "CPU电压"),
    ("VRM.*error", "电压调节模块错误"),
    ("CPU.*Vcore", "CPU核心电压"),
    
    # 其他
    ("CPU.*stall", "CPU停滞"),
    ("CPU.*hang", "CPU挂起"),
    ("CPU.*dead", "CPU死亡"),
    ("CPU.*offline", "CPU离线"),
]

def find_message_files(root_dir):
    """查找系统消息文件"""
    message_files = []
    
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            file_lower = file.lower()
            # 检查是否是系统消息文件
            if any(pattern in file_lower for pattern in ['messages', 'syslog', 'journal', 'kern.log', 'dmesg']):
                message_files.append(os.path.join(root, file))
            # 检查是否在messages目录下
            elif 'messages' in root.lower():
                message_files.append(os.path.join(root, file))
    
    return message_files

def parse_timestamp(line):
    """解析时间戳"""
    for pattern, fmt_name in TIME_PATTERNS:
        match = re.search(pattern[0], line)
        if match:
            ts_str = match.group(1)
            fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
            for fmt in fmts:
                try:
                    dt = datetime.strptime(ts_str, fmt)
                    if fmt == "%b %d %H:%M:%S": 
                        dt = dt.replace(year=datetime.now().year)
                    return dt, ts_str
                except:
                    continue
    return None, None

def is_in_time_range(line, start_dt, end_dt, date_filter):
    """检查是否在时间范围内"""
    if date_filter:
        if date_filter in line:
            return True
        if not start_dt and not end_dt:
            return False
    
    line_dt, _ = parse_timestamp(line)
    if not line_dt:
        return True  # 没有时间戳的行不过滤
    
    if start_dt and line_dt < start_dt:
        return False
    if end_dt and line_dt > end_dt:
        return False
    
    return True

def analyze_messages_file(file_path, keywords=None, date_filter=None, start_dt=None, end_dt=None):
    """分析系统消息文件"""
    results = []
    error_counts = defaultdict(int)
    
    if keywords is None:
        keywords = CPU_MESSAGE_KEYWORDS
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
            for line_num, line in enumerate(lines, 1):
                # 检查时间过滤
                if not is_in_time_range(line, start_dt, end_dt, date_filter):
                    continue
                
                line_lower = line.lower()
                
                # 检查每个关键词
                for pattern, description in keywords:
                    if re.search(pattern, line_lower, re.IGNORECASE):
                        # 解析时间戳
                        timestamp_dt, timestamp_str = parse_timestamp(line)
                        
                        # 提取CPU编号（如果存在）
                        cpu_match = re.search(r'CPU[:\s]*(\d+)', line, re.IGNORECASE)
                        cpu_num = cpu_match.group(1) if cpu_match else "未知"
                        
                        # 提取错误严重程度
                        severity = "INFO"
                        if any(keyword in line_lower for keyword in ['error', 'fail', 'fatal', 'panic']):
                            severity = "ERROR"
                        elif any(keyword in line_lower for keyword in ['warning', 'warn']):
                            severity = "WARNING"
                        elif any(keyword in line_lower for keyword in ['critical', 'emerg']):
                            severity = "CRITICAL"
                        
                        results.append({
                            "file": os.path.basename(file_path),
                            "type": "MESSAGE",
                            "line_num": line_num,
                            "timestamp": timestamp_str,
                            "timestamp_dt": timestamp_dt,
                            "cpu": cpu_num,
                            "severity": severity,
                            "pattern": pattern,
                            "description": description,
                            "line": line.strip()
                        })
                        
                        error_counts[description] += 1
                        break  # 每行只匹配一个关键词
    except Exception as e:
        print(f"⚠️  无法分析消息文件 {file_path}: {str(e)}")
    
    return results, error_counts

def analyze_messages_logs(log_dir, keywords=None, date_filter=None, start_time=None, end_time=None):
    """分析系统消息日志目录"""
    print(f"🔍 开始系统消息日志分析: {log_dir}")
    print("=" * 60)
    
    # 解析时间参数
    start_dt = None
    end_dt = None
    
    if start_time:
        try:
            start_dt = datetime.strptime(start_time, "%Y-%m-%d %H:%M:%S")
        except:
            print(f"❌ 错误: 开始时间格式不正确: {start_time}")
            sys.exit(1)
    
    if end_time:
        try:
            end_dt = datetime.strptime(end_time, "%Y-%m-%d %H:%M:%S")
        except:
            print(f"❌ 错误: 结束时间格式不正确: {end_time}")
            sys.exit(1)
    
    # 查找系统消息文件
    message_files = find_message_files(log_dir)
    
    if not message_files:
        print("❌ 未找到系统消息日志文件")
        return []
    
    print(f"找到 {len(message_files)} 个系统消息文件")
    print("-" * 60)
    
    all_results = []
    total_error_counts = defaultdict(int)
    
    # 分析每个文件
    for file_path in message_files[:5]:  # 最多分析5个文件
        filename = os.path.basename(file_path)
        print(f"📊 分析文件: {filename}")
        
        results, error_counts = analyze_messages_file(
            file_path, 
            keywords, 
            date_filter, 
            start_dt, 
            end_dt
        )
        
        all_results.extend(results)
        
        # 累加错误计数
        for desc, count in error_counts.items():
            total_error_counts[desc] += count
        
        if results:
            print(f"  找到 {len(results)} 条CPU相关消息")
            
            # 按严重程度统计
            severity_counts = defaultdict(int)
            for result in results:
                severity_counts[result["severity"]] += 1
            
            for severity, count in sorted(severity_counts.items()):
                severity_icon = "ℹ️ "
                if severity == "ERROR":
                    severity_icon = "❌"
                elif severity == "WARNING":
                    severity_icon = "⚠️ "
                elif severity == "CRITICAL":
                    severity_icon = "🚨"
                
                print(f"  {severity_icon} {severity}: {count} 条")
            
            # 输出前3条重要消息
            important_results = [r for r in results if r["severity"] in ["ERROR", "CRITICAL"]]
            if important_results:
                print(f"  重要消息 (前3条):")
                for result in important_results[:3]:
                    timestamp = result["timestamp"] if result["timestamp"] else "无时间戳"
                    cpu_info = f"CPU {result['cpu']}" if result['cpu'] != "未知" else "CPU"
                    print(f"    第{result['line_num']}行: [{timestamp}] {cpu_info} - {result['description']}")
            else:
                # 如果没有重要消息，输出前3条警告消息
                warning_results = [r for r in results if r["severity"] == "WARNING"]
                if warning_results:
                    print(f"  警告消息 (前3条):")
                    for result in warning_results[:3]:
                        timestamp = result["timestamp"] if result["timestamp"] else "无时间戳"
                        cpu_info = f"CPU {result['cpu']}" if result['cpu'] != "未知" else "CPU"
                        print(f"    第{result['line_num']}行: [{timestamp}] {cpu_info} - {result['description']}")
        else:
            print(f"  ✅ 未发现CPU相关消息")
        
        print()
    
    print("-" * 60)
    
    # 汇总分析结果
    if all_results:
        print("📈 系统消息日志分析汇总:")
        
        # 按错误类型统计
        if total_error_counts:
            print(f"\n🔍 错误类型统计 (前10名):")
            sorted_errors = sorted(total_error_counts.items(), key=lambda x: x[1], reverse=True)[:10]
            for desc, count in sorted_errors:
                print(f"  {desc:<30} {count:>4} 次")
        
        # 按时间分布统计
        time_distribution = defaultdict(int)
        for result in all_results:
            if result["timestamp_dt"]:
                hour = result["timestamp_dt"].hour
                time_key = f"{hour:02d}:00-{hour:02d}:59"
                time_distribution[time_key] += 1
        
        if time_distribution:
            print(f"\n⏰ 时间分布统计:")
            sorted_times = sorted(time_distribution.items(), key=lambda x: x[1], reverse=True)[:8]
            for time_key, count in sorted_times:
                print(f"  {time_key}: {count:>4} 条")
        
        # 按CPU编号统计
        cpu_distribution = defaultdict(int)
        for result in all_results:
            if result["cpu"] != "未知":
                cpu_distribution[result["cpu"]] += 1
        
        if cpu_distribution:
            print(f"\n💻 CPU分布统计:")
            sorted_cpus = sorted(cpu_distribution.items(), key=lambda x: int(x[0]) if x[0].isdigit() else 999)
            for cpu_num, count in sorted_cpus[:10]:  # 最多显示10个CPU
                print(f"  CPU {cpu_num}: {count:>4} 条")
        
        # 检查严重问题
        severe_issues = []
        
        # 检查致命错误
        fatal_errors = [r for r in all_results if r["severity"] == "CRITICAL"]
        if fatal_errors:
            severe_issues.append(f"致命错误: {len(fatal_errors)} 条")
        
        # 检查错误
        errors = [r for r in all_results if r["severity"] == "ERROR"]
        if errors:
            severe_issues.append(f"错误: {len(errors)} 条")
        
        # 检查警告
        warnings = [r for r in all_results if r["severity"] == "WARNING"]
        if warnings:
            severe_issues.append(f"警告: {len(warnings)} 条")
        
        # 检查特定问题类型
        problem_types = {
            "CPU过热": ["CPU.*over temperature", "CPU.*hot", "thermal.*shutdown"],
            "CPU降频": ["CPU.*throttling", "thermal.*throttle"],
            "机器检查异常": ["MCE:.*CPU", "machine check.*CPU"],
            "缓存错误": ["cache error", "ECC error"],
            "微码错误": ["microcode.*error", "ucode.*error"],
            "总线错误": ["QPI.*error", "UPI.*error", "bus error.*CPU"],
            "电压错误": ["CPU.*voltage", "VRM.*error"],
        }
        
        for problem_name, patterns in problem_types.items():
            problem_count = 0
            for result in all_results:
                for pattern in patterns:
                    if re.search(pattern, result["line"], re.IGNORECASE):
                        problem_count += 1
                        break
            
            if problem_count > 0:
                severe_issues.append(f"{problem_name}: {problem_count} 条")
        
        if severe_issues:
            print(f"\n🚨 发现严重问题:")
            for issue in severe_issues:
                print(f"  - {issue}")
            
            # 输出时间线分析
            print(f"\n📅 问题时间线 (最近10条严重问题):")
            severe_results = [r for r in all_results if r["severity"] in ["CRITICAL", "ERROR", "WARNING"]]
            severe_results.sort(key=lambda x: x["timestamp_dt"] if x["timestamp_dt"] else datetime.min, reverse=True)
            
            for result in severe_results[:10]:
                timestamp = result["timestamp"] if result["timestamp"] else "无时间戳"
                cpu_info = f"CPU {result['cpu']}" if result['cpu'] != "未知" else "CPU"
                severity_icon = "ℹ️ "
                if result["severity"] == "ERROR":
                    severity_icon = "❌"
                elif result["severity"] == "WARNING":
                    severity_icon = "⚠️ "
                elif result["severity"] == "CRITICAL":
                    severity_icon = "🚨"
                
                # 截断过长的描述
                description = result["description"]
                if len(description) > 40:
                    description = description[:37] + "..."
                
                print(f"  {severity_icon} [{timestamp}] {cpu_info}: {description}")
        else:
            print(f"\n✅ 未发现严重CPU问题")
        
        # 输出建议
        print(f"\n💡 分析建议:")
        
        if any("CPU过热" in issue for issue in severe_issues):
            print("  - 检查CPU散热器、风扇和机箱风道")
            print("  - 检查环境温度是否过高")
            print("  - 考虑降低CPU负载或优化应用")
        
        if any("CPU降频" in issue for issue in severe_issues):
            print("  - 检查电源管理和温度设置")
            print("  - 确认BIOS中的CPU频率设置")
            print("  - 检查是否有过热导致降频")
        
        if any("机器检查异常" in issue for issue in severe_issues):
            print("  - 检查CPU硬件是否损坏")
            print("  - 更新BIOS和微码")
            print("  - 检查内存和主板稳定性")
        
        if any("缓存错误" in issue for issue in severe_issues):
            print("  - 检查CPU缓存是否损坏")
            print("  - 更新微码可能修复某些缓存错误")
            print("  - 考虑更换CPU")
        
        if any("微码错误" in issue for issue in severe_issues):
            print("  - 更新CPU微码到最新版本")
            print("  - 检查微码与CPU型号是否匹配")
            print("  - 查看厂商是否有已知的微码问题")
        
        if any("总线错误" in issue for issue in severe_issues):
            print("  - 检查CPU插座和主板连接")
            print("  - 检查QPI/UPI总线物理连接")
            print("  - 考虑主板或CPU硬件问题")
        
        if any("电压错误" in issue for issue in severe_issues):
            print("  - 检查VRM模块和主板供电")
            print("  - 检查电源供应是否稳定")
            print("  - 检查BIOS中的CPU电压设置")
    else:
        print("ℹ️  未在系统消息日志中发现CPU相关消息")
        print("💡 建议:")
        print("  - 检查日志文件是否包含CPU相关信息")
        print("  - 尝试不同的关键词进行搜索")
        print("  - 检查时间范围设置是否正确")
    
    print("=" * 60)
    print("✅ 系统消息日志分析完成")
    
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
    
    # 从结果中汇总
    new_errors = [r for r in results if r["severity"] in ["ERROR", "CRITICAL", "WARNING"]]
    new_throttling = len([r for r in results if "THROTTLING" in r.get("description", "").upper()])
    
    error_summary['critical_errors'].extend(new_errors)
    error_summary['total_errors'] += len(results)
    freq_summary['throttling_count'] += new_throttling
    all_results_list.extend(results)
    
    results_summary = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log_dir": log_dir,
        "cpu_info": existing_data.get('cpu_info', {}),
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
    parser = argparse.ArgumentParser(description='CPU故障诊断 - 系统消息日志分析')
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
    
    # 执行系统消息日志分析
    results = analyze_messages_logs(
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
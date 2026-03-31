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

class CPUAnalyzer:
    def __init__(self, log_dir):
        self.log_dir = log_dir
        self.results = []
        self.cpu_info = {}
        self.temperature_data = []
        self.error_data = []
        self.frequency_data = []
        
    def find_cpu_files(self):
        """查找所有CPU相关文件"""
        cpu_files = []
        
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                file_lower = file.lower()
                # 检查CPU相关文件
                if any(pattern in file_lower for pattern in [
                    'cpu', 'processor', 'thermal', 'temperature', 
                    'cpufreq', 'frequency', 'microcode', 'mce',
                    'sel', 'ibmc', 'dmesg', 'messages', 'syslog'
                ]):
                    cpu_files.append(os.path.join(root, file))
        
        return cpu_files
    
    def analyze_cpu_info(self):
        """分析CPU基本信息"""
        print("🔍 分析CPU基本信息...")
        
        cpu_info_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                file_lower = file.lower()
                if any(pattern in file_lower for pattern in ['cpuinfo', 'cpu_info', 'proc/cpuinfo']):
                    cpu_info_files.append(os.path.join(root, file))
        
        if not cpu_info_files:
            print("  ⚠️  未找到CPU信息文件")
            return
        
        for file_path in cpu_info_files[:2]:  # 最多分析2个文件
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    
                    # 统计处理器数量
                    processor_matches = re.findall(r'processor\s*:\s*\d+', content, re.IGNORECASE)
                    processor_count = len(processor_matches)
                    
                    # 提取CPU型号
                    model_match = re.search(r'model name\s*:\s*(.+)', content, re.IGNORECASE)
                    model = model_match.group(1).strip() if model_match else "未知"
                    
                    # 提取CPU频率
                    freq_match = re.search(r'cpu mhz\s*:\s*(\d+\.?\d*)', content, re.IGNORECASE)
                    frequency = float(freq_match.group(1)) if freq_match else 0
                    
                    # 提取缓存大小
                    cache_matches = re.findall(r'cache size\s*:\s*(\d+)\s*KB', content, re.IGNORECASE)
                    total_cache = sum(int(size) for size in cache_matches) if cache_matches else 0
                    
                    # 提取微码版本
                    microcode_match = re.search(r'microcode\s*:\s*(0x[0-9a-f]+)', content, re.IGNORECASE)
                    microcode = microcode_match.group(1).strip() if microcode_match else "未知"
                    
                    # 提取核心和插槽信息
                    core_match = re.search(r'cpu cores\s*:\s*(\d+)', content, re.IGNORECASE)
                    cores_per_socket = int(core_match.group(1)) if core_match else 0
                    
                    sockets = 0
                    if processor_count > 0 and cores_per_socket > 0:
                        sockets = processor_count // cores_per_socket
                    
                    self.cpu_info = {
                        "processors": processor_count,
                        "sockets": sockets,
                        "cores_per_socket": cores_per_socket,
                        "model": model,
                        "frequency_mhz": frequency,
                        "cache_size_kb": total_cache,
                        "microcode": microcode,
                        "source_file": os.path.basename(file_path)
                    }
                    
                    print(f"  ✅ CPU信息分析完成:")
                    print(f"    处理器: {processor_count} 个")
                    print(f"    插槽: {sockets} 个")
                    print(f"    型号: {model}")
                    print(f"    频率: {frequency:.2f} MHz")
                    print(f"    缓存: {total_cache} KB")
                    print(f"    微码: {microcode}")
                    
                    self.results.append({
                        "type": "CPU_INFO",
                        "data": self.cpu_info
                    })
                    
                    break  # 只分析第一个有效的CPU信息文件
                    
            except Exception as e:
                print(f"  ⚠️  无法分析CPU信息文件 {file_path}: {str(e)}")
    
    def analyze_temperature(self):
        """分析CPU温度"""
        print("\n🌡️ 分析CPU温度...")
        
        temp_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                file_lower = file.lower()
                if any(pattern in file_lower for pattern in ['thermal', 'temperature', 'sensor', 'cpu', 'temp']):
                    temp_files.append(os.path.join(root, file))
        
        if not temp_files:
            print("  ⚠️  未找到温度文件")
            return
        
        high_temp_count = 0
        critical_temp_count = 0
        
        for file_path in temp_files[:5]:  # 最多分析5个文件
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
                                
                                # 确定温度状态
                                status = "正常"
                                if temp > 80:
                                    status = "注意"
                                if temp > 90:
                                    status = "警告"
                                    high_temp_count += 1
                                if temp > 100:
                                    status = "危险"
                                    critical_temp_count += 1
                                
                                # 提取传感器名称
                                sensor_name = "未知"
                                name_match = re.search(r'([a-zA-Z0-9_]+)\s*:', line)
                                if name_match:
                                    sensor_name = name_match.group(1)
                                
                                # 提取时间戳
                                timestamp = None
                                for tp, fmt_name in TIME_PATTERNS:
                                    pattern_str = tp if isinstance(tp, str) else tp[0]
                                    match = re.search(pattern_str, line)
                                    if match:
                                        timestamp = match.group(1)
                                        break
                                
                                temp_data = {
                                    "sensor": sensor_name,
                                    "temperature": temp,
                                    "unit": "°C",
                                    "status": status,
                                    "timestamp": timestamp,
                                    "source_file": os.path.basename(file_path),
                                    "line": line.strip()
                                }
                                
                                self.temperature_data.append(temp_data)
                                
                                if status in ["警告", "危险"]:
                                    print(f"  ⚠️  {sensor_name}: {temp}°C ({status})")
            
            except Exception as e:
                print(f"  ⚠️  无法分析温度文件 {file_path}: {str(e)}")
        
        # 温度统计
        if self.temperature_data:
            temps = [t["temperature"] for t in self.temperature_data]
            avg_temp = sum(temps) / len(temps)
            max_temp = max(temps)
            min_temp = min(temps)
            
            print(f"  📊 温度统计:")
            print(f"    平均温度: {avg_temp:.1f}°C")
            print(f"    最高温度: {max_temp:.1f}°C")
            print(f"    最低温度: {min_temp:.1f}°C")
            print(f"    高温警告: {high_temp_count} 次")
            print(f"    危险温度: {critical_temp_count} 次")
            
            self.results.append({
                "type": "TEMPERATURE_STATS",
                "avg_temperature": avg_temp,
                "max_temperature": max_temp,
                "min_temperature": min_temp,
                "high_temp_count": high_temp_count,
                "critical_temp_count": critical_temp_count,
                "total_readings": len(self.temperature_data)
            })
        else:
            print("  ✅ 未发现温度数据")
    
    def analyze_errors(self):
        """分析CPU错误"""
        print("\n🚨 分析CPU错误...")
        
        # 错误关键词
        error_patterns = [
            (r'CPU.*error', "CPU错误"),
            (r'CPU.*fail', "CPU故障"),
            (r'CPU.*fatal', "CPU致命错误"),
            (r'MCE:.*CPU', "CPU机器检查异常"),
            (r'machine check.*CPU', "CPU机器检查"),
            (r'cache error', "缓存错误"),
            (r'ECC error', "ECC错误"),
            (r'CPU.*over temperature', "CPU过热"),
            (r'CPU.*thermal', "CPU热管理错误"),
            (r'CPU.*throttling', "CPU降频"),
            (r'microcode.*error', "微码错误"),
            (r'QPI.*error', "QPI总线错误"),
            (r'UPI.*error', "UPI总线错误"),
            (r'CPU.*voltage', "CPU电压错误"),
            (r'VRM.*error', "电压调节模块错误"),
        ]
        
        error_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                file_lower = file.lower()
                if any(pattern in file_lower for pattern in ['messages', 'syslog', 'dmesg', 'journal', 'sel', 'ibmc']):
                    error_files.append(os.path.join(root, file))
        
        if not error_files:
            print("  ⚠️  未找到错误日志文件")
            return
        
        error_counts = defaultdict(int)
        
        for file_path in error_files[:10]:  # 最多分析10个文件
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                    
                    for line_num, line in enumerate(lines, 1):
                        line_lower = line.lower()
                        
                        for pattern, description in error_patterns:
                            if re.search(pattern, line_lower, re.IGNORECASE):
                                # 提取时间戳
                                timestamp = None
                                for time_pattern, fmt_name in TIME_PATTERNS:
                                    match = re.search(time_pattern[0], line)
                                    if match:
                                        timestamp = match.group(1)
                                        break
                                
                                # 提取CPU编号
                                cpu_match = re.search(r'CPU[:\s]*(\d+)', line, re.IGNORECASE)
                                cpu_num = cpu_match.group(1) if cpu_match else "未知"
                                
                                # 确定错误严重程度
                                severity = "INFO"
                                if any(keyword in line_lower for keyword in ['error', 'fail', 'fatal', 'panic']):
                                    severity = "ERROR"
                                elif any(keyword in line_lower for keyword in ['warning', 'warn']):
                                    severity = "WARNING"
                                elif any(keyword in line_lower for keyword in ['critical', 'emerg']):
                                    severity = "CRITICAL"
                                
                                error_data = {
                                    "description": description,
                                    "severity": severity,
                                    "cpu": cpu_num,
                                    "timestamp": timestamp,
                                    "line_num": line_num,
                                    "source_file": os.path.basename(file_path),
                                    "line": line.strip()
                                }
                                
                                self.error_data.append(error_data)
                                error_counts[description] += 1
                                
                                if severity in ["ERROR", "CRITICAL"]:
                                    print(f"  ❌ 第{line_num}行: {description} (CPU {cpu_num})")
                                
                                break  # 每行只匹配一个错误
                
            except Exception as e:
                print(f"  ⚠️  无法分析错误文件 {file_path}: {str(e)}")
        
        # 错误统计
        if self.error_data:
            print(f"  📊 错误统计:")
            
            # 按严重程度统计
            severity_counts = defaultdict(int)
            for error in self.error_data:
                severity_counts[error["severity"]] += 1
            
            for severity, count in sorted(severity_counts.items()):
                severity_icon = "ℹ️ "
                if severity == "ERROR":
                    severity_icon = "❌"
                elif severity == "WARNING":
                    severity_icon = "⚠️ "
                elif severity == "CRITICAL":
                    severity_icon = "🚨"
                
                print(f"    {severity_icon} {severity}: {count} 条")
            
            # 按错误类型统计
            if error_counts:
                print(f"  🔍 错误类型统计 (前10名):")
                sorted_errors = sorted(error_counts.items(), key=lambda x: x[1], reverse=True)[:10]
                for desc, count in sorted_errors:
                    print(f"    {desc:<25} {count:>4} 次")
            
            self.results.append({
                "type": "ERROR_STATS",
                "total_errors": len(self.error_data),
                "severity_counts": dict(severity_counts),
                "error_type_counts": dict(error_counts)
            })
        else:
            print("  ✅ 未发现CPU错误")
    
    def analyze_frequency(self):
        """分析CPU频率"""
        print("\n⚡ 分析CPU频率...")
        
        freq_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                file_lower = file.lower()
                if any(pattern in file_lower for pattern in ['cpufreq', 'frequency', 'turbostat', 'cpu.*freq']):
                    freq_files.append(os.path.join(root, file))
        
        if not freq_files:
            print("  ⚠️  未找到频率文件")
            return
        
        throttling_count = 0
        
        for file_path in freq_files[:3]:  # 最多分析3个文件
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
                                
                                freq_data = {
                                    "frequency": freq,
                                    "unit": "MHz",
                                    "source_file": os.path.basename(file_path),
                                    "line": line.strip()
                                }
                                
                                self.frequency_data.append(freq_data)
                        
                        # 查找降频信息
                        elif 'throttling' in line_lower or 'throttle' in line_lower:
                            throttling_count += 1
                            print(f"  ⚠️  发现CPU降频: {line.strip()}")
                
            except Exception as e:
                print(f"  ⚠️  无法分析频率文件 {file_path}: {str(e)}")
        
        # 频率统计
        if self.frequency_data:
            freqs = [f["frequency"] for f in self.frequency_data]
            avg_freq = sum(freqs) / len(freqs)
            max_freq = max(freqs)
            min_freq = min(freqs)
            
            print(f"  📊 频率统计:")
            print(f"    平均频率: {avg_freq:.0f} MHz")
            print(f"    最高频率: {max_freq:.0f} MHz")
            print(f"    最低频率: {min_freq:.0f} MHz")
            print(f"    降频次数: {throttling_count} 次")
            
            # 检查频率是否异常低
            if avg_freq < 1000:  # 低于1GHz可能有问题
                print(f"  ⚠️  平均频率异常低 ({avg_freq:.0f} MHz)")
            
            self.results.append({
                "type": "FREQUENCY_STATS",
                "avg_frequency": avg_freq,
                "max_frequency": max_freq,
                "min_frequency": min_freq,
                "throttling_count": throttling_count,
                "total_readings": len(self.frequency_data)
            })
        else:
            print("  ✅ 未发现频率数据")
    
    def analyze_hardware(self):
        """分析CPU硬件问题"""
        print("\n🔧 分析CPU硬件问题...")
        
        hardware_issues = []
        
        # 检查MCE错误
        mce_errors = [e for e in self.error_data if "机器检查" in e["description"]]
        if mce_errors:
            hardware_issues.append(f"机器检查异常: {len(mce_errors)} 条")
            print(f"  ⚠️  发现机器检查异常: {len(mce_errors)} 条")
        
        # 检查缓存错误
        cache_errors = [e for e in self.error_data if "缓存" in e["description"] or "ECC" in e["description"]]
        if cache_errors:
            hardware_issues.append(f"缓存错误: {len(cache_errors)} 条")
            print(f"  ⚠️  发现缓存错误: {len(cache_errors)} 条")
        
        # 检查总线错误
        bus_errors = [e for e in self.error_data if "总线" in e["description"] or "QPI" in e["description"] or "UPI" in e["description"]]
        if bus_errors:
            hardware_issues.append(f"总线错误: {len(bus_errors)} 条")
            print(f"  ⚠️  发现总线错误: {len(bus_errors)} 条")
        
        # 检查电压错误
        voltage_errors = [e for e in self.error_data if "电压" in e["description"] or "VRM" in e["description"]]
        if voltage_errors:
            hardware_issues.append(f"电压错误: {len(voltage_errors)} 条")
            print(f"  ⚠️  发现电压错误: {len(voltage_errors)} 条")
        
        if hardware_issues:
            self.results.append({
                "type": "HARDWARE_ISSUES",
                "issues": hardware_issues,
                "mce_count": len(mce_errors),
                "cache_error_count": len(cache_errors),
                "bus_error_count": len(bus_errors),
                "voltage_error_count": len(voltage_errors)
            })
        else:
            print("  ✅ 未发现硬件问题")
    
    def generate_summary(self):
        """生成分析摘要"""
        print("\n" + "=" * 60)
        print("📋 CPU故障诊断摘要")
        print("=" * 60)
        
        # CPU基本信息
        if self.cpu_info:
            print("💻 CPU基本信息:")
            print(f"  型号: {self.cpu_info['model']}")
            print(f"  处理器: {self.cpu_info['processors']} 个")
            print(f"  插槽: {self.cpu_info['sockets']} 个")
            print(f"  频率: {self.cpu_info['frequency_mhz']:.2f} MHz")
            print(f"  缓存: {self.cpu_info['cache_size_kb']} KB")
            print(f"  微码: {self.cpu_info['microcode']}")
        
        # 温度问题
        high_temps = [t for t in self.temperature_data if t["status"] in ["警告", "危险"]]
        if high_temps:
            print(f"\n🌡️  CPU温度问题:")
            for temp in high_temps[:5]:  # 最多显示5个高温记录
                print(f"  ⚠️  {temp['sensor']}: {temp['temperature']}°C ({temp['status']})")
        
        # 错误问题
        critical_errors = [e for e in self.error_data if e["severity"] in ["ERROR", "CRITICAL"]]
        if critical_errors:
            print(f"\n🚨 CPU错误问题:")
            for error in critical_errors[:5]:  # 最多显示5个严重错误
                cpu_info = f"CPU {error['cpu']}" if error['cpu'] != "未知" else "CPU"
                print(f"  ❌ {cpu_info}: {error['description']}")
        
        # 频率问题
        if hasattr(self, 'frequency_data') and self.frequency_data:
            freqs = [f["frequency"] for f in self.frequency_data]
            avg_freq = sum(freqs) / len(freqs)
            
            if avg_freq < 1000:  # 低于1GHz
                print(f"\n⚡ CPU频率问题:")
                print(f"  ⚠️  平均频率异常低: {avg_freq:.0f} MHz")
        
        # 硬件问题
        hardware_issues = []
        for result in self.results:
            if result["type"] == "HARDWARE_ISSUES":
                hardware_issues = result.get("issues", [])
                break
        
        if hardware_issues:
            print(f"\n🔧 CPU硬件问题:")
            for issue in hardware_issues:
                print(f"  ⚠️  {issue}")
        
        # 总体评估
        print("\n📈 总体评估:")
        
        issue_count = 0
        
        # 检查高温问题
        if high_temps:
            issue_count += 1
            print(f"  ❌ 存在CPU高温问题")
        
        # 检查严重错误
        if critical_errors:
            issue_count += 1
            print(f"  ❌ 存在CPU严重错误")
        
        # 检查频率问题
        if hasattr(self, 'frequency_data') and self.frequency_data:
            freqs = [f["frequency"] for f in self.frequency_data]
            avg_freq = sum(freqs) / len(freqs)
            if avg_freq < 1000:
                issue_count += 1
                print(f"  ❌ 存在CPU频率问题")
        
        # 检查硬件问题
        if hardware_issues:
            issue_count += 1
            print(f"  ❌ 存在CPU硬件问题")
        
        if issue_count == 0:
            print(f"  ✅ CPU状态正常")
        elif issue_count == 1:
            print(f"  ⚠️  CPU存在1个问题")
        else:
            print(f"  🚨 CPU存在{issue_count}个问题")
        
        print("=" * 60)
        
        # 保存结果到文件
        self.save_results()
    
    def save_results(self):
        """保存分析结果到文件"""
        output_file = "/tmp/cpu_analysis_results.json"
        
        try:
            # 尝试加载现有结果以便合并
            existing_data = {}
            if os.path.exists(output_file):
                try:
                    with open(output_file, 'r', encoding='utf-8') as f:
                        existing_data = json.load(f)
                except:
                    pass

            # 合并逻辑
            temp_summary = existing_data.get('temperature_summary', {'high_temps': [], 'total_readings': 0})
            error_summary = existing_data.get('error_summary', {'critical_errors': [], 'total_errors': 0})
            freq_summary = existing_data.get('frequency_summary', {'throttling_count': 0, 'total_readings': 0})
            all_results_list = existing_data.get('all_results', [])
            
            # 添加本次结果
            new_high_temps = [t for t in self.temperature_data if t["status"] in ["警告", "危险"]]
            new_errors = [e for e in self.error_data if e["severity"] in ["ERROR", "CRITICAL"]]
            new_throttling = next((r["throttling_count"] for r in self.results if r["type"] == "FREQUENCY_STATS"), 0)
            
            temp_summary['high_temps'].extend(new_high_temps)
            temp_summary['total_readings'] += len(self.temperature_data)
            error_summary['critical_errors'].extend(new_errors)
            error_summary['total_errors'] += len(self.error_data)
            freq_summary['throttling_count'] += new_throttling
            freq_summary['total_readings'] += len(self.frequency_data)
            all_results_list.extend(self.results)

            results_summary = {
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "log_dir": self.log_dir,
                "cpu_info": self.cpu_info if self.cpu_info else existing_data.get('cpu_info', {}),
                "temperature_summary": temp_summary,
                "error_summary": error_summary,
                "frequency_summary": freq_summary,
                "all_results": all_results_list
            }
            
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(results_summary, f, ensure_ascii=False, indent=2)
            
            print(f"💾 分析结果已保存到: {output_file}")
            
        except Exception as e:
            print(f"⚠️  无法保存分析结果: {str(e)}")
    
    def run_analysis(self, analysis_type=None):
        """运行分析"""
        print(f"🔍 开始CPU故障诊断分析: {self.log_dir}")
        print("=" * 60)
        
        # 基础信息总是分析
        self.analyze_cpu_info()
        
        # 确定需要运行哪些分析
        do_temperature = analysis_type in ["temperature", None]
        do_errors = analysis_type in ["errors", "hardware", "microcode", "cache", "interconnect", "voltage", None]
        do_frequency = analysis_type in ["frequency", None]
        do_hardware = analysis_type in ["hardware", "cache", "interconnect", "voltage", None]
        
        if do_temperature:
            self.analyze_temperature()
        
        if do_errors:
            self.analyze_errors()
        
        if do_frequency:
            self.analyze_frequency()
        
        if do_hardware:
            self.analyze_hardware()
        
        # 将分析场景保存到conf文件，供报告生成脚本使用
        if analysis_type:
            try:
                scene_file = "/tmp/cpu_diagnosis_scene.conf"
                scenario_mapping = {
                    "hardware": "CPU_HARDWARE_FAILURE",
                    "temperature": "CPU_OVERHEATING",
                    "errors": "CPU_GENERAL_ERRORS",
                    "frequency": "CPU_FREQUENCY_THROTTLING",
                    "microcode": "CPU_MICROCODE_ERROR",
                    "cache": "CPU_CACHE_ERROR",
                    "interconnect": "CPU_INTERCONNECT_ERROR",
                    "voltage": "CPU_VOLTAGE_REGULATION"
                }
                primary_scene = scenario_mapping.get(analysis_type, "UNKNOWN")
                with open(scene_file, 'w', encoding='utf-8') as f:
                    f.write(f"PRIMARY_SCENE={primary_scene}\n")
                print(f"📊 记录分析场景: {primary_scene}")
            except:
                pass
        
        self.generate_summary()
        
        return self.results

def main():
    parser = argparse.ArgumentParser(description='CPU故障诊断 - 专项分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('--hardware', action='store_true', help='分析CPU硬件问题')
    parser.add_argument('--temperature', action='store_true', help='分析CPU温度问题')
    parser.add_argument('--errors', action='store_true', help='分析CPU错误')
    parser.add_argument('--frequency', action='store_true', help='分析CPU频率问题')
    parser.add_argument('--microcode', action='store_true', help='分析CPU微码问题')
    parser.add_argument('--cache', action='store_true', help='分析CPU缓存问题')
    parser.add_argument('--interconnect', action='store_true', help='分析CPU互连问题')
    parser.add_argument('--voltage', action='store_true', help='分析CPU电压问题')
    
    args = parser.parse_args()
    
    if not os.path.isdir(args.log_dir):
        print(f"❌ 错误: 目录 '{args.log_dir}' 不存在")
        sys.exit(1)
    
    # 确定分析类型
    analysis_type = None
    if args.hardware:
        analysis_type = "hardware"
    elif args.temperature:
        analysis_type = "temperature"
    elif args.errors:
        analysis_type = "errors"
    elif args.frequency:
        analysis_type = "frequency"
    elif args.microcode:
        analysis_type = "microcode"
    elif args.cache:
        analysis_type = "cache"
    elif args.interconnect:
        analysis_type = "interconnect"
    elif args.voltage:
        analysis_type = "voltage"
    
    # 运行分析
    analyzer = CPUAnalyzer(args.log_dir)
    results = analyzer.run_analysis(analysis_type)
    
    # 如果有结果，返回成功
    if results:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
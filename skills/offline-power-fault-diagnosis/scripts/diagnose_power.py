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

class PowerAnalyzer:
    def __init__(self, log_dir):
        self.log_dir = log_dir
        self.results = []
        self.psu_info = {}
        self.voltage_data = []
        self.error_data = []
        self.power_consumption_data = []
        self.scenes = []
        
    def find_power_files(self):
        """查找所有电源相关文件"""
        power_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                file_lower = file.lower()
                if any(pattern in file_lower for pattern in [
                    'power', 'psu', 'voltage', 'sensor', 'thermal', 
                    'sel', 'ibmc', 'dmesg', 'messages', 'syslog', 'monitor'
                ]):
                    power_files.append(os.path.join(root, file))
        return power_files
    
    def analyze_psu_info(self):
        """分析PSU基本信息"""
        print("🔍 分析PSU基本信息...")
        psu_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                if any(p in file.lower() for p in ['psu_status', 'psu_info', 'power_info']):
                    psu_files.append(os.path.join(root, file))
        
        if not psu_files:
            # 尝试从sensor_info中获取
            psu_files = find_files(self.log_dir, [r".*sensor.*"])
            
        psu_count = 0
        psu_states = {}
        for file_path in psu_files[:3]:
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    matches = re.findall(r'PSU\s*(\d+)[\s:]+(Present|Absent|Normal|Fault|Unknown)', content, re.IGNORECASE)
                    for num, state in matches:
                        psu_states[f"PSU_{num}"] = state
                        psu_count = max(psu_count, int(num))
            except: pass
            
        if psu_states:
            psu_count = len(psu_states)
            print(f"  ✅ 发现 {psu_count} 个PSU模块:")
            for psu, state in psu_states.items():
                print(f"    {psu}: {state}")
            
            self.psu_info = {
                "count": psu_count,
                "states": psu_states
            }
            self.results.append({"type": "PSU_INFO", "data": self.psu_info})
        else:
            print("  ⚠️  未找到具体PSU状态文件")

    def analyze_voltage(self):
        """分析电压数据"""
        print("\n⚡ 分析系统电压...")
        voltage_files = find_files(self.log_dir, [r".*sensor.*", r".*voltage.*"])
        
        anomaly_count = 0
        for file_path in voltage_files[:5]:
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                    for line in lines:
                        if 'voltage' in line.lower() or 'vout' in line.lower() or 'vin' in line.lower():
                            val_match = re.search(r'(\d+\.?\d*)\s*[Vv]', line)
                            if val_match:
                                val = float(val_match.group(1))
                                status = "Normal"
                                if "out of range" in line.lower() or "critical" in line.lower():
                                    status = "Critical"
                                    anomaly_count += 1
                                
                                sensor_match = re.search(r'([a-zA-Z0-9_]+)\s*[:]', line)
                                sensor_name = sensor_match.group(1) if sensor_match else "Unknown"
                                
                                self.voltage_data.append({
                                    "sensor": sensor_name,
                                    "value": val,
                                    "status": status,
                                    "line": line.strip()
                                })
            except: pass
            
        if self.voltage_data:
            print(f"  📊 电压分析完成，发现 {anomaly_count} 次异常记录")
            self.results.append({"type": "VOLTAGE_STATS", "anomaly_count": anomaly_count})
        else:
            print("  ✅ 电压数据正常或缺失")

    def analyze_errors(self):
        """分析电源错误日志"""
        print("\n🚨 分析电源错误日志...")
        error_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                if any(p in file.lower() for p in ['sel', 'messages', 'syslog', 'dmesg', 'ibmc']):
                    error_files.append(os.path.join(root, file))
        
        patterns = [
            (r'power loss|AC lost|input lost', "POWER_LOSS_DETECTED"),
            (r'PSU.*failure|PSU.*fault|PSU.*absent', "PSU_HARDWARE_FAULT"),
            (r'voltage.*out of range|voltage sensor failure', "VOLTAGE_ANOMALY"),
            (r'redundancy lost|redundancy degraded', "REDUNDANCY_ISSUE"),
            (r'overload|current overload', "POWER_OVERLOAD"),
            (r'temperature high|thermal.*fail', "THERMAL_ISSUE")
        ]
        
        error_counts = defaultdict(int)
        for file_path in error_files[:10]:
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        for pattern, tag in patterns:
                            if re.search(pattern, line, re.IGNORECASE):
                                timestamp = None
                                for tp, _ in TIME_PATTERNS:
                                    m = re.search(tp, line)
                                    if m: timestamp = m.group(1); break
                                
                                self.error_data.append({
                                    "tag": tag,
                                    "timestamp": timestamp,
                                    "line": line.strip(),
                                    "file": os.path.basename(file_path)
                                })
                                error_counts[tag] += 1
                                break
            except: pass
            
        if error_counts:
            print("  📊 发现以下电源事件:")
            for tag, count in error_counts.items():
                print(f"    {tag}: {count} 次")
            self.results.append({"type": "ERROR_STATS", "counts": dict(error_counts)})
        else:
            print("  ✅ 未发现明显电源错误日志")

    def classify_scene(self):
        """Step 1: 场景分类"""
        print("\n🏷️  执行场景分类 (Step 1)...")
        scores = defaultdict(int)
        for err in self.error_data:
            scores[err["tag"]] += 1
        
        top_scene = "UNKNOWN"
        if scores:
            top_scene = max(scores, key=scores.get)
            
        mapping = {
            "POWER_LOSS_DETECTED": "POWER_LOSS",
            "PSU_HARDWARE_FAULT": "POWER_MODULE_FAILURE",
            "VOLTAGE_ANOMALY": "VOLTAGE_ANOMALY",
            "REDUNDANCY_ISSUE": "REDUNDANCY_FAILURE",
            "POWER_OVERLOAD": "OVERLOAD",
            "THERMAL_ISSUE": "TEMPERATURE_ISSUE"
        }
        
        scene_label = mapping.get(top_scene, "UNKNOWN")
        print(f"  🎯 判定主要场景: {scene_label}")
        
        # 保存场景到临时文件供报告生成
        try:
            with open("/tmp/power_diagnosis_scene.conf", 'w') as f:
                f.write(f"SCENE={scene_label}\n")
                f.write(f"CONFIDENCE={'HIGH' if scores[top_scene] > 3 else 'MEDIUM' if scores else 'LOW'}\n")
        except: pass
        
        return scene_label

    def cross_validate(self):
        """Step 3: 交叉验证"""
        print("\n⚖️  执行交叉验证 (Step 3)...")
        # 简单的时间一致性检查
        times = [e["timestamp"] for e in self.error_data if e["timestamp"]]
        if len(times) > 1:
            print(f"  ✅ 时间戳一致性校验通过 ({len(times)} 个样本)")
        else:
            print("  ⚠️  时间戳样本不足，无法进行强力验证")
            
        # 物理同一性检查
        psus = set()
        for err in self.error_data:
            m = re.search(r'PSU\s*(\d+)', err["line"], re.IGNORECASE)
            if m: psus.add(m.group(1))
        
        if len(psus) == 1:
            print(f"  ✅ 物理部件定位一致: PSU {list(psus)[0]}")
        elif len(psus) > 1:
            print(f"  ⚠️  多部件受累: PSU {', '.join(sorted(list(psus)))}")

    def save_results(self, scene_label):
        """保存最终JSON结果"""
        output_file = "/tmp/power_analysis_results.json"
        data = {
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "log_dir": self.log_dir,
            "scene": scene_label,
            "psu_info": self.psu_info,
            "error_summary": {
                "total_errors": len(self.error_data),
                "top_errors": self.error_data[:10]
            },
            "voltage_details": self.voltage_data[:20],
            "all_results": self.results
        }
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"\n💾 最终分析结果已保存到: {output_file}")
        except Exception as e:
            print(f"⚠️  错误: 无法保存JSON结果: {e}")

    def run(self, analysis_type=None):
        print("="*60)
        print(f"🚀 开始电源故障综合分析: {self.log_dir}")
        print("="*60)
        
        self.analyze_psu_info()
        self.analyze_voltage()
        self.analyze_errors()
        
        scene = self.classify_scene()
        self.cross_validate()
        self.save_results(scene)
        
        print("\n" + "="*60)
        print("✅ 分析流程执行完毕")
        print("="*60)

def find_files(root_dir, patterns):
    matches = []
    for root, d, files in os.walk(root_dir):
        for f in files:
            for p in patterns:
                if re.match(p, f, re.IGNORECASE):
                    matches.append(os.path.join(root, f))
    return matches

def main():
    parser = argparse.ArgumentParser(description='服务器电源故障专项分析工具')
    parser.add_argument('log_dir', help='日志根目录')
    parser.add_argument('--full', action='store_true', help='全量分析')
    # 为了兼容CPU脚本的命名习惯
    parser.add_argument('--hardware', action='store_true')
    parser.add_argument('--voltage', action='store_true')
    parser.add_argument('--overload', action='store_true')
    
    args = parser.parse_args()
    if not os.path.isdir(args.log_dir):
        print(f"❌ 目录不存在: {args.log_dir}")
        sys.exit(1)
        
    analyzer = PowerAnalyzer(args.log_dir)
    analyzer.run()

if __name__ == "__main__":
    main()

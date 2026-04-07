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

class NetworkAnalyzer:
    def __init__(self, log_dir):
        self.log_dir = log_dir
        self.results = []
        self.nic_info = {}
        self.temperature_data = []
        self.error_data = []
        self.link_data = []
        self.performance_data = []
        
    def find_network_files(self):
        """查找所有网络相关文件"""
        net_files = []
        patterns = ['net', 'eth', 'ethtool', 'ifconfig', 'ip_addr', 'pci', 'lspci']
        for root, dirs, files in os.walk(self.log_dir):
            # 强化对这些子目录的识别
            if any(p in root.lower() for p in ['network', 'infocollect_logs']):
                for file in files:
                    if not any(file.lower().endswith(ext) for ext in ['.exe', '.bin', '.dll', '.so']):
                        net_files.append(os.path.join(root, file))
            else:
                for file in files:
                    file_lower = file.lower()
                    if any(p in file_lower for p in patterns):
                        net_files.append(os.path.join(root, file))
        return net_files
    
    def analyze_nic_info(self):
        """分析网卡基本信息"""
        print("🔍 分析网卡基本信息...")
        info_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                file_lower = file.lower()
                if any(p in file_lower for p in ['ethtool_i', 'lspci', 'nic_info']):
                    info_files.append(os.path.join(root, file))
        
        if info_files:
            for f_path in info_files[:3]:
                try:
                    with open(f_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        driver = re.search(r'driver:\s*(\S+)', content)
                        version = re.search(r'version:\s*(\S+)', content)
                        fw = re.search(r'firmware-version:\s*(\S+)', content)
                        bus = re.search(r'bus-info:\s*(\S+)', content)
                        
                        if driver:
                            self.nic_info = {
                                "driver": driver.group(1),
                                "version": version.group(1) if version else "未知",
                                "firmware": fw.group(1) if fw else "未知",
                                "bus_info": bus.group(1) if bus else "未知"
                            }
                            print(f"  ✅ 发现网卡: {self.nic_info['bus_info']} (驱动: {self.nic_info['driver']})")
                            break
                except: pass
                
        if self.nic_info:
            # 这里的 type 为 NIC_INFO 保持不变，但后期会映射到报告中的 network_info 健值
            self.results.append({"type": "NIC_INFO", "data": self.nic_info})

    def analyze_temperature(self):
        """分析网卡温度"""
        print("\n🌡️ 分析网卡温度...")
        temp_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                if 'sensor' in file.lower() or 'temp' in file.lower():
                    temp_files.append(os.path.join(root, file))
        
        for f_path in temp_files[:5]:
            try:
                with open(f_path, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        if 'nic' in line.lower() or 'network' in line.lower():
                            match = re.search(r'(\d+\.?\d*)\s*°?[Cc]', line)
                            if match:
                                temp = float(match.group(1))
                                status = "正常"
                                if temp > 85: status = "警告"
                                if temp > 95: status = "危险"
                                
                                ts = self._extract_timestamp(line)
                                entry = {"sensor": "网卡温度", "value": temp, "status": status, "timestamp": ts, "file": os.path.basename(f_path)}
                                self.temperature_data.append(entry)
                                if status in ["警告", "危险"]:
                                    print(f"  ⚠️  网卡温度异常: {temp}°C ({status})")
            except: pass
            
    def analyze_errors(self):
        """分析网络错误"""
        print("\n🚨 分析网络错误...")
        err_patterns = [
            (r'PCIe\s+error|AER\s+Error|Surprise\s+Removal', "PCIe严重错误/热插拔"),
            (r'NIC\s+failure|Hardware\s+failure', "硬件故障"),
            (r'TX\s+unit\s+hang|reset\s+adapter', "网卡挂死/重置"),
            (r'link\s+down|link\s+is\s+down|lost\s+carrier', "链路断开"),
            (r'IP\s+conflict|duplicate\s+address|arp\s+reply.*conflict', "IP/ARP冲突"),
            (r'bonding:.*failover|bonding:.*enslave', "Bond切换/成员变动"),
            (r'ICMP\s+fragmentation\s+needed|MTU\s+mismatch', "MTU不一致"),
            (r'udev:.*renamed\s+eth\d+', "网卡命名乱序"),
            (r'broadcast\s+storm|packet\s+storm', "网络环路/风暴")
        ]
        
        err_files = []
        for root, dirs, files in os.walk(self.log_dir):
            for file in files:
                if any(p in file.lower() for p in ['messages', 'dmesg', 'syslog', 'sel', 'ibmc']):
                    err_files.append(os.path.join(root, file))
                    
        for f_path in err_files[:10]:
            try:
                with open(f_path, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        for pattern, desc in err_patterns:
                            if re.search(pattern, line, re.IGNORECASE):
                                ts = self._extract_timestamp(line)
                                entry = {"description": desc, "timestamp": ts, "file": os.path.basename(f_path), "line": line.strip()}
                                self.error_data.append(entry)
                                break
            except: pass
            
        print(f"  📊 发现 {len(self.error_data)} 条潜在网络错误记录")

    def _extract_timestamp(self, line):
        for pattern, _ in TIME_PATTERNS:
            match = re.search(pattern, line)
            if match: return match.group(1)
        return None

    def run_analysis(self, analysis_type=None):
        print(f"🔍 开始网络故障全量分析: {self.log_dir}")
        print("=" * 60)
        self.analyze_nic_info()
        self.analyze_temperature()
        self.analyze_errors()
        
        # 保存场景标签
        if analysis_type:
            try:
                with open("/tmp/network_diagnosis_scene.conf", 'w') as f:
                    mapping = {"hardware": "NIC_HARDWARE_FAILURE", "link": "LINK_DOWN", "performance": "PERFORMANCE_DEGRADATION"}
                    f.write(f"PRIMARY_SCENE={mapping.get(analysis_type, 'UNKNOWN')}\n")
            except: pass

        self.save_results()
        return self.results

    def save_results(self):
        output_file = "/tmp/network_analysis_results.json"
        try:
            # 尝试加载现有结果以实现增量合并
            existing_data = {}
            if os.path.exists(output_file):
                try:
                    with open(output_file, 'r', encoding='utf-8') as f:
                        existing_data = json.load(f)
                except: pass

            temp_sum = {"high_temps": [t for t in self.temperature_data if t["status"] in ["警告", "危险"]], "total_readings": len(self.temperature_data)}
            err_sum = {"critical_errors": self.error_data, "total_errors": len(self.error_data)}
            
            new_all_results = self.results + \
                              [{"type": "OS_ERROR", "description": e["description"], "timestamp": e["timestamp"], "file": e["file"], "line": e["line"]} for e in self.error_data]
            
            # 合并逻辑
            all_results_list = existing_data.get('all_results', [])
            all_results_list.extend(new_all_results)

            summary = {
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "log_dir": self.log_dir,
                "network_info": self.nic_info if self.nic_info else existing_data.get('network_info', {}),
                "temperature_summary": temp_sum,
                "error_summary": err_sum,
                "all_results": all_results_list
            }
            # 额外添加汇总场景标签
            if any(e["description"] in ["网卡挂死/重置", "链路断开"] for e in self.error_data):
                summary["all_results"].append({"type": "LINK_STATS", "status": "不稳定"})
            if any("硬件故障" in e["description"] for e in self.error_data):
                summary["all_results"].append({"type": "ERROR_STATS", "status": "硬件故障"})

            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(summary, f, ensure_ascii=False, indent=2)
            print(f"💾 分析结果已保存并合并到: {output_file}")
        except Exception as e:
            print(f"⚠️  结果保存失败: {str(e)}")

def main():
    parser = argparse.ArgumentParser(description='网络故障诊断 - 专项分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('--hardware', action='store_true')
    parser.add_argument('--link', action='store_true')
    parser.add_argument('--performance', action='store_true')
    parser.add_argument('--driver', action='store_true')
    
    args = parser.parse_args()
    if not os.path.isdir(args.log_dir):
        print(f"❌ 错误: 目录 '{args.log_dir}' 不存在")
        sys.exit(1)
    
    analysis_type = None
    if args.hardware: analysis_type = "hardware"
    elif args.link: analysis_type = "link"
    elif args.performance: analysis_type = "performance"
    elif args.driver: analysis_type = "driver"
    
    analyzer = NetworkAnalyzer(args.log_dir)
    results = analyzer.run_analysis(analysis_type)
    # 不再因为 0 结果而返回退出码 1，除非发生脚本崩溃型异常
    sys.exit(0)

if __name__ == '__main__':
    main()

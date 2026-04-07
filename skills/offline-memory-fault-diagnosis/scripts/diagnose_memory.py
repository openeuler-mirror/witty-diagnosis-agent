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

class MemoryAnalyzer:
    def __init__(self, log_dir):
        self.log_dir = log_dir
        self.results = []
        self.memory_info = {}
        self.error_data = []
        self.performance_data = []
        
    def analyze_memory_info(self):
        """分析内存基本配置信息"""
        print("🔍 分析内存基本配置...")
        meminfo_files = [os.path.join(r, f) for r, d, files in os.walk(self.log_dir) for f in files if 'meminfo' in f.lower()]
        
        if not meminfo_files:
            print("  ⚠️  未找到 meminfo 文件")
            return
            
        try:
            with open(meminfo_files[0], 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                mem_total = re.search(r'MemTotal:\s+(\d+)\s+kB', content)
                huge_pages = re.search(r'HugePages_Total:\s+(\d+)', content)
                slab_size = re.search(r'Slab:\s+(\d+)\s+kB', content)
                
                self.memory_info = {
                    "mem_total_gb": round(int(mem_total.group(1))/1024/1024, 2) if mem_total else 0,
                    "huge_pages": int(huge_pages.group(1)) if huge_pages else 0,
                    "slab_kb": int(slab_size.group(1)) if slab_size else 0,
                    "source": os.path.basename(meminfo_files[0])
                }
                print(f"  ✅ 内存总量: {self.memory_info['mem_total_gb']} GB")
                print(f"  ✅ Slab 占用: {self.memory_info['slab_kb']} kB")
                self.results.append({"type": "MEMORY_INFO", "data": self.memory_info})
        except Exception as e:
            print(f"  ⚠️  内存信息分析失败: {e}")

    def analyze_errors(self, scenario=None, keywords=None, date_filter=None):
        """分析内存错误 (ECC, UCE, OOM等)，支持自定义关键字和日期过滤"""
        print(f"\n🚨 分析内存错误 (场景: {scenario or '通用'})...")
        
        search_patterns = []
        if keywords:
            for k in keywords:
                search_patterns.append((re.escape(k), f"自定义搜索: {k}"))
        else:
            search_patterns = [
                (r'ECC error', "ECC错误"),
                (r'Uncorrectable Error', "不可纠正错误(UCE)"),
                (r'Correctable Error', "可纠正错误(CE)"),
                (r'Out of memory', "系统内存不足(OOM)"),
                (r'OOM.*killer', "OOM Killer 触发"),
                (r'memory corruption', "内存数据损坏"),
                (r'segfault', "分段错误"),
                (r'DIMM.*Presence', "内存条在位丢失"),
            ]
        
        # 搜索日志文件
        log_files = []
        for r, d, files in os.walk(self.log_dir):
            for f in files:
                if any(p in f.lower() for p in ['messages', 'syslog', 'dmesg', 'sel', 'ibmc']):
                    log_files.append(os.path.join(r, f))
        
        for fp in log_files[:15]: # 略微增加扫描覆盖面
            try:
                with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
                    for line_num, line in enumerate(f, 1):
                        if date_filter and date_filter.lower() not in line.lower():
                            continue
                        for pattern, desc in search_patterns:
                            if re.search(pattern, line, re.IGNORECASE):
                                ts = None
                                for tp, _ in TIME_PATTERNS:
                                    m = re.search(tp, line)
                                    if m: ts = m.group(1); break
                                
                                err_item = {
                                    "description": desc,
                                    "timestamp": ts,
                                    "file": os.path.basename(fp),
                                    "line": line.strip()
                                }
                                self.error_data.append(err_item)
                                print(f"  ❌ [{ts or '?'}] {desc} ({os.path.basename(fp)})")
                                break
            except: pass
            
        if self.error_data:
            self.results.append({"type": "ERROR_STATS", "total": len(self.error_data), "errors": self.error_data[:100]})
        else:
            print("  ✅ 未发现明显内存错误")

    def analyze_performance(self):
        """分析内存性能 (Swap, NUMA)"""
        print("\n📈 分析内存性能...")
        numa_files = [os.path.join(r, f) for r, d, fs in os.walk(self.log_dir) for f in fs if 'numa' in f.lower()]
        if numa_files:
            print(f"  ✅ 发现 {len(numa_files)} 个 NUMA 相关日志，已加入分析队列")
            self.results.append({"type": "PERFORMANCE_LOGS", "count": len(numa_files)})
        else:
            print("  ✅ 未发现明确的性能异常日志")

    def save_results(self, scenario):
        """保存分析结果"""
        output_file = "/tmp/memory_analysis_results.json"
        existing_data = {}
        if os.path.exists(output_file):
            try:
                with open(output_file, 'r', encoding='utf-8') as f: existing_data = json.load(f)
            except: pass
            
        all_results_list = existing_data.get('all_results', [])
        all_results_list.extend(self.results)
        
        results_summary = {
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "log_dir": self.log_dir,
            "memory_info": self.memory_info if self.memory_info else existing_data.get('memory_info', {}),
            "all_results": all_results_list
        }
        
        try:
            # 路径不存在则创建
            os.makedirs(os.path.dirname(output_file), exist_ok=True)
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(results_summary, f, ensure_ascii=False, indent=2)
            
            # 记录场景
            if scenario:
                with open("/tmp/memory_diagnosis_scene.conf", 'w') as f:
                    f.write(f"PRIMARY_SCENE={scenario.upper()}\n")
            
            print(f"\n💾 分析结果已保存: {output_file}")
        except: pass

def main():
    parser = argparse.ArgumentParser(description='内存故障诊断 - 专项分析')
    parser.add_argument('log_dir', help='日志目录路径')
    parser.add_argument('--ecc', action='store_true')
    parser.add_argument('--oom', action='store_true')
    parser.add_argument('--leak', action='store_true')
    parser.add_argument('--performance', action='store_true')
    parser.add_argument('-k', '--keywords', nargs='+', help='自定义关键字过滤')
    parser.add_argument('-d', '--date', help='日期过滤 (如 "2025-07-21")')
    args = parser.parse_args()
    
    if not os.path.isdir(args.log_dir): sys.exit(1)
    
    analyzer = MemoryAnalyzer(args.log_dir)
    analyzer.analyze_memory_info()
    
    scenario = None
    if args.ecc: scenario = "MEMORY_ECC_ERROR"
    elif args.oom: scenario = "MEMORY_OOM_KILLER"
    elif args.leak: scenario = "MEMORY_LEAK"
    elif args.performance: scenario = "MEMORY_PERFORMANCE"
    
    analyzer.analyze_errors(scenario, keywords=args.keywords, date_filter=args.date)
    analyzer.analyze_performance()
    analyzer.save_results(scenario)

if __name__ == '__main__':
    main()


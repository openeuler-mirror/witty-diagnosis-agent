#!/usr/bin/env python3
import os
import sys
import re
import argparse
from datetime import datetime

# Common timestamp patterns
TIME_PATTERNS = [
    r'(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})',
    r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})',
    r'(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})',
    r'(\[\s*\d+\.\d+\])',
]

def find_files(root_dir, filename_pattern):
    matches = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if re.match(filename_pattern, file, re.IGNORECASE):
                matches.append(os.path.join(root, file))
    return matches

def read_log_content(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    except:
        return ""

def is_in_time_range(line, start_dt, end_dt, date_str):
    # If generic date string is provided
    if date_str:
        if date_str in line:
            return True
        if not start_dt and not end_dt:
            return False
    
    # If precise time range
    if start_dt or end_dt:
        # Try to extract timestamp
        for pattern in TIME_PATTERNS:
            match = re.search(pattern, line)
            if match:
                ts_str = match.group(1)
                # Try parsing
                fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
                for fmt in fmts:
                    try:
                        dt = datetime.strptime(ts_str, fmt)
                        if fmt == "%b %d %H:%M:%S": dt = dt.replace(year=datetime.now().year)
                        if start_dt and dt < start_dt: return False
                        if end_dt and dt > end_dt: return False
                        return True
                    except:
                        continue
        # If line has no timestamp but we are filtering by time, skip it
        return False
        
    return True

def analyze_disk_failure(log_dir, keywords=None, start_dt=None, end_dt=None, date_str=None):
    results = {
        "smart_status": [],
        "smart_metrics": {},
        "hardware_errors": [],
        "io_errors": [],
        "affected_devices": set(),
        "critical_issues": [],
        "timeline": []
    }
    
    # Find and analyze SMART logs
    smart_files = find_files(log_dir, r".*smart.*")
    for file_path in smart_files:
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                current_device = None
                for i, line in enumerate(f, 1):
                    if not is_in_time_range(line, start_dt, end_dt, date_str):
                        continue
                    if keywords:
                        keyword_match = False
                        for keyword in keywords:
                            if keyword.lower() in line.lower():
                                keyword_match = True
                                break
                        if not keyword_match:
                            continue
                    
                    # Extract device name
                    device_match = re.search(r'/dev/(sd[a-z]|nvme\d+n\d+|hd[a-z])', line, re.IGNORECASE)
                    if device_match:
                        current_device = device_match.group(0)
                        results["affected_devices"].add(current_device)
                    
                    # Check SMART overall health
                    if re.search(r'SMART overall-health.*PASSED', line, re.IGNORECASE):
                        results["smart_status"].append(f"{current_device or 'Unknown'}: SMART健康状态: PASSED")
                    elif re.search(r'SMART overall-health.*FAILED', line, re.IGNORECASE):
                        results["smart_status"].append(f"{current_device or 'Unknown'}: ❌ SMART健康状态: FAILED")
                        results["critical_issues"].append(f"SMART检测到磁盘故障: {current_device or 'Unknown'}")
                    
                    # Extract SMART metrics
                    metric_patterns = {
                        "Reallocated_Sector_Ct": r'Reallocated_Sector_Ct.*\s+(\d+)\s+(\d+)\s+(\d+)',
                        "Current_Pending_Sector": r'Current_Pending_Sector.*\s+(\d+)\s+(\d+)\s+(\d+)',
                        "Offline_Uncorrectable": r'Offline_Uncorrectable.*\s+(\d+)\s+(\d+)\s+(\d+)',
                        "Seek_Error_Rate": r'Seek_Error_Rate.*\s+(\d+)\s+(\d+)\s+(\d+)',
                        "Power_On_Hours": r'Power_On_Hours.*\s+(\d+)\s+(\d+)\s+(\d+)',
                        "Temperature_Celsius": r'Temperature_Celsius.*\s+(\d+)\s+(\d+)\s+(\d+)',
                    }
                    
                    for metric_name, pattern in metric_patterns.items():
                        match = re.search(pattern, line, re.IGNORECASE)
                        if match:
                            raw = match.group(1)
                            value = match.group(2)
                            threshold = match.group(3)
                            if current_device not in results["smart_metrics"]:
                                results["smart_metrics"][current_device] = {}
                            results["smart_metrics"][current_device][metric_name] = {
                                "raw": raw,
                                "value": value,
                                "threshold": threshold
                            }
                            
                            # Check for critical values
                            if metric_name in ["Reallocated_Sector_Ct", "Current_Pending_Sector", "Offline_Uncorrectable"]:
                                try:
                                    if int(value) > 0:
                                        results["critical_issues"].append(f"{current_device}: {metric_name} = {value} (有坏扇区)")
                                except:
                                    pass
        except:
            pass
    
    # Find and analyze kernel logs for hardware errors
    kernel_files = find_files(log_dir, r".*dmesg.*")
    for file_path in kernel_files:
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                for i, line in enumerate(f, 1):
                    if not is_in_time_range(line, start_dt, end_dt, date_str):
                        continue
                    if keywords:
                        keyword_match = False
                        for keyword in keywords:
                            if keyword.lower() in line.lower():
                                keyword_match = True
                                break
                        if not keyword_match:
                            continue
                    
                    # Check for hardware errors
                    if re.search(r'hardware error|MCE|Machine Check|DRDY ERR|UNC|ICRC|ABRT', line, re.IGNORECASE):
                        results["hardware_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract device info
                        device_match = re.search(r'(sd[a-z]|nvme\d+n\d+|hd[a-z])', line, re.IGNORECASE)
                        if device_match:
                            results["affected_devices"].add(f"/dev/{device_match.group(0)}")
                        
                        # Check if critical
                        if re.search(r'UNC.*error|fatal.*error|critical', line, re.IGNORECASE):
                            results["critical_issues"].append(f"硬件致命错误: {line.strip()[:100]}")
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"硬件错误: {line.strip()[:80]}"))
                                break
        except:
            pass
    
    # Find and analyze kernel logs for I/O errors
    for file_path in kernel_files:
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                for i, line in enumerate(f, 1):
                    if not is_in_time_range(line, start_dt, end_dt, date_str):
                        continue
                    if keywords:
                        keyword_match = False
                        for keyword in keywords:
                            if keyword.lower() in line.lower():
                                keyword_match = True
                                break
                        if not keyword_match:
                            continue
                    
                    # Check for I/O errors
                    if re.search(r'I/O error|block.*error|timeout.*I/O|Buffer I/O error|read-error|write-error', line, re.IGNORECASE):
                        results["io_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract device info
                        device_match = re.search(r'(sd[a-z]|nvme\d+n\d+|hd[a-z])', line, re.IGNORECASE)
                        if device_match:
                            results["affected_devices"].add(f"/dev/{device_match.group(0)}")
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"I/O错误: {line.strip()[:80]}"))
                                break
        except:
            pass
    
    return results

def main():
    parser = argparse.ArgumentParser(
        description="Disk Hardware Failure Diagnosis Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/
  python3 %(prog)s ./logs/ -k "FAILED" "error"
  python3 %(prog)s ./logs/ -d "Mar 16"
  python3 %(prog)s ./logs/ -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
        """
    )
    
    parser.add_argument("log_dir", help="Directory containing file system logs")
    parser.add_argument("-k", "--keywords", nargs="+", metavar="WORD",
                        help="Additional keywords to search for")
    parser.add_argument("-d", "--date", metavar="DATE_STR",
                        help="Filter logs by specific date string")
    parser.add_argument("-s", "--start-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="Start time for filtering")
    parser.add_argument("-e", "--end-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="End time for filtering")
    
    args = parser.parse_args()
    
    if not os.path.isdir(args.log_dir):
        print(f"Error: {args.log_dir} is not a directory.")
        sys.exit(1)
    
    start_dt = None
    end_dt = None
    if args.start_time:
        try:
            start_dt = datetime.strptime(args.start_time, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            print("Error: Invalid start time format.")
            sys.exit(1)
    if args.end_time:
        try:
            end_dt = datetime.strptime(args.end_time, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            print("Error: Invalid end time format.")
            sys.exit(1)
    
    print("================================================================")
    print(" 磁盘硬件故障深度分析报告")
    print(" 时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("================================================================")
    print()
    
    results = analyze_disk_failure(
        args.log_dir, 
        args.keywords, 
        start_dt, 
        end_dt, 
        args.date
    )
    
    # Summary
    print("━━━━ [A] 分析摘要 ━━━━")
    print(f"  受影响设备: {', '.join(results['affected_devices']) if results['affected_devices'] else '未知'}")
    print(f"  SMART状态数: {len(results['smart_status'])}")
    print(f"  硬件错误数: {len(results['hardware_errors'])}")
    print(f"  I/O错误数: {len(results['io_errors'])}")
    print(f"  关键问题数: {len(results['critical_issues'])}")
    print()
    
    # Critical Issues
    if results["critical_issues"]:
        print("━━━━ [B] 关键问题 (需立即处理) ━━━━")
        for i, issue in enumerate(results["critical_issues"], 1):
            print(f"  ⚠️  {i}. {issue}")
        print()
    
    # SMART Status
    if results["smart_status"]:
        print("━━━━ [C] SMART 健康状态 ━━━━")
        for status in results["smart_status"]:
            print(f"  {status}")
        print()
    
    # SMART Metrics
    if results["smart_metrics"]:
        print("━━━━ [D] SMART 关键指标 ━━━━")
        for device, metrics in results["smart_metrics"].items():
            print(f"  设备: {device or 'Unknown'}")
            for metric_name, values in metrics.items():
                raw = values.get("raw", "N/A")
                value = values.get("value", "N/A")
                threshold = values.get("threshold", "N/A")
                
                # Add warning for critical metrics
                warning = ""
                if metric_name in ["Reallocated_Sector_Ct", "Current_Pending_Sector", "Offline_Uncorrectable"]:
                    try:
                        if int(value) > 0:
                            warning = " ⚠️ (有坏扇区)"
                    except:
                        pass
                
                print(f"    {metric_name}: RAW={raw}, VALUE={value}, THRESH={threshold}{warning}")
            print()
    
    # Hardware Errors
    if results["hardware_errors"]:
        print("━━━━ [E] 硬件错误日志 ━━━━")
        for i, error in enumerate(results["hardware_errors"][:15], 1):
            print(f"  {i}. {error}")
        if len(results["hardware_errors"]) > 15:
            print(f"  ... (还有 {len(results['hardware_errors']) - 15} 个错误未显示)")
        print()
    
    # I/O Errors
    if results["io_errors"]:
        print("━━━━ [F] I/O 错误日志 ━━━━")
        for i, error in enumerate(results["io_errors"][:15], 1):
            print(f"  {i}. {error}")
        if len(results["io_errors"]) > 15:
            print(f"  ... (还有 {len(results['io_errors']) - 15} 个错误未显示)")
        print()
    
    # Timeline
    if results["timeline"]:
        print("━━━━ [G] 时间线分析 ━━━━")
        # Sort by timestamp
        sorted_timeline = sorted(results["timeline"], key=lambda x: x[0])
        for timestamp, event in sorted_timeline[:10]:
            print(f"  [{timestamp}] {event}")
        if len(sorted_timeline) > 10:
            print(f"  ... (还有 {len(sorted_timeline) - 10} 个事件未显示)")
        print()
    
    # Recommendations
    print("━━━━ [H] 修复建议 ━━━━")
    print("  1. ⚠️  立即停止对故障磁盘的写入操作")
    print("  2. 尽快备份重要数据到其他存储设备")
    
    if results["critical_issues"]:
        print("  3. 检测到关键问题，建议立即更换磁盘")
    
    if any("Reallocated_Sector_Ct" in str(m) for m in results["smart_metrics"].values()):
        print("  4. 存在重新分配扇区，磁盘有物理损坏")
        print("     - 评估是否可继续使用")
        print("     - 监控坏扇区增长趋势")
    
    if any("Current_Pending_Sector" in str(m) for m in results["smart_metrics"].values()):
        print("  5. 存在待处理扇区，可能有潜在坏道")
        print("     - 运行完整磁盘扫描")
        print("     - 考虑使用ddrescue进行数据恢复")
    
    if results["hardware_errors"]:
        print("  6. 检测到硬件错误，检查磁盘连接和电源")
        print("     - 重新插拔磁盘和数据线")
        print("     - 检查RAID控制器状态")
    
    if results["io_errors"] > 10:
        print("  7. I/O错误频繁，磁盘可能即将完全失效")
        print("     - 立即更换磁盘")
        print("     - 重建RAID阵列（如适用）")
    
    print("  8. 更换磁盘后验证新磁盘健康状态")
    print("  9. 定期监控磁盘SMART指标")
    print()
    
    print("⚠️  注意：以上为基于日志的离线分析建议，实际操作需在原系统上执行")
    print("================================================================")

if __name__ == "__main__":
    main()
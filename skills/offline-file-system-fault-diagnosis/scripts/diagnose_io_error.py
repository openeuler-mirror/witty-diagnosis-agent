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

def analyze_io_error(log_dir, keywords=None, start_dt=None, end_dt=None, date_str=None):
    results = {
        "io_errors": [],
        "block_errors": [],
        "timeout_errors": [],
        "buffer_errors": [],
        "scsi_errors": [],
        "ata_errors": [],
        "affected_devices": set(),
        "error_patterns": {},
        "timeline": []
    }
    
    # Find and analyze kernel logs
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
                    
                    # Check for I/O errors
                    if re.search(r'I/O error', line, re.IGNORECASE):
                        results["io_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract device info
                        device_match = re.search(r'dev (\S+)', line, re.IGNORECASE)
                        if device_match:
                            device = device_match.group(1)
                            results["affected_devices"].add(device)
                            if device not in results["error_patterns"]:
                                results["error_patterns"][device] = 0
                            results["error_patterns"][device] += 1
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"I/O错误: {line.strip()[:80]}"))
                                break
                    
                    # Check for block errors
                    elif re.search(r'block.*error|blk_update_request.*error', line, re.IGNORECASE):
                        results["block_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract device and sector info
                        device_match = re.search(r'dev (\S+)', line, re.IGNORECASE)
                        sector_match = re.search(r'sector (\d+)', line, re.IGNORECASE)
                        
                        if device_match:
                            device = device_match.group(1)
                            results["affected_devices"].add(device)
                        
                        if sector_match:
                            sector = sector_match.group(1)
                            results["timeline"].append((datetime.now().strftime("%H:%M:%S"), f"块错误: 设备 {device or 'unknown'}, 扇区 {sector}"))
                    
                    # Check for timeout errors
                    elif re.search(r'timeout.*I/O|I/O.*timeout', line, re.IGNORECASE):
                        results["timeout_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract device info
                        device_match = re.search(r'dev (\S+)', line, re.IGNORECASE)
                        if device_match:
                            device = device_match.group(1)
                            results["affected_devices"].add(device)
                    
                    # Check for buffer I/O errors
                    elif re.search(r'Buffer I/O error', line, re.IGNORECASE):
                        results["buffer_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract device and logical block info
                        device_match = re.search(r'dev (\S+)', line, re.IGNORECASE)
                        block_match = re.search(r'logical block (\d+)', line, re.IGNORECASE)
                        
                        if device_match:
                            device = device_match.group(1)
                            results["affected_devices"].add(device)
                        
                        if block_match:
                            block = block_match.group(1)
                            results["timeline"].append((datetime.now().strftime("%H:%M:%S"), f"缓冲区I/O错误: 设备 {device or 'unknown'}, 逻辑块 {block}"))
                    
                    # Check for SCSI errors
                    elif re.search(r'SCSI error', line, re.IGNORECASE):
                        results["scsi_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract sense key info
                        sense_match = re.search(r'sense key (\S+)', line, re.IGNORECASE)
                        if sense_match:
                            sense_key = sense_match.group(1)
                            results["timeline"].append((datetime.now().strftime("%H:%M:%S"), f"SCSI错误: sense key {sense_key}"))
                    
                    # Check for ATA errors
                    elif re.search(r'ata.*error|DRDY.*err|exception Emask', line, re.IGNORECASE):
                        results["ata_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract ATA port info
                        ata_match = re.search(r'ata(\d+\.\d+)', line, re.IGNORECASE)
                        if ata_match:
                            ata_port = ata_match.group(1)
                            results["timeline"].append((datetime.now().strftime("%H:%M:%S"), f"ATA错误: 端口 {ata_port}"))
        except:
            pass
    
    # Find and analyze system logs
    sysmsg_files = find_files(log_dir, r".*messages.*|.*syslog.*")
    for file_path in sysmsg_files:
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
                    
                    # Check for I/O related errors in system logs
                    if re.search(r'disk.*error|storage.*error|read.*failed|write.*failed', line, re.IGNORECASE):
                        results["io_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"系统日志I/O错误: {line.strip()[:80]}"))
                                break
        except:
            pass
    
    return results

def main():
    parser = argparse.ArgumentParser(
        description="I/O Error Diagnosis Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/
  python3 %(prog)s ./logs/ -k "timeout" "sector"
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
    print(" I/O错误深度分析报告")
    print(" 时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("================================================================")
    print()
    
    results = analyze_io_error(
        args.log_dir, 
        args.keywords, 
        start_dt, 
        end_dt, 
        args.date
    )
    
    # Summary
    print("━━━━ [A] 分析摘要 ━━━━")
    print(f"  受影响设备: {', '.join(results['affected_devices']) if results['affected_devices'] else '未知'}")
    print(f"  I/O错误总数: {len(results['io_errors'])}")
    print(f"  块错误数: {len(results['block_errors'])}")
    print(f"  超时错误数: {len(results['timeout_errors'])}")
    print(f"  缓冲区错误数: {len(results['buffer_errors'])}")
    print(f"  SCSI错误数: {len(results['scsi_errors'])}")
    print(f"  ATA错误数: {len(results['ata_errors'])}")
    print()
    
    # Error patterns by device
    if results["error_patterns"]:
        print("━━━━ [B] 设备错误统计 ━━━━")
        sorted_patterns = sorted(results["error_patterns"].items(), key=lambda x: x[1], reverse=True)
        for device, count in sorted_patterns:
            severity = "⚠️ " if count > 10 else ""
            print(f"  {severity}{device}: {count} 个错误")
        print()
    
    # I/O Errors
    if results["io_errors"]:
        print("━━━━ [C] I/O 错误日志 ━━━━")
        for i, error in enumerate(results["io_errors"][:15], 1):
            print(f"  {i}. {error}")
        if len(results["io_errors"]) > 15:
            print(f"  ... (还有 {len(results['io_errors']) - 15} 个错误未显示)")
        print()
    
    # Block Errors
    if results["block_errors"]:
        print("━━━━ [D] 块设备错误日志 ━━━━")
        for i, error in enumerate(results["block_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["block_errors"]) > 10:
            print(f"  ... (还有 {len(results['block_errors']) - 10} 个错误未显示)")
        print()
    
    # Timeout Errors
    if results["timeout_errors"]:
        print("━━━━ [E] 超时错误日志 ━━━━")
        for i, error in enumerate(results["timeout_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["timeout_errors"]) > 10:
            print(f"  ... (还有 {len(results['timeout_errors']) - 10} 个错误未显示)")
        print()
    
    # Buffer Errors
    if results["buffer_errors"]:
        print("━━━━ [F] 缓冲区I/O错误日志 ━━━━")
        for i, error in enumerate(results["buffer_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["buffer_errors"]) > 10:
            print(f"  ... (还有 {len(results['buffer_errors']) - 10} 个错误未显示)")
        print()
    
    # SCSI Errors
    if results["scsi_errors"]:
        print("━━━━ [G] SCSI错误日志 ━━━━")
        for i, error in enumerate(results["scsi_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["scsi_errors"]) > 10:
            print(f"  ... (还有 {len(results['scsi_errors']) - 10} 个错误未显示)")
        print()
    
    # ATA Errors
    if results["ata_errors"]:
        print("━━━━ [H] ATA错误日志 ━━━━")
        for i, error in enumerate(results["ata_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["ata_errors"]) > 10:
            print(f"  ... (还有 {len(results['ata_errors']) - 10} 个错误未显示)")
        print()
    
    # Timeline
    if results["timeline"]:
        print("━━━━ [I] 时间线分析 ━━━━")
        # Sort by timestamp
        sorted_timeline = sorted(results["timeline"], key=lambda x: x[0])
        for timestamp, event in sorted_timeline[:15]:
            print(f"  [{timestamp}] {event}")
        if len(sorted_timeline) > 15:
            print(f"  ... (还有 {len(sorted_timeline) - 15} 个事件未显示)")
        print()
    
    # Recommendations
    print("━━━━ [J] 修复建议 ━━━━")
    
    if len(results["io_errors"]) > 20:
        print("  1. ⚠️  I/O错误频繁，建议立即检查磁盘健康")
        print("     - 运行 smartctl -a /dev/sdX")
        print("     - 检查SMART指标")
    
    if results["timeout_errors"]:
        print("  2. 超时错误可能原因：")
        print("     - 磁盘响应慢")
        print("     - 电缆连接问题")
        print("     - 控制器问题")
        print("     - 增加超时时间: echo 180 > /sys/block/sdX/device/timeout")
    
    if results["block_errors"]:
        print("  3. 块设备错误：")
        print("     - 检查坏扇区")
        print("     - 运行坏道扫描: badblocks -sv /dev/sdX")
        print("     - 考虑更换磁盘")
    
    if results["buffer_errors"]:
        print("  4. 缓冲区I/O错误：")
        print("     - 文件系统损坏")
        print("     - 内存问题")
        print("     - 运行文件系统检查: fsck /dev/sdX")
    
    if results["scsi_errors"]:
        print("  5. SCSI错误：")
        print("     - 检查SCSI线缆")
        print("     - 验证终端电阻")
        print("     - 检查SCSI ID冲突")
    
    if results["ata_errors"]:
        print("  6. ATA错误：")
        print("     - 检查ATA/IDE电缆")
        print("     - 验证主从设置")
        print("     - 检查BIOS中的磁盘设置")
    
    print("  7. 通用检查：")
    print("     - 检查磁盘连接")
    print("     - 验证电源供应")
    print("     - 检查散热")
    print("     - 更新驱动和固件")
    
    print("  8. 监控和预防：")
    print("     - 设置磁盘监控")
    print("     - 定期检查SMART状态")
    print("     - 实施定期备份")
    print()
    
    print("⚠️  注意：以上为基于日志的离线分析建议，实际操作需在原系统上执行")
    print("================================================================")

if __name__ == "__main__":
    main()
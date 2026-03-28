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

def analyze_fs_corruption(log_dir, keywords=None, start_dt=None, end_dt=None, date_str=None):
    results = {
        "fsck_errors": [],
        "kernel_errors": [],
        "system_errors": [],
        "affected_filesystems": set(),
        "error_types": set(),
        "timeline": []
    }
    
    # Find and analyze fsck logs
    fsck_files = find_files(log_dir, r".*fsck.*")
    for file_path in fsck_files:
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
                    
                    # Check for fsck errors
                    if re.search(r'error|corrupt|damage|inode|superblock|fix|repair', line, re.IGNORECASE):
                        results["fsck_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract filesystem info
                        fs_match = re.search(r'/(dev/\S+)|(\S+):', line)
                        if fs_match:
                            results["affected_filesystems"].add(fs_match.group(1) or fs_match.group(2))
                        
                        # Extract error type
                        if re.search(r'superblock', line, re.IGNORECASE):
                            results["error_types"].add("superblock损坏")
                        elif re.search(r'inode', line, re.IGNORECASE):
                            results["error_types"].add("inode损坏")
                        elif re.search(r'journal', line, re.IGNORECASE):
                            results["error_types"].add("日志损坏")
                        
                        # Extract timestamp if available
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), line.strip()))
                                break
        except:
            pass
    
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
                    
                    # Check for filesystem errors in kernel logs
                    if re.search(r'EXT4-fs error|XFS.*error|BTRFS.*error|filesystem.*corrupt|superblock|inode.*error|JBD2.*error', line, re.IGNORECASE):
                        results["kernel_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract filesystem info
                        fs_match = re.search(r'\((dev/\S+)\)|(\S+):', line)
                        if fs_match:
                            results["affected_filesystems"].add(fs_match.group(1) or fs_match.group(2))
                        
                        # Extract error type
                        if re.search(r'EXT4-fs', line, re.IGNORECASE):
                            results["error_types"].add("EXT4文件系统错误")
                        elif re.search(r'XFS', line, re.IGNORECASE):
                            results["error_types"].add("XFS文件系统错误")
                        elif re.search(r'BTRFS', line, re.IGNORECASE):
                            results["error_types"].add("BTRFS文件系统错误")
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), line.strip()))
                                break
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
                    
                    # Check for filesystem errors in system logs
                    if re.search(r'filesystem.*error|fsck.*error|mount.*error.*filesystem', line, re.IGNORECASE):
                        results["system_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), line.strip()))
                                break
        except:
            pass
    
    return results

def main():
    parser = argparse.ArgumentParser(
        description="File System Corruption Diagnosis Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/
  python3 %(prog)s ./logs/ -k "superblock" "inode"
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
    print(" 文件系统损坏深度分析报告")
    print(" 时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("================================================================")
    print()
    
    results = analyze_fs_corruption(
        args.log_dir, 
        args.keywords, 
        start_dt, 
        end_dt, 
        args.date
    )
    
    # Summary
    print("━━━━ [A] 分析摘要 ━━━━")
    print(f"  受影响文件系统: {', '.join(results['affected_filesystems']) if results['affected_filesystems'] else '未知'}")
    print(f"  错误类型: {', '.join(results['error_types']) if results['error_types'] else '未知'}")
    print(f"  FSCK错误数: {len(results['fsck_errors'])}")
    print(f"  内核错误数: {len(results['kernel_errors'])}")
    print(f"  系统错误数: {len(results['system_errors'])}")
    print()
    
    # FSCK Errors
    if results["fsck_errors"]:
        print("━━━━ [B] FSCK 检查错误 ━━━━")
        for i, error in enumerate(results["fsck_errors"][:20], 1):
            print(f"  {i}. {error}")
        if len(results["fsck_errors"]) > 20:
            print(f"  ... (还有 {len(results['fsck_errors']) - 20} 个错误未显示)")
        print()
    
    # Kernel Errors
    if results["kernel_errors"]:
        print("━━━━ [C] 内核文件系统错误 ━━━━")
        for i, error in enumerate(results["kernel_errors"][:20], 1):
            print(f"  {i}. {error}")
        if len(results["kernel_errors"]) > 20:
            print(f"  ... (还有 {len(results['kernel_errors']) - 20} 个错误未显示)")
        print()
    
    # System Errors
    if results["system_errors"]:
        print("━━━━ [D] 系统日志错误 ━━━━")
        for i, error in enumerate(results["system_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["system_errors"]) > 10:
            print(f"  ... (还有 {len(results['system_errors']) - 10} 个错误未显示)")
        print()
    
    # Timeline
    if results["timeline"]:
        print("━━━━ [E] 时间线分析 ━━━━")
        # Sort by timestamp (simple string sort for now)
        sorted_timeline = sorted(results["timeline"], key=lambda x: x[0])
        for timestamp, event in sorted_timeline[:10]:
            print(f"  [{timestamp}] {event[:100]}...")
        if len(sorted_timeline) > 10:
            print(f"  ... (还有 {len(sorted_timeline) - 10} 个事件未显示)")
        print()
    
    # Recommendations
    print("━━━━ [F] 修复建议 ━━━━")
    print("  1. 立即停止对受影响文件系统的写入操作")
    print("  2. 备份重要数据到其他存储设备")
    
    if "superblock损坏" in results["error_types"]:
        print("  3. 超级块损坏：尝试使用备用超级块恢复")
        print("     - ext4: e2fsck -b 32768 /dev/sdX")
        print("     - xfs: xfs_repair -L /dev/sdX")
    
    if "inode损坏" in results["error_types"]:
        print("  3. inode损坏：运行完整文件系统检查")
        print("     - ext4: e2fsck -y /dev/sdX")
        print("     - xfs: xfs_repair /dev/sdX")
    
    if "EXT4文件系统错误" in results["error_types"]:
        print("  3. EXT4文件系统错误：")
        print("     - e2fsck -p /dev/sdX (自动修复)")
        print("     - e2fsck -y /dev/sdX (交互式修复)")
    
    if "XFS文件系统错误" in results["error_types"]:
        print("  3. XFS文件系统错误：")
        print("     - xfs_repair /dev/sdX")
        print("     - xfs_repair -L /dev/sdX (日志清零，数据可能丢失)")
    
    if "BTRFS文件系统错误" in results["error_types"]:
        print("  3. BTRFS文件系统错误：")
        print("     - btrfs check --repair /dev/sdX (谨慎使用)")
        print("     - btrfs scrub start /dev/sdX")
    
    print("  4. 修复后重新挂载文件系统")
    print("  5. 验证数据完整性")
    print("  6. 考虑定期进行文件系统健康检查")
    print()
    
    print("⚠️  注意：以上为基于日志的离线分析建议，实际操作需在原系统上执行")
    print("================================================================")

if __name__ == "__main__":
    main()
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

def analyze_space_issue(log_dir, keywords=None, start_dt=None, end_dt=None, date_str=None):
    results = {
        "disk_full_errors": [],
        "inode_exhausted": [],
        "quota_exceeded": [],
        "low_space_warnings": [],
        "affected_filesystems": set(),
        "space_usage_patterns": {},
        "timeline": []
    }
    
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
                    
                    # Check for disk full errors
                    if re.search(r'No space left|disk.*full|filesystem.*full', line, re.IGNORECASE):
                        results["disk_full_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract filesystem info
                        fs_match = re.search(r'on\s+(\S+)\s+is|filesystem\s+(\S+)\s+full', line, re.IGNORECASE)
                        if fs_match:
                            fs = fs_match.group(1) or fs_match.group(2)
                            results["affected_filesystems"].add(fs)
                            if fs not in results["space_usage_patterns"]:
                                results["space_usage_patterns"][fs] = {"full_errors": 0, "warnings": 0}
                            results["space_usage_patterns"][fs]["full_errors"] += 1
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"磁盘空间不足: {line.strip()[:80]}"))
                                break
                    
                    # Check for inode exhausted errors
                    elif re.search(r'inode.*exhausted|No space.*inode', line, re.IGNORECASE):
                        results["inode_exhausted"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract filesystem info
                        fs_match = re.search(r'on\s+(\S+)\s+is|filesystem\s+(\S+)\s+inode', line, re.IGNORECASE)
                        if fs_match:
                            fs = fs_match.group(1) or fs_match.group(2)
                            results["affected_filesystems"].add(fs)
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"inode耗尽: {line.strip()[:80]}"))
                                break
                    
                    # Check for quota exceeded errors
                    elif re.search(r'quota.*exceeded|over.*quota', line, re.IGNORECASE):
                        results["quota_exceeded"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract user info
                        user_match = re.search(r'user\s+(\S+)|uid\s+(\d+)', line, re.IGNORECASE)
                        if user_match:
                            results["timeline"].append((datetime.now().strftime("%H:%M:%S"), f"配额超出: 用户 {user_match.group(1) or user_match.group(2)}"))
                    
                    # Check for low space warnings
                    elif re.search(r'low.*space|space.*low|almost.*full', line, re.IGNORECASE):
                        results["low_space_warnings"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract filesystem info
                        fs_match = re.search(r'on\s+(\S+)\s+is|filesystem\s+(\S+)\s+low', line, re.IGNORECASE)
                        if fs_match:
                            fs = fs_match.group(1) or fs_match.group(2)
                            if fs not in results["space_usage_patterns"]:
                                results["space_usage_patterns"][fs] = {"full_errors": 0, "warnings": 0}
                            results["space_usage_patterns"][fs]["warnings"] += 1
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
                    
                    # Check for space related errors in kernel logs
                    if re.search(r'No space left|out of inodes|disk full', line, re.IGNORECASE):
                        results["disk_full_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract filesystem info
                        fs_match = re.search(r'(\S+):\s+No|filesystem\s+(\S+)', line, re.IGNORECASE)
                        if fs_match:
                            fs = fs_match.group(1) or fs_match.group(2)
                            results["affected_filesystems"].add(fs)
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"内核空间错误: {line.strip()[:80]}"))
                                break
        except:
            pass
    
    # Find and analyze df output logs
    df_files = find_files(log_dir, r".*df.*|.*disk.*usage.*")
    for file_path in df_files:
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                for j, line in enumerate(lines, 1):
                    if not is_in_time_range(line, start_dt, end_dt, date_str):
                        continue
                    
                    # Parse df output
                    if re.search(r'^\s*\d+%\s+', line):
                        parts = line.split()
                        if len(parts) >= 5:
                            usage = parts[4]
                            filesystem = parts[0]
                            try:
                                usage_pct = int(usage.replace('%', ''))
                                if usage_pct > 90:
                                    results["low_space_warnings"].append(f"{os.path.basename(file_path)}:{j}: {line.strip()}")
                                    results["affected_filesystems"].add(filesystem)
                            except:
                                pass
        except:
            pass
    
    return results

def main():
    parser = argparse.ArgumentParser(
        description="Space Issue Diagnosis Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/
  python3 %(prog)s ./logs/ -k "full" "space"
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
    print(" 空间问题深度分析报告")
    print(" 时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("================================================================")
    print()
    
    results = analyze_space_issue(
        args.log_dir, 
        args.keywords, 
        start_dt, 
        end_dt, 
        args.date
    )
    
    # Summary
    print("━━━━ [A] 分析摘要 ━━━━")
    print(f"  受影响文件系统: {', '.join(results['affected_filesystems']) if results['affected_filesystems'] else '未知'}")
    print(f"  磁盘空间不足错误数: {len(results['disk_full_errors'])}")
    print(f"  inode耗尽错误数: {len(results['inode_exhausted'])}")
    print(f"  配额超出错误数: {len(results['quota_exceeded'])}")
    print(f"  低空间警告数: {len(results['low_space_warnings'])}")
    print()
    
    # Space usage patterns
    if results["space_usage_patterns"]:
        print("━━━━ [B] 空间使用模式分析 ━━━━")
        for fs, patterns in results["space_usage_patterns"].items():
            full_errors = patterns["full_errors"]
            warnings = patterns["warnings"]
            severity = "⚠️ " if full_errors > 0 else ""
            print(f"  {severity}{fs}:")
            print(f"    - 空间不足错误: {full_errors}")
            print(f"    - 低空间警告: {warnings}")
        print()
    
    # Disk Full Errors
    if results["disk_full_errors"]:
        print("━━━━ [C] 磁盘空间不足错误日志 ━━━━")
        for i, error in enumerate(results["disk_full_errors"][:15], 1):
            print(f"  {i}. {error}")
        if len(results["disk_full_errors"]) > 15:
            print(f"  ... (还有 {len(results['disk_full_errors']) - 15} 个错误未显示)")
        print()
    
    # Inode Exhausted Errors
    if results["inode_exhausted"]:
        print("━━━━ [D] inode耗尽错误日志 ━━━━")
        for i, error in enumerate(results["inode_exhausted"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["inode_exhausted"]) > 10:
            print(f"  ... (还有 {len(results['inode_exhausted']) - 10} 个错误未显示)")
        print()
    
    # Quota Exceeded Errors
    if results["quota_exceeded"]:
        print("━━━━ [E] 配额超出错误日志 ━━━━")
        for i, error in enumerate(results["quota_exceeded"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["quota_exceeded"]) > 10:
            print(f"  ... (还有 {len(results['quota_exceeded']) - 10} 个错误未显示)")
        print()
    
    # Low Space Warnings
    if results["low_space_warnings"]:
        print("━━━━ [F] 低空间警告日志 ━━━━")
        for i, warning in enumerate(results["low_space_warnings"][:10], 1):
            print(f"  {i}. {warning}")
        if len(results["low_space_warnings"]) > 10:
            print(f"  ... (还有 {len(results['low_space_warnings']) - 10} 个警告未显示)")
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
    
    if results["disk_full_errors"]:
        print("  1. 磁盘空间不足：")
        print("     - 立即清理临时文件: rm -rf /tmp/*")
        print("     - 查找大文件: find / -type f -size +100M")
        print("     - 清理日志文件: journalctl --vacuum-time=7d")
        print("     - 检查并清理软件包缓存")
    
    if results["inode_exhausted"]:
        print("  2. inode耗尽：")
        print("     - 查找小文件目录: find / -type d -exec ls -la {} \; | grep '^d' | wc -l")
        print("     - 清理大量小文件")
        print("     - 考虑重新格式化文件系统以增加inode数量")
    
    if results["quota_exceeded"]:
        print("  3. 配额超出：")
        print("     - 检查用户配额: quota -u <用户名>")
        print("     - 调整配额限制: edquota -u <用户名>")
        print("     - 清理用户文件")
    
    if results["low_space_warnings"]:
        print("  4. 低空间警告：")
        print("     - 监控空间使用趋势")
        print("     - 设置自动清理脚本")
        print("     - 考虑扩展存储容量")
    
    print("  5. 通用检查：")
    print("     - 检查磁盘使用情况: df -h")
    print("     - 检查inode使用情况: df -i")
    print("     - 检查挂载点空间")
    
    print("  6. 预防措施：")
    print("     - 设置磁盘空间监控告警")
    print("     - 定期清理无用文件")
    print("     - 实施存储容量规划")
    
    print("  7. 紧急处理：")
    print("     - 如果系统无法启动，进入救援模式")
    print("     - 使用live CD/USB清理空间")
    print("     - 考虑临时挂载外部存储")
    print()
    
    print("⚠️  注意：以上为基于日志的离线分析建议，实际操作需在原系统上执行")
    print("================================================================")

if __name__ == "__main__":
    main()
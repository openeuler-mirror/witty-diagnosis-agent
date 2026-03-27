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

def analyze_mount_error(log_dir, keywords=None, start_dt=None, end_dt=None, date_str=None):
    results = {
        "systemd_errors": [],
        "kernel_errors": [],
        "fstab_issues": [],
        "device_issues": [],
        "filesystem_issues": [],
        "affected_mounts": set(),
        "timeline": []
    }
    
    # Find and analyze systemd logs
    systemd_files = find_files(log_dir, r".*systemd.*|.*boot.*|.*journal.*")
    for file_path in systemd_files:
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
                    
                    # Check for mount errors in systemd logs
                    if re.search(r'mount.*failed|Failed to mount|Dependency failed.*mount|special mount.*failed', line, re.IGNORECASE):
                        results["systemd_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract mount point info
                        mount_match = re.search(r'mount.*(\S+)\s+on\s+(\S+)', line, re.IGNORECASE)
                        if mount_match:
                            results["affected_mounts"].add(mount_match.group(2))
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"systemd挂载错误: {line.strip()[:80]}"))
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
                    
                    # Check for mount errors in kernel logs
                    if re.search(r'mount.*error|VFS.*error|unknown filesystem|wrong fs type|bad option|device.*not found', line, re.IGNORECASE):
                        results["kernel_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract device/filesystem info
                        if re.search(r'device.*not found|no such device', line, re.IGNORECASE):
                            device_match = re.search(r'device\s+(\S+)', line, re.IGNORECASE)
                            if device_match:
                                results["device_issues"].append(f"设备不存在: {device_match.group(1)}")
                        
                        if re.search(r'unknown filesystem|wrong fs type', line, re.IGNORECASE):
                            fs_match = re.search(r'type\s+(\S+)|filesystem\s+(\S+)', line, re.IGNORECASE)
                            if fs_match:
                                results["filesystem_issues"].append(f"文件系统类型错误: {fs_match.group(1) or fs_match.group(2)}")
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"内核挂载错误: {line.strip()[:80]}"))
                                break
        except:
            pass
    
    # Find and analyze fstab logs
    fstab_files = find_files(log_dir, r".*fstab.*")
    for file_path in fstab_files:
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
                # Check for common fstab issues
                lines = content.split('\n')
                for j, line in enumerate(lines, 1):
                    line = line.strip()
                    if line.startswith('#') or not line:
                        continue
                    
                    # Parse fstab line
                    parts = line.split()
                    if len(parts) >= 4:
                        device = parts[0]
                        mountpoint = parts[1]
                        fstype = parts[2]
                        options = parts[3]
                        
                        # Check for UUID format
                        if device.startswith('UUID='):
                            uuid = device[5:]
                            results["fstab_issues"].append(f"使用UUID挂载: {uuid} -> {mountpoint}")
                        
                        # Check for device path
                        elif device.startswith('/dev/'):
                            results["fstab_issues"].append(f"使用设备路径挂载: {device} -> {mountpoint}")
                        
                        # Check for problematic options
                        if 'noauto' in options:
                            results["fstab_issues"].append(f"挂载点 {mountpoint} 设置为 noauto，需要手动挂载")
                        
                        if 'nofail' in options:
                            results["fstab_issues"].append(f"挂载点 {mountpoint} 设置为 nofail，挂载失败不会阻止启动")
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
                    
                    # Check for mount issues in system logs
                    if re.search(r'cannot mount|mount.*problem|filesystem.*not mounted', line, re.IGNORECASE):
                        results["systemd_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"系统挂载问题: {line.strip()[:80]}"))
                                break
        except:
            pass
    
    return results

def main():
    parser = argparse.ArgumentParser(
        description="Mount Error Diagnosis Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/
  python3 %(prog)s ./logs/ -k "failed" "error"
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
    print(" 挂载错误深度分析报告")
    print(" 时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("================================================================")
    print()
    
    results = analyze_mount_error(
        args.log_dir, 
        args.keywords, 
        start_dt, 
        end_dt, 
        args.date
    )
    
    # Summary
    print("━━━━ [A] 分析摘要 ━━━━")
    print(f"  受影响挂载点: {', '.join(results['affected_mounts']) if results['affected_mounts'] else '未知'}")
    print(f"  systemd错误数: {len(results['systemd_errors'])}")
    print(f"  内核错误数: {len(results['kernel_errors'])}")
    print(f"  fstab问题数: {len(results['fstab_issues'])}")
    print(f"  设备问题数: {len(results['device_issues'])}")
    print(f"  文件系统问题数: {len(results['filesystem_issues'])}")
    print()
    
    # Systemd Errors
    if results["systemd_errors"]:
        print("━━━━ [B] systemd 挂载错误 ━━━━")
        for i, error in enumerate(results["systemd_errors"][:15], 1):
            print(f"  {i}. {error}")
        if len(results["systemd_errors"]) > 15:
            print(f"  ... (还有 {len(results['systemd_errors']) - 15} 个错误未显示)")
        print()
    
    # Kernel Errors
    if results["kernel_errors"]:
        print("━━━━ [C] 内核挂载错误 ━━━━")
        for i, error in enumerate(results["kernel_errors"][:15], 1):
            print(f"  {i}. {error}")
        if len(results["kernel_errors"]) > 15:
            print(f"  ... (还有 {len(results['kernel_errors']) - 15} 个错误未显示)")
        print()
    
    # Fstab Issues
    if results["fstab_issues"]:
        print("━━━━ [D] fstab 配置问题 ━━━━")
        for i, issue in enumerate(results["fstab_issues"], 1):
            print(f"  {i}. {issue}")
        print()
    
    # Device Issues
    if results["device_issues"]:
        print("━━━━ [E] 设备问题 ━━━━")
        for i, issue in enumerate(results["device_issues"], 1):
            print(f"  ⚠️  {i}. {issue}")
        print()
    
    # Filesystem Issues
    if results["filesystem_issues"]:
        print("━━━━ [F] 文件系统问题 ━━━━")
        for i, issue in enumerate(results["filesystem_issues"], 1):
            print(f"  ⚠️  {i}. {issue}")
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
    print("  1. 检查 /etc/fstab 配置文件")
    print("     - 确认设备路径或UUID正确")
    print("     - 检查文件系统类型")
    print("     - 验证挂载选项")
    
    if results["device_issues"]:
        print("  2. 设备不存在问题：")
        print("     - 运行 lsblk 确认设备是否存在")
        print("     - 检查磁盘是否被识别")
        print("     - 验证分区表")
        print("     - 检查 RAID 阵列状态（如适用）")
    
    if results["filesystem_issues"]:
        print("  3. 文件系统类型错误：")
        print("     - 运行 blkid 确认文件系统类型")
        print("     - 检查是否格式化为正确的文件系统")
        print("     - 验证文件系统是否损坏")
    
    if results["systemd_errors"]:
        print("  4. systemd 挂载失败：")
        print("     - 检查 systemd 服务状态: systemctl status <mount-unit>")
        print("     - 查看详细日志: journalctl -u <mount-unit>")
        print("     - 检查依赖关系")
    
    print("  5. 手动测试挂载：")
    print("     - mount /dev/sdX /mnt/test")
    print("     - 检查错误信息")
    print("     - 验证权限和选项")
    
    print("  6. 修复后测试：")
    print("     - 重新加载 systemd: systemctl daemon-reload")
    print("     - 重启挂载服务")
    print("     - 验证挂载状态")
    print()
    
    print("⚠️  注意：以上为基于日志的离线分析建议，实际操作需在原系统上执行")
    print("================================================================")

if __name__ == "__main__":
    main()
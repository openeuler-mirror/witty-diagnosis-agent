#!/usr/bin/env python3
import os
import sys
import re
import argparse
from datetime import datetime

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
    if date_str:
        if date_str in line:
            return True
        if not start_dt and not end_dt:
            return False
    
    if start_dt or end_dt:
        for pattern in TIME_PATTERNS:
            match = re.search(pattern, line)
            if match:
                ts_str = match.group(1)
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
        return False
        
    return True

def classify_scene(log_dir, keywords=None, start_dt=None, end_dt=None, date_str=None):
    kernel_log = ""
    systemd_log = ""
    fsck_log = ""
    sysmsg_log = ""
    smart_log = ""
    
    ibmc_dir = os.path.join(log_dir, "ibmc_logs")
    infocollect_dir = os.path.join(log_dir, "infocollect_logs")
    messages_dir = os.path.join(log_dir, "messages")
    
    kernel_files = find_files(log_dir, r".*dmesg.*")
    for file in kernel_files:
        kernel_log += read_log_content(file)
    
    systemd_files = find_files(log_dir, r".*systemd.*|.*boot.*")
    for file in systemd_files:
        systemd_log += read_log_content(file)
    
    fsck_files = find_files(log_dir, r".*fsck.*")
    for file in fsck_files:
        fsck_log += read_log_content(file)
    
    sysmsg_files = find_files(log_dir, r".*messages.*|.*syslog.*")
    for file in sysmsg_files:
        sysmsg_log += read_log_content(file)
    
    smart_files = find_files(log_dir, r".*smart.*|disk_smart.*")
    for file in smart_files:
        smart_log += read_log_content(file)
    
    scene = "UNKNOWN"
    confidence = "LOW"
    reasons = []
    evidence = []
    
    def check_line(line, pattern):
        if not is_in_time_range(line, start_dt, end_dt, date_str):
            return False
        if keywords:
            for keyword in keywords:
                if keyword.lower() in line.lower():
                    return True
            return False
        return True
    
    if smart_log:
        lines = smart_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'SMART.*FAILED|FAILING|Critical', line, re.IGNORECASE):
                    scene = "DISK_FAILURE"
                    confidence = "HIGH"
                    reasons.append("SMART状态显示磁盘故障或即将故障")
                    evidence.append(line.strip()[:200])
                    break
                elif re.search(r'Reallocated_Sector_Ct.*[1-9]|Current_Pending_Sector.*[1-9]', line, re.IGNORECASE):
                    scene = "DISK_FAILURE"
                    confidence = "MEDIUM"
                    reasons.append("SMART检测到坏扇区")
                    evidence.append(line.strip()[:200])
                    break
    
    if kernel_log and scene == "UNKNOWN":
        lines = kernel_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'hardware error|MCE|Machine Check|DRDY ERR|UNC', line, re.IGNORECASE):
                    scene = "DISK_FAILURE"
                    confidence = "HIGH"
                    reasons.append("内核日志检测到硬件错误")
                    evidence.append(line.strip()[:200])
                    break
    
    if fsck_log and scene == "UNKNOWN":
        lines = fsck_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'error|corrupt|damage|inode|superblock|fix', line, re.IGNORECASE):
                    scene = "FS_CORRUPTION"
                    confidence = "HIGH"
                    reasons.append("fsck检测到文件系统错误")
                    evidence.append(line.strip()[:200])
                    break
    
    if kernel_log and scene == "UNKNOWN":
        lines = kernel_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'EXT4-fs error|XFS.*error|BTRFS.*error|filesystem.*corrupt|superblock|inode.*error', line, re.IGNORECASE):
                    scene = "FS_CORRUPTION"
                    confidence = "HIGH"
                    reasons.append("内核日志报告文件系统错误")
                    evidence.append(line.strip()[:200])
                    break
    
    if kernel_log and scene == "UNKNOWN":
        lines = kernel_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'I/O error|block.*error|timeout.*I/O|Buffer I/O error|read-error|write-error', line, re.IGNORECASE):
                    scene = "IO_ERROR"
                    confidence = "HIGH"
                    reasons.append("内核日志检测到I/O错误")
                    evidence.append(line.strip()[:200])
                    break
    
    if systemd_log and scene == "UNKNOWN":
        lines = systemd_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'mount.*failed|Failed to mount|Dependency failed.*mount|special mount', line, re.IGNORECASE):
                    scene = "MOUNT_ERROR"
                    confidence = "HIGH"
                    reasons.append("systemd启动日志显示挂载失败")
                    evidence.append(line.strip()[:200])
                    break
    
    if kernel_log and scene == "UNKNOWN":
        lines = kernel_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'mount.*error|VFS.*error|unknown filesystem|wrong fs type|bad option', line, re.IGNORECASE):
                    scene = "MOUNT_ERROR"
                    confidence = "MEDIUM"
                    reasons.append("内核日志报告挂载错误")
                    evidence.append(line.strip()[:200])
                    break
    
    if sysmsg_log and scene == "UNKNOWN":
        lines = sysmsg_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'No space left|disk.*full|inode.*exhausted|cannot create.*full', line, re.IGNORECASE):
                    scene = "SPACE_ISSUE"
                    confidence = "HIGH"
                    reasons.append("系统日志显示磁盘空间不足")
                    evidence.append(line.strip()[:200])
                    break
    
    if kernel_log and scene == "UNKNOWN":
        lines = kernel_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'No space left|out of inodes|disk full', line, re.IGNORECASE):
                    scene = "SPACE_ISSUE"
                    confidence = "MEDIUM"
                    reasons.append("内核日志报告空间不足")
                    evidence.append(line.strip()[:200])
                    break
    
    if sysmsg_log and scene == "UNKNOWN":
        lines = sysmsg_log.split('\n')
        for line in lines:
            if check_line(line, None):
                if re.search(r'Permission denied|access denied|operation not permitted', line, re.IGNORECASE):
                    scene = "PERMISSION_ISSUE"
                    confidence = "MEDIUM"
                    reasons.append("系统日志显示权限拒绝错误")
                    evidence.append(line.strip()[:200])
                    break
    
    return scene, confidence, reasons, evidence

def main():
    parser = argparse.ArgumentParser(
        description="File System Fault Scene Classifier",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/
  python3 %(prog)s ./logs/ -k "I/O error" "corrupt"
  python3 %(prog)s ./logs/ -d "Mar 16"
  python3 %(prog)s ./logs/ -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
        """
    )
    
    parser.add_argument("log_dir", help="Root directory containing 'ibmc_logs', 'infocollect_logs', and 'messages' folders")
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
    print(" 场景分类结果")
    print(" 时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("================================================================")
    print()
    
    scene, confidence, reasons, evidence = classify_scene(
        args.log_dir, 
        args.keywords, 
        start_dt, 
        end_dt, 
        args.date
    )
    
    print(f"  🏷️  场景标签  : {scene}")
    print(f"  📊 置信度    : {confidence}")
    print()
    
    print("  判断依据：")
    if reasons:
        for reason in reasons:
            print(f"    • {reason}")
    else:
        print("    • 未命中任何自动规则，需人工分析")
    print()
    
    if evidence:
        print("  关键证据：")
        for i, e in enumerate(evidence[:3], 1):
            print(f"    [{i}] {e}")
        print()
    
    print("================================================================")
    print(" 下一步建议")
    print("================================================================")
    
    if scene == "FS_CORRUPTION":
        print("  执行：python3 scripts/diagnose_messages.py <log_dir>/messages -k \"EXT4-fs error\" \"XFS.*error\"")
        print("  重点：fsck结果分析 → 损坏类型定位 → 修复方案评估")
    elif scene == "DISK_FAILURE":
        print("  ⚠️  硬件故障优先：停止写入操作！")
        print("  执行：python3 scripts/diagnose_infocollect.py <log_dir>/infocollect_logs")
        print("  重点：SMART指标分析 → 确认故障程度 → 数据备份 → 更换磁盘")
    elif scene == "MOUNT_ERROR":
        print("  执行：python3 scripts/diagnose_messages.py <log_dir>/messages -k \"mount\" \"failed\"")
        print("  重点：fstab配置检查 → 设备UUID对比 → 挂载选项验证")
    elif scene == "IO_ERROR":
        print("  执行：python3 scripts/diagnose_messages.py <log_dir>/messages -k \"I/O error\"")
        print("  重点：I/O错误定位 → 受影响设备确认 → 根因分析（硬件/驱动/文件系统）")
    elif scene == "PERMISSION_ISSUE":
        print("  执行：python3 scripts/diagnose_messages.py <log_dir>/messages -k \"Permission denied\"")
        print("  重点：权限配置检查 → SELinux/AppArmor状态 → 用户/组权限")
    elif scene == "SPACE_ISSUE":
        print("  执行：python3 scripts/diagnose_messages.py <log_dir>/messages -k \"No space left\"")
        print("  重点：空间使用分析 → 大文件定位 → 清理建议")
    else:  # UNKNOWN
        print("  ⚠️  无法自动判断，建议手动执行日志分析：")
        print("  执行：python3 scripts/diagnose_summary.py <log_dir>")
        print("  或人工审查各日志文件中的ERROR、FAIL、WARNING关键词")
    
    print()
    print("================================================================")
    
    try:
        with open("/tmp/fs_diagnosis_scene.conf", "w") as f:
            f.write(f"SCENE={scene}\n")
            f.write(f"CONFIDENCE={confidence}\n")
        print("场景标签已保存至 /tmp/fs_diagnosis_scene.conf")
    except:
        pass

if __name__ == "__main__":
    main()

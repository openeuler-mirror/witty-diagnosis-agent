#!/usr/bin/env python3
import os
import sys
import re
import argparse
from datetime import datetime

def find_files(root_dir, pattern):
    """Recursively find files matching the pattern."""
    matched_files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if re.search(pattern, filename, re.IGNORECASE):
                matched_files.append(os.path.join(dirpath, filename))
    return matched_files

def parse_os_logs(file_paths):
    issues = []
    # Regular expressions for L5 OS layer IO errors, L6 business logic errors, and File System states
    patterns = {
        # File System States - Normal
        'fs_normal_mount': re.compile(r'(EXT4-fs \([^)]+\): mounted filesystem|XFS \([^)]+\): Mounting V[0-9]+ Filesystem)'),
        
        # File System States - Recovery & Repair
        'fs_recovery': re.compile(r'(EXT4-fs \([^)]+\): recovery complete|XFS \([^)]+\): Ending clean mount|recovering journal)'),
        'fs_manual_repair': re.compile(r'(fsck\.ext4|xfs_repair)'),

        # L5 OS errors & File System States - Abnormal (I/O errors but not yet failed)
        'io_error_dev': re.compile(r'I/O error, dev (sd[a-z]+)'),
        'blk_update_request': re.compile(r'blk_update_request: I/O error'),
        'end_request': re.compile(r'end_request: I/O error'),
        'buffer_io_error': re.compile(r'Buffer I/O error on dev (sd[a-z]+)'),
        'reset_link': re.compile(r'(reset link|hard resetting link)'),
        'ncq_error': re.compile(r'failed command: READ FPDMA QUEUED'),
        'scsi_error': re.compile(r'SCSI error: return code = 0x08000002'),
        'soft_error': re.compile(r'hostbyte=DID_SOFT_ERROR'),
        
        # File System States - Failure (Data protection actions: Read-only, Shutdown, Magic number error)
        'fs_error': re.compile(r'(EXT4-fs error|XFS: .* I/O error)'),
        'remount_ro': re.compile(r'Remounting filesystem read-only'),
        'xfs_force_shutdown': re.compile(r'xfs_do_force_shutdown'),
        'fs_corruption': re.compile(r'Corruption of in-memory data detected'),
        'fs_mount_fail': re.compile(r'(Invalid superblock magic number|can\'t read superblock)'),

        # L6 Business/Service errors
        'osd_service_exit': re.compile(r'51001'),
        'osd_io_blocked': re.compile(r'(51036|51635)'),
        'media_not_present': re.compile(r'51455'),
        'nvme_fault': re.compile(r'51450'),
        'fs_partition_anomaly': re.compile(r'(51837|CMC1301023)'),
        'system_disk_util': re.compile(r'check_sda_util'),
        'blocks_throughput': re.compile(r'(blocks_sent_to_initiator|blocks_recv_to_initiator)')
    }

    # Regex to extract timestamp from messages/syslog/secure format (e.g., "Apr  2 10:15:25")
    # Or from dmesg format (e.g., "[12345.678901]")
    # Or from some history files format
    timestamp_pattern = re.compile(r'^([A-Z][a-z]{2}\s+\d+\s+\d{2}:\d{2}:\d{2}|\[\s*\d+\.\d+\])')

    for file_path in file_paths:
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    for key, pattern in patterns.items():
                        match = pattern.search(line)
                        if match:
                            ts_match = timestamp_pattern.search(line)
                            timestamp = ts_match.group(1) if ts_match else "Unknown"
                            
                            issues.append({
                                'type': key,
                                'timestamp': timestamp,
                                'matched_text': match.group(0),
                                'full_line': line.strip(),
                                'file_path': file_path,
                                'line_num': line_num
                            })
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
            
    return issues

def evaluate_issues(issues):
    # Group issues by type
    summary = {}
    
    # State mapping
    state_mapping = {
        'fs_normal_mount': '正常 (Normal)',
        'fs_recovery': '恢复 (Recovery)',
        'fs_manual_repair': '恢复 (Recovery) - 人工介入',
        'io_error_dev': '异常 (Abnormal)',
        'blk_update_request': '异常 (Abnormal)',
        'end_request': '异常 (Abnormal)',
        'buffer_io_error': '异常 (Abnormal)',
        'reset_link': '异常 (Abnormal)',
        'ncq_error': '异常 (Abnormal)',
        'scsi_error': '异常 (Abnormal)',
        'soft_error': '异常 (Abnormal)',
        'fs_error': '故障 (Failure)',
        'remount_ro': '故障 (Failure) - 只读保护',
        'xfs_force_shutdown': '故障 (Failure) - 强制关闭',
        'fs_corruption': '故障 (Failure) - 数据损坏',
        'fs_mount_fail': '故障 (Failure) - 挂载失败'
    }

    for issue in issues:
        t = issue['type']
        
        # Add file system state context
        issue['fs_state'] = state_mapping.get(t, '业务报错/其他')
        
        # Filter out normal events entirely from the summary and timeline
        if issue['fs_state'] == '正常 (Normal)':
            continue

        if t not in summary:
            summary[t] = []
        summary[t].append(issue)
        
    return summary

def main():
    parser = argparse.ArgumentParser(description="Automated OS Layer I/O Error Diagnosis Tool")
    parser.add_argument("log_path", help="Root directory of the logs to analyze (e.g., infocollect_logs)")
    args = parser.parse_args()

    root_dir = args.log_path
    if not os.path.exists(root_dir):
        print(f"Error: Directory {root_dir} does not exist.")
        sys.exit(1)

    # Find dmesg, messages, secure and bash_history files
    log_files = find_files(root_dir, r'(dmesg|messages|secure|bash_history)')
    print(f"Found {len(log_files)} OS log files to analyze.")
    
    issues = parse_os_logs(log_files)
    summary = evaluate_issues(issues)

    timestamp_str = datetime.now().strftime('%Y%m%d_%H%M%S')
    import random
    import string
    random_str = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
    output_file = f"/tmp/os_io_error_diagnosis_report_{timestamp_str}_{random_str}.txt"
    
    with open(output_file, "w") as out:
        out.write("=============================================\n")
        out.write("  OS层 I/O 错误与文件系统诊断报告\n")
        out.write("=============================================\n")
        out.write(f"检测执行时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        out.write(f"日志路径：{root_dir}\n\n")

        if not summary:
            out.write("未发现 OS 层 I/O 错误或文件系统异常。\n")
        else:
            out.write("发现以下类型的系统错误：\n")
            out.write("-" * 80 + "\n")
            for t, items in summary.items():
                out.write(f"【错误类型/检测项】 {t} (共 {len(items)} 条)\n")
                out.write(f"  ▶ 关联状态：{items[0].get('fs_state', 'N/A')}\n")
                
                # Sort items by timestamp (roughly, by line number if timestamp is relative)
                items.sort(key=lambda x: x['line_num'])
                
                # Show up to 3 examples
                for item in items[:3]:
                    out.write(f"  - 时间: {item['timestamp']}\n")
                    out.write(f"    文件: {item['file_path']} (行 {item['line_num']})\n")
                    out.write(f"    内容: {item['full_line']}\n")
                if len(items) > 3:
                    out.write(f"  ... 还有 {len(items) - 3} 条类似记录 (包含更早或更晚的事件) ...\n")
                out.write("\n")
                
        # Timeline reconstruction
        # Collect all valid issues from summary to build timeline (since normal events are filtered out)
        valid_issues = []
        for items in summary.values():
            valid_issues.extend(items)
            
        if valid_issues:
            out.write("=============================================\n")
            out.write("  文件系统状态演进与时间线 (Timeline)\n")
            out.write("=============================================\n")
            
            # Sort by file path first (to group by file), then line number to keep chronological order within files
            # A more robust sorting would parse the actual timestamp strings, but this works well for logs
            issues_sorted = sorted(valid_issues, key=lambda x: (x['file_path'], x['line_num']))
            
            # If we still have too many events, cap them at a reasonable limit
            if len(issues_sorted) > 50:
                # Keep first 25 and last 25 events to show the beginning and end of the sequence
                display_events = issues_sorted[:25] + issues_sorted[-25:]
                
                # Output first half
                for item in issues_sorted[:25]:
                    out.write(f"[{item['timestamp']}] [{item['fs_state']}] {item['matched_text']} (文件: {os.path.basename(item['file_path'])})\n")
                
                out.write(f"\n... 已折叠 {len(issues_sorted) - 50} 条相似记录 ...\n\n")
                
                # Output second half
                for item in issues_sorted[-25:]:
                    out.write(f"[{item['timestamp']}] [{item['fs_state']}] {item['matched_text']} (文件: {os.path.basename(item['file_path'])})\n")
            else:
                for item in issues_sorted:
                    out.write(f"[{item['timestamp']}] [{item['fs_state']}] {item['matched_text']} (文件: {os.path.basename(item['file_path'])})\n")

    print(f"诊断完成。结果已输出至 {output_file}")

if __name__ == "__main__":
    main()

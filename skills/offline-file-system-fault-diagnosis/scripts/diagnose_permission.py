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
                fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
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

def analyze_permission_issue(log_dir, keywords=None, start_dt=None, end_dt=None, date_str=None):
    results = {
        "permission_denied": [],
        "access_denied": [],
        "operation_not_permitted": [],
        "selinux_errors": [],
        "apparmor_errors": [],
        "affected_users": set(),
        "affected_files": set(),
        "affected_processes": set(),
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
                    
                    # Check for permission denied errors
                    if re.search(r'Permission denied', line, re.IGNORECASE):
                        results["permission_denied"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract user info
                        user_match = re.search(r'user=(\S+)', line, re.IGNORECASE)
                        if user_match:
                            results["affected_users"].add(user_match.group(1))
                        
                        # Extract file info
                        file_match = re.search(r'path=(\S+)|file=(\S+)', line, re.IGNORECASE)
                        if file_match:
                            results["affected_files"].add(file_match.group(1) or file_match.group(2))
                        
                        # Extract process info
                        process_match = re.search(r'pid=(\d+)|comm=(\S+)', line, re.IGNORECASE)
                        if process_match:
                            results["affected_processes"].add(process_match.group(1) or process_match.group(2))
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"权限拒绝: {line.strip()[:80]}"))
                                break
                    
                    # Check for access denied errors
                    elif re.search(r'Access denied', line, re.IGNORECASE):
                        results["access_denied"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract user info
                        user_match = re.search(r'user=(\S+)', line, re.IGNORECASE)
                        if user_match:
                            results["affected_users"].add(user_match.group(1))
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"访问拒绝: {line.strip()[:80]}"))
                                break
                    
                    # Check for operation not permitted errors
                    elif re.search(r'Operation not permitted', line, re.IGNORECASE):
                        results["operation_not_permitted"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract process info
                        process_match = re.search(r'pid=(\d+)', line, re.IGNORECASE)
                        if process_match:
                            results["affected_processes"].add(process_match.group(1))
                        
                        # Extract timestamp
                        for pattern in TIME_PATTERNS:
                            ts_match = re.search(pattern, line)
                            if ts_match:
                                results["timeline"].append((ts_match.group(1), f"操作不允许: {line.strip()[:80]}"))
                                break
                    
                    # Check for SELinux errors
                    elif re.search(r'SELinux.*denied|avc.*denied', line, re.IGNORECASE):
                        results["selinux_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract SELinux context
                        context_match = re.search(r'scontext=(\S+)|tcontext=(\S+)', line, re.IGNORECASE)
                        if context_match:
                            results["timeline"].append((datetime.now().strftime("%H:%M:%S"), f"SELinux拒绝: {context_match.group(1) or context_match.group(2)}"))
                    
                    # Check for AppArmor errors
                    elif re.search(r'AppArmor.*denied', line, re.IGNORECASE):
                        results["apparmor_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract AppArmor profile
                        profile_match = re.search(r'profile=(\S+)', line, re.IGNORECASE)
                        if profile_match:
                            results["timeline"].append((datetime.now().strftime("%H:%M:%S"), f"AppArmor拒绝: {profile_match.group(1)}"))
        except:
            pass
    
    # Find and analyze audit logs
    audit_files = find_files(log_dir, r".*audit.*|.*secure.*")
    for file_path in audit_files:
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
                    
                    # Check for audit permission errors
                    if re.search(r'type=AVC|type=SYSCALL.*denied', line, re.IGNORECASE):
                        results["selinux_errors"].append(f"{os.path.basename(file_path)}:{i}: {line.strip()}")
                        
                        # Extract audit info
                        pid_match = re.search(r'pid=(\d+)', line, re.IGNORECASE)
                        if pid_match:
                            results["affected_processes"].add(pid_match.group(1))
        except:
            pass
    
    return results

def main():
    parser = argparse.ArgumentParser(
        description="Permission Issue Diagnosis Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/
  python3 %(prog)s ./logs/ -k "denied" "permission"
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
    print(" 权限问题深度分析报告")
    print(" 时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("================================================================")
    print()
    
    results = analyze_permission_issue(
        args.log_dir, 
        args.keywords, 
        start_dt, 
        end_dt, 
        args.date
    )
    
    # Summary
    print("━━━━ [A] 分析摘要 ━━━━")
    print(f"  受影响用户: {', '.join(results['affected_users']) if results['affected_users'] else '未知'}")
    print(f"  受影响文件: {', '.join(results['affected_files']) if results['affected_files'] else '未知'}")
    print(f"  受影响进程: {', '.join(results['affected_processes']) if results['affected_processes'] else '未知'}")
    print(f"  权限拒绝错误数: {len(results['permission_denied'])}")
    print(f"  访问拒绝错误数: {len(results['access_denied'])}")
    print(f"  操作不允许错误数: {len(results['operation_not_permitted'])}")
    print(f"  SELinux错误数: {len(results['selinux_errors'])}")
    print(f"  AppArmor错误数: {len(results['apparmor_errors'])}")
    print()
    
    # Permission Denied Errors
    if results["permission_denied"]:
        print("━━━━ [B] 权限拒绝错误日志 ━━━━")
        for i, error in enumerate(results["permission_denied"][:15], 1):
            print(f"  {i}. {error}")
        if len(results["permission_denied"]) > 15:
            print(f"  ... (还有 {len(results['permission_denied']) - 15} 个错误未显示)")
        print()
    
    # Access Denied Errors
    if results["access_denied"]:
        print("━━━━ [C] 访问拒绝错误日志 ━━━━")
        for i, error in enumerate(results["access_denied"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["access_denied"]) > 10:
            print(f"  ... (还有 {len(results['access_denied']) - 10} 个错误未显示)")
        print()
    
    # Operation Not Permitted Errors
    if results["operation_not_permitted"]:
        print("━━━━ [D] 操作不允许错误日志 ━━━━")
        for i, error in enumerate(results["operation_not_permitted"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["operation_not_permitted"]) > 10:
            print(f"  ... (还有 {len(results['operation_not_permitted']) - 10} 个错误未显示)")
        print()
    
    # SELinux Errors
    if results["selinux_errors"]:
        print("━━━━ [E] SELinux 错误日志 ━━━━")
        for i, error in enumerate(results["selinux_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["selinux_errors"]) > 10:
            print(f"  ... (还有 {len(results['selinux_errors']) - 10} 个错误未显示)")
        print()
    
    # AppArmor Errors
    if results["apparmor_errors"]:
        print("━━━━ [F] AppArmor 错误日志 ━━━━")
        for i, error in enumerate(results["apparmor_errors"][:10], 1):
            print(f"  {i}. {error}")
        if len(results["apparmor_errors"]) > 10:
            print(f"  ... (还有 {len(results['apparmor_errors']) - 10} 个错误未显示)")
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
    
    if results["permission_denied"]:
        print("  1. 权限拒绝问题：")
        print("     - 检查文件权限: ls -la <文件路径>")
        print("     - 检查目录权限")
        print("     - 验证用户和组所有权")
    
    if results["access_denied"]:
        print("  2. 访问拒绝问题：")
        print("     - 检查访问控制列表 (ACL): getfacl <文件路径>")
        print("     - 验证用户组成员资格")
        print("     - 检查特殊权限位 (setuid, setgid, sticky)")
    
    if results["selinux_errors"]:
        print("  3. SELinux 问题：")
        print("     - 查看 SELinux 上下文: ls -Z <文件路径>")
        print("     - 检查 SELinux 布尔值: getsebool -a")
        print("     - 生成 SELinux 策略模块: audit2allow")
        print("     - 临时解决方案: setenforce 0 (谨慎使用)")
    
    if results["apparmor_errors"]:
        print("  4. AppArmor 问题：")
        print("     - 检查 AppArmor 状态: aa-status")
        print("     - 查看进程的 AppArmor 配置文件")
        print("     - 修改 AppArmor 配置文件")
    
    print("  5. 通用检查：")
    print("     - 检查用户和组信息: id <用户名>")
    print("     - 验证文件系统挂载选项")
    print("     - 检查 PAM 配置")
    
    print("  6. 调试步骤：")
    print("     - 使用 strace 跟踪系统调用")
    print("     - 检查系统日志详细条目")
    print("     - 测试最小权限配置")
    
    print("  7. 预防措施：")
    print("     - 实施最小权限原则")
    print("     - 定期审计权限配置")
    print("     - 监控权限相关日志")
    print()
    
    print("⚠️  注意：以上为基于日志的离线分析建议，实际操作需在原系统上执行")
    print("================================================================")

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
import os
import sys
import re
import argparse
import subprocess
from datetime import datetime

# Common timestamp patterns for file system logs
TIME_PATTERNS = [
    (r'(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})', "MMM D HH:MM:SS (Syslog)"),
    (r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})', "YYYY-MM-DD HH:MM:SS (ISO)"),
    (r'(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})', "MM/DD/YYYY HH:MM:SS"),
    (r'(\[\s*\d+\.\d+\])', "Kernel timestamp [seconds]"),
]

def find_files(root_dir, filename_pattern):
    matches = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if re.match(filename_pattern, file, re.IGNORECASE):
                matches.append(os.path.join(root, file))
    return matches

def get_time_info(file_path):
    min_dt = None
    max_dt = None
    detected_fmt = "Unknown"
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            if not lines: return None, None, "Empty"
            
            # Find format and min time
            for line in lines[:200]:
                for pattern, fmt_name in TIME_PATTERNS:
                    match = re.search(pattern, line)
                    if match:
                        ts_str = match.group(1)
                        detected_fmt = fmt_name
                        # Parsing logic
                        fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
                        for f_str in fmts:
                            try:
                                dt = datetime.strptime(ts_str, f_str)
                                if f_str == "%b %d %H:%M:%S": dt = dt.replace(year=datetime.now().year)
                                if min_dt is None or dt < min_dt: min_dt = dt
                                break
                            except: continue
                        if min_dt: break
            
            # Find max time
            for line in reversed(lines[-200:]):
                for pattern, _ in TIME_PATTERNS:
                    match = re.search(pattern, line)
                    if match:
                        ts_str = match.group(1)
                        fmts = ["%b %d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S"]
                        for f_str in fmts:
                            try:
                                dt = datetime.strptime(ts_str, f_str)
                                if f_str == "%b %d %H:%M:%S": dt = dt.replace(year=datetime.now().year)
                                if max_dt is None or dt > max_dt: max_dt = dt
                                break
                            except: continue
                        if max_dt: break
    except: pass
    return min_dt, max_dt, detected_fmt

def run_diagnose_script(script_name, log_dir, args_str=""):
    script_path = os.path.join(os.path.dirname(__file__), script_name)
    cmd = f"python3 {script_path} {log_dir} {args_str}"
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.stdout
    except Exception as e:
        return f"Error running {script_name}: {e}"

def show_overview(log_dir):
    print("\n=== File System Log Overview ===")
    
    # 1. Time Range
    print("\n[Log Time Range]")
    time_files = find_files(log_dir, r".*\.(log|txt)$")
    global_min = None
    global_max = None
    
    if time_files:
        for file in time_files[:5]:  # Check first 5 files
            min_dt, max_dt, fmt = get_time_info(file)
            if min_dt:
                if global_min is None or min_dt < global_min: global_min = min_dt
            if max_dt:
                if global_max is None or max_dt > global_max: global_max = max_dt
        
        if global_min and global_max:
            print(f"  Earliest Log: {global_min}")
            print(f"  Latest Log:   {global_max}")
        else:
            print("  Could not determine time range from logs.")
    else:
        print("  No log files found to determine time range.")
    
    # 2. File Count by type
    print("\n[File Summary]")
    file_patterns = {
        "Kernel dmesg": r".*dmesg.*",
        "System messages": r".*messages.*|.*syslog.*",
        "SMART logs": r".*smart.*",
        "FSCK logs": r".*fsck.*",
        "Mount logs": r".*mount.*|.*fstab.*",
    }
    
    for name, pattern in file_patterns.items():
        files = find_files(log_dir, pattern)
        if files:
            print(f"  {name}: {len(files)} files")
    
    # 3. Error Overview
    print("\n[Error Summary]")
    error_keywords = ["error", "fail", "critical", "warning", "panic", "corrupt", "damage", "timeout"]
    
    issues_found = []
    for file_path in time_files[:10]:  # Check first 10 files
        try:
            filename = os.path.basename(file_path)
            error_count = 0
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    if any(k in line.lower() for k in error_keywords):
                        error_count += 1
            if error_count > 0:
                issues_found.append((filename, error_count))
        except: pass
        
    if issues_found:
        print(f"  Found potential issues in {len(issues_found)} files:")
        issues_found.sort(key=lambda x: x[1], reverse=True)
        for name, count in issues_found[:5]:  # Show top 5
            print(f"    - {name}: {count} occurrences")
    else:
        print("  No obvious error keywords found in scanned files.")
    print("=======================\n")

def main():
    parser = argparse.ArgumentParser(
        description="Integrated File System Diagnosis Summary Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/ -o
  python3 %(prog)s ./logs/ -k "I/O error" "corrupt"
  python3 %(prog)s ./logs/ -d "Mar 16"
  python3 %(prog)s ./logs/ -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
        """
    )
    parser.add_argument("log_dir", help="Directory containing file system logs")
    parser.add_argument("-k", "--keywords", nargs="+", metavar="WORD",
                        help="Additional keywords to search for (e.g., 'I/O error', 'corrupt', 'mount failed')")
    parser.add_argument("-d", "--date", metavar="DATE_STR",
                        help="Filter logs by a date string (e.g., 'Mar 16' or '2026-03-10')")
    parser.add_argument("-s", "--start-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="Start time for filtering (e.g., '2026-03-10 08:00:00')")
    parser.add_argument("-e", "--end-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="End time for filtering (e.g., '2026-03-10 12:00:00')")
    parser.add_argument("-o", "--overview", action="store_true",
                        help="Show log overview instead of detailed analysis")
    
    args = parser.parse_args()
    log_dir = args.log_dir
    
    if not os.path.isdir(log_dir):
        print(f"Error: {log_dir} is not a directory.")
        sys.exit(1)

    print("====================================================")
    print("      Integrated File System Diagnosis Summary")
    print("====================================================\n")

    if args.overview:
        show_overview(log_dir)
        return

    # 1. Metadata Analysis
    print("--- [1. Metadata & Time Analysis] ---")
    
    # Check for common log types
    log_types = {
        "Kernel Logs": find_files(log_dir, r".*dmesg.*"),
        "System Logs": find_files(log_dir, r".*messages.*|.*syslog.*"),
        "SMART Logs": find_files(log_dir, r".*smart.*"),
        "FSCK Logs": find_files(log_dir, r".*fsck.*"),
        "Mount Logs": find_files(log_dir, r".*mount.*|.*fstab.*"),
    }
    
    for name, files in log_types.items():
        if files:
            print(f"\n{name}: Found {len(files)} files")
            if files:
                min_t, max_t, fmt = get_time_info(files[0])
                print(f"  Sample File: {os.path.basename(files[0])}")
                print(f"  Time Format: {fmt}")
                if min_t and max_t:
                    print(f"  Time Range:  {min_t} to {max_t}")
        else:
            print(f"\n{name}: Not Found")

    # 2. Detailed Diagnosis Results
    print("\n--- [2. Detailed Diagnosis Summary] ---")
    
    pass_args = ""
    if args.keywords: pass_args += f" -k {' '.join(args.keywords)}"
    if args.date: pass_args += f" -d '{args.date}'"
    if args.start_time: pass_args += f" -s '{args.start_time}'"
    if args.end_time: pass_args += f" -e '{args.end_time}'"

    # Check if we have Python diagnosis scripts
    script_dir = os.path.dirname(__file__)
    
    # Run scene classifier first
    scene_classifier = os.path.join(script_dir, "scene_classifier.py")
    if os.path.exists(scene_classifier):
        print("\n>>> Scene Classification Results:")
        cmd = f"python3 {scene_classifier} {log_dir} {pass_args}"
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            print(result.stdout)
        except Exception as e:
            print(f"Error running scene classifier: {e}")
    else:
        print("\n>>> Scene Classification: Not available (scene_classifier.py not found)")

    # Check for specific diagnosis scripts
    diagnosis_scripts = {
        "File System Corruption": "diagnose_fs_corruption.py",
        "Disk Hardware Failure": "diagnose_disk_failure.py",
        "Mount Error": "diagnose_mount_error.py",
        "I/O Error": "diagnose_io_error.py",
        "Permission Issue": "diagnose_permission.py",
        "Space Issue": "diagnose_space.py",
    }
    
    for name, script in diagnosis_scripts.items():
        script_path = os.path.join(script_dir, script)
        if os.path.exists(script_path):
            print(f"\n>>> {name} Analysis:")
            cmd = f"python3 {script_path} {log_dir} {pass_args}"
            try:
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                # Show first 20 lines of output
                lines = result.stdout.split('\n')
                for line in lines[:20]:
                    if line.strip():
                        print(f"  {line}")
                if len(lines) > 20:
                    print(f"  ... (output truncated, {len(lines)-20} more lines)")
            except Exception as e:
                print(f"  Error: {e}")

    print("\n====================================================")
    print("                Diagnosis Complete")
    print("====================================================")

if __name__ == "__main__":
    main()
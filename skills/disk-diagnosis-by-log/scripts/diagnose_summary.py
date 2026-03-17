#!/usr/bin/env python3
import os
import sys
import re
import argparse
import subprocess
from datetime import datetime

# Common timestamp patterns
TIME_PATTERNS = [
    (r'(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})', "MMM D HH:MM:SS (Syslog)"),
    (r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})', "YYYY-MM-DD HH:MM:SS (ISO)"),
    (r'(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})', "MM/DD/YYYY HH:MM:SS (SEL)"),
]

def find_files(root_dir, filename_pattern):
    matches = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if re.match(filename_pattern, file):
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
                        # Parsing logic similar to sub-scripts
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

def main():
    parser = argparse.ArgumentParser(
        description="Integrated Disk Diagnosis Summary Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/ -k "disk_fail" "slot0"
  python3 %(prog)s ./logs/ -d "Mar 16"
  python3 %(prog)s ./logs/ -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
        """
    )
    parser.add_argument("root_dir", help="Root directory containing 'ibmc_logs', 'infocollect_logs', and 'messages' folders")
    parser.add_argument("-k", "--keywords", nargs="+", metavar="WORD",
                        help="Additional keywords to search for (e.g., 'fail', 'sdb', 'slot 1')")
    parser.add_argument("-d", "--date", metavar="DATE_STR",
                        help="Filter logs by a date string (e.g., 'Mar 16' or '2026-03-10')")
    parser.add_argument("-s", "--start-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="Start time for filtering (e.g., '2026-03-10 08:00:00')")
    parser.add_argument("-e", "--end-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="End time for filtering (e.g., '2026-03-10 12:00:00')")
    
    args = parser.parse_args()
    root_dir = args.root_dir
    
    if not os.path.isdir(root_dir):
        print(f"Error: {root_dir} is not a directory.")
        sys.exit(1)

    print("====================================================")
    print("      Integrated Disk Diagnosis Summary")
    print("====================================================\n")

    # 1. Metadata Analysis
    print("--- [1. Metadata & Time Analysis] ---")
    sub_dirs = {
        "iBMC Logs": os.path.join(root_dir, "ibmc_logs"),
        "InfoCollect": os.path.join(root_dir, "infocollect_logs"),
        "OS Messages": os.path.join(root_dir, "messages")
    }

    for name, path in sub_dirs.items():
        if os.path.exists(path):
            print(f"\n{name} Folder: Found")
            # Sample a key log file for time analysis
            sample_file = None
            if name == "iBMC Logs": sample_file = find_files(path, r".*sel.*\.txt|.*sel.*\.csv")
            elif name == "InfoCollect": sample_file = find_files(path, r"disk_smart\.txt|sasraidlog\.txt")
            elif name == "OS Messages": sample_file = find_files(path, r"messages.*|syslog.*|dmesg.*")
            
            if sample_file:
                min_t, max_t, fmt = get_time_info(sample_file[0])
                print(f"  Sample File: {os.path.basename(sample_file[0])}")
                print(f"  Time Format: {fmt}")
                print(f"  Time Range:  {min_t} to {max_t}")
            else:
                print("  No sample log files found for time analysis.")
        else:
            print(f"\n{name} Folder: Not Found")

    # 2. Detailed Diagnosis Results
    print("\n--- [2. Detailed Diagnosis Summary] ---")
    
    pass_args = ""
    if args.keywords: pass_args += f" -k {' '.join(args.keywords)}"
    if args.date: pass_args += f" -d '{args.date}'"
    if args.start_time: pass_args += f" -s '{args.start_time}'"
    if args.end_time: pass_args += f" -e '{args.end_time}'"

    # Run sub-scripts
    if os.path.exists(sub_dirs["iBMC Logs"]):
        print("\n>>> iBMC Diagnosis Results:")
        print(run_diagnose_script("diagnose_ibmc.py", sub_dirs["iBMC Logs"], pass_args))

    if os.path.exists(sub_dirs["InfoCollect"]):
        print("\n>>> InfoCollect Diagnosis Results:")
        print(run_diagnose_script("diagnose_infocollect.py", sub_dirs["InfoCollect"], pass_args))

    if os.path.exists(sub_dirs["OS Messages"]):
        print("\n>>> OS Messages Diagnosis Results:")
        print(run_diagnose_script("diagnose_messages.py", sub_dirs["OS Messages"], pass_args))

    print("\n====================================================")
    print("                Diagnosis Complete")
    print("====================================================")

if __name__ == "__main__":
    main()

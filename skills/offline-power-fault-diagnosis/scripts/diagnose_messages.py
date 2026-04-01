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
]

def find_files(root_dir, filename_pattern):
    matches = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if re.match(filename_pattern, file):
                matches.append(os.path.join(root, file))
    return matches

def parse_time(line):
    for pattern in TIME_PATTERNS:
        match = re.search(pattern, line)
        if match:
            ts_str = match.group(1)
            formats = [
                "%b %d %H:%M:%S", 
                "%Y-%m-%d %H:%M:%S", 
                "%Y-%m-dT%H:%M:%S",
                "%m/%d/%Y %H:%M:%S"
            ]
            for fmt in formats:
                try:
                    dt = datetime.strptime(ts_str, fmt)
                    if fmt == "%b %d %H:%M:%S":
                        dt = dt.replace(year=datetime.now().year) 
                    return dt
                except ValueError:
                    continue
    return None

def is_in_time_range(line, start_dt, end_dt, target_date_str):
    if target_date_str:
        if target_date_str in line:
            return True
        if not start_dt and not end_dt:
            return False
    
    if start_dt or end_dt:
        dt = parse_time(line)
        if dt:
            if start_dt and dt < start_dt:
                return False
            if end_dt and dt > end_dt:
                return False
            return True
        return False
        
    return True

def get_file_time_range(file_path):
    min_dt = None
    max_dt = None
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for _ in range(100):
                line = f.readline()
                if not line: break
                dt = parse_time(line)
                if dt:
                    if min_dt is None or dt < min_dt: min_dt = dt
                    if max_dt is None or dt > max_dt: max_dt = dt
            
            f.seek(0, os.SEEK_END)
            file_size = f.tell()
            if file_size > 100000:
                f.seek(max(0, file_size - 100000))
                f.readline()
            else:
                f.seek(0)
                
            for line in f:
                dt = parse_time(line)
                if dt:
                    if min_dt is None or dt < min_dt: min_dt = dt
                    if max_dt is None or dt > max_dt: max_dt = dt
    except Exception:
        pass
    return min_dt, max_dt

def grep_file(file_path, keywords, start_dt=None, end_dt=None, date_str=None):
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for i, line in enumerate(f):
                if (start_dt or end_dt or date_str):
                    if not is_in_time_range(line, start_dt, end_dt, date_str):
                        continue

                for keyword in keywords:
                    if keyword.lower() in line.lower():
                        results.append(f"Line {i+1}: {line.strip()}")
                        break
    except Exception as e:
        results.append(f"Error reading {file_path}: {e}")
    return results

def show_overview(root_dir):
    print("\n=== OS Messages Power Log Overview ===")

    print("\n[Log Time Range]")
    time_files = find_files(root_dir, r"(messages.*|syslog.*|dmesg.*|pm\.log)")
    global_min = None
    global_max = None
    
    if time_files:
        for file in time_files:
            min_dt, max_dt = get_file_time_range(file)
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
        print("  No OS messages logs found to determine time range.")

    print("\n[OS Messages Files]")
    messages_files = find_files(root_dir, r"messages.*")
    syslog_files = find_files(root_dir, r"syslog.*")
    dmesg_files = find_files(root_dir, r"dmesg.*")
    pm_files = find_files(root_dir, r"pm\.log")
    
    print(f"  Messages Files: {len(messages_files)}")
    print(f"  Syslog Files: {len(syslog_files)}")
    print(f"  dmesg Files: {len(dmesg_files)}")
    print(f"  Power Management Logs: {len(pm_files)}")
    
    print("\n[Power Error Summary]")
    error_keywords = ["power loss", "AC lost", "system shutdown", "unexpected shutdown", 
                     "power failure", "PSU", "Power Supply", "voltage", "redundancy",
                     "overload", "temperature", "fan", "thermal", "over temperature",
                     "error", "fail", "critical", "warning", "shutdown", "reboot"]
    
    all_files = []
    all_files.extend(find_files(root_dir, r".*\.log"))
    all_files.extend(find_files(root_dir, r"messages.*"))
    all_files.extend(find_files(root_dir, r"syslog.*"))
    all_files = sorted(list(set(all_files)))
    
    issues_found = []
    for file_path in all_files:
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
        print(f"  Found potential power issues in {len(issues_found)} files:")
        issues_found.sort(key=lambda x: x[1], reverse=True)
        for name, count in issues_found:
            print(f"    - {name}: {count} occurrences")
    else:
        print("  No obvious power error keywords found in scanned files.")
    print("=======================\n")

def check_power_loss_events(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking Power Loss Events ---")
    files = find_files(root_dir, r"(messages.*|syslog.*|dmesg.*|pm\.log)")
    if not files:
        print("Warning: OS messages logs not found.")
        return

    keywords = ["power loss", "AC lost", "system shutdown", "unexpected shutdown", 
                "power failure", "shutdown", "reboot", "halt", "power off"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
            print(f"  Found {len(issues)} power loss events. Showing first 20:")
            for issue in issues[:20]:
                print(f"  {issue}")
        else:
            print("  No power loss events found.")

def check_power_management_logs(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking Power Management Logs ---")
    files = find_files(root_dir, r"(pm\.log|.*power.*\.log|.*acpi.*\.log)")
    if not files:
        # Fallback to general logs if no specific PM logs
        files = find_files(root_dir, r"(messages.*|syslog.*)")
        
    keywords = ["ACPI", "power management", "suspend", "resume", "hibernate", 
                "power state", "battery", "UPS", "power event"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
            print(f"  Found {len(issues)} power management events. Showing first 15:")
            for issue in issues[:15]:
                print(f"  {issue}")
        else:
            print("  No power management events found.")

def check_psu_system_logs(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking PSU System Logs ---")
    files = find_files(root_dir, r"(messages.*|syslog.*)")
    if not files:
        print("Warning: System logs not found.")
        return

    keywords = ["PSU", "Power Supply", "power supply", "PSU failure", "PSU fault",
                "voltage", "redundancy", "overload", "current"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
            print(f"  Found {len(issues)} PSU/system power events. Showing first 15:")
            for issue in issues[:15]:
                print(f"  {issue}")
        else:
            print("  No PSU/system power events found.")

def check_temperature_system_logs(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking Temperature System Logs ---")
    files = find_files(root_dir, r"(messages.*|syslog.*|dmesg.*)")
    if not files:
        print("Warning: System logs not found.")
        return

    keywords = ["temperature", "thermal", "over temperature", "overheat", 
                "fan", "cooling", "fan failure", "thermal shutdown"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
            print(f"  Found {len(issues)} temperature events. Showing first 15:")
            for issue in issues[:15]:
                print(f"  {issue}")
        else:
            print("  No temperature events found.")

def check_dmesg_power_events(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking dmesg for Power Events ---")
    files = find_files(root_dir, r"(dmesg.*|.*dmesg.*)")
    if not files:
        print("Warning: dmesg logs not found.")
        return

    keywords = ["power.*fail", "ACPI.*error", "unexpected.*shutdown", 
                "thermal.*event", "fan.*failure", "PSU", "power supply",
                "voltage.*regulator", "power.*management"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
            print(f"  Found {len(issues)} power-related dmesg events. Showing first 20:")
            for issue in issues[:20]:
                print(f"  {issue}")
        else:
            print("  No power-related dmesg events found.")

def main():
    parser = argparse.ArgumentParser(
        description="OS Messages Power Log Diagnosis Tool (System Power Events Analysis)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./messages/ -o
  python3 %(prog)s ./messages/ -k "power loss" "shutdown" -d "Mar 16"
  python3 %(prog)s ./messages/ -s "2026-03-15 01:00:00" -e "2026-03-15 23:59:59"
        """
    )
    
    parser.add_argument("log_dir", help="Path to the directory containing OS messages logs")
    
    parser.add_argument("-k", "--keywords", nargs="+", metavar="WORD",
                        help="Additional keywords to search for in system logs")
    
    parser.add_argument("-d", "--date", metavar="DATE_STR",
                        help="Filter logs by specific date string (e.g., 'Mar 5' or '2023-03-05')")
    
    parser.add_argument("-s", "--start-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="Start time for precise time filtering")
    
    parser.add_argument("-e", "--end-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="End time for precise time filtering")
                        
    parser.add_argument("-o", "--overview", action="store_true",
                        help="Show high-level overview instead of detailed logs")

    args = parser.parse_args()
    
    if not os.path.isdir(args.log_dir):
        print(f"Error: Directory {args.log_dir} not found.")
        sys.exit(1)

    if args.overview:
        show_overview(args.log_dir)
        sys.exit(0)

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

    print(f"Starting OS Messages Power Diagnosis on {args.log_dir}...")
    
    grep_kwargs = {
        'start_dt': start_dt,
        'end_dt': end_dt,
        'date_str': args.date
    }

    check_power_loss_events(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    check_power_management_logs(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    check_psu_system_logs(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    check_temperature_system_logs(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    check_dmesg_power_events(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    
    print("\nOS Messages Power Diagnosis Complete.")

if __name__ == "__main__":
    main()
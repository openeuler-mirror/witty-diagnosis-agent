#!/usr/bin/env python3
import os
import sys
import re
import argparse
from datetime import datetime

# Common timestamp patterns in logs
# Syslog: Mar  5 10:56:59
# ISO8601: 2023-03-05T10:56:59
# SEL: 03/05/2023 10:56:59
TIME_PATTERNS = [
    r'(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})',  # Mar  5 10:56:59
    r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})', # 2023-03-05 10:56:59
    r'(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})', # 03/05/2023 10:56:59
]

def find_files(root_dir, filename_pattern):
    matches = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if re.match(filename_pattern, file):
                matches.append(os.path.join(root, file))
    return matches

def parse_time(line):
    # Try to extract timestamp from line
    for pattern in TIME_PATTERNS:
        match = re.search(pattern, line)
        if match:
            ts_str = match.group(1)
            # Try parsing common formats
            formats = [
                "%b %d %H:%M:%S", 
                "%Y-%m-%d %H:%M:%S", 
                "%Y-%m-%dT%H:%M:%S",
                "%m/%d/%Y %H:%M:%S"
            ]
            for fmt in formats:
                try:
                    # For format like "Mar 5 ...", year is missing. Assume current year or handle carefully.
                    # This is a simple diagnostic tool, assuming logs are relatively recent.
                    dt = datetime.strptime(ts_str, fmt)
                    if fmt == "%b %d %H:%M:%S":
                        dt = dt.replace(year=datetime.now().year) 
                    return dt
                except ValueError:
                    continue
    return None

def is_in_time_range(line, start_dt, end_dt, target_date_str):
    # If generic date string is provided (e.g. "Mar 5"), simple check
    if target_date_str:
        if target_date_str in line:
            return True
        # If date string is provided but not matched, and no other time filter,
        # we should probably return False?
        # BUT wait, if I use -d "Mar 5", I only want "Mar 5".
        # If line is "Mar 6...", return False.
        if not start_dt and not end_dt:
            return False
    
    # If precise time range
    if start_dt or end_dt:
        dt = parse_time(line)
        if dt:
            if start_dt and dt < start_dt:
                return False
            if end_dt and dt > end_dt:
                return False
            return True
        # If line has no timestamp but we are filtering by time, 
        # usually we might skip it or include it if it's a context line.
        # For strict filtering, we skip.
        return False
        
    return True

def get_file_time_range(file_path):
    min_dt = None
    max_dt = None
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            # Check first 100 lines
            for _ in range(100):
                line = f.readline()
                if not line: break
                dt = parse_time(line)
                if dt:
                    if min_dt is None or dt < min_dt: min_dt = dt
                    if max_dt is None or dt > max_dt: max_dt = dt
            
            # Check last 100 lines (using seek if possible, or just reading if small)
            # Simple approach: read lines and keep last valid dt
            # Optimization: seek to end - 100KB and read?
            f.seek(0, os.SEEK_END)
            file_size = f.tell()
            if file_size > 100000:
                f.seek(max(0, file_size - 100000))
                # Discard partial line
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

def show_overview(root_dir):
    print("\n=== Global Overview ===")

    # 1. Time Range
    print("\n[Log Time Range]")
    time_files = find_files(root_dir, r"(messages.*|syslog.*|dmesg.*)")
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
        print("  No system logs found to determine time range.")

    # 2. Hardware Info
    print("\n[Hardware Overview]")
    smart_files = find_files(root_dir, r"disk_smart\.txt")
    raid_files = find_files(root_dir, r"(sasraidlog|sashbalog)\.txt")
    
    print(f"  SMART Logs found: {len(smart_files)}")
    print(f"  RAID Logs found:  {len(raid_files)}")
    
    # Try to extract disk info from smart logs if possible
    disk_models = set()
    for f_path in smart_files:
        try:
            with open(f_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                # Simple regex for Device Model
                models = re.findall(r"Device Model:\s+(.*)", content)
                disk_models.update(models)
        except: pass
    
    if disk_models:
        print(f"  Detected Disk Models ({len(disk_models)}):")
        for m in disk_models:
            print(f"    - {m.strip()}")
            
    # 3. Error Overview
    print("\n[Error Summary]")
    error_keywords = ["error", "fail", "critical", "warning", "offline", "degraded"]
    
    all_files = []
    # Collect all relevant text files
    all_files.extend(find_files(root_dir, r".*\.txt"))
    all_files.extend(find_files(root_dir, r"(messages.*|syslog.*|dmesg.*)"))
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
        print(f"  Found potential issues in {len(issues_found)} files:")
        # Sort by count desc
        issues_found.sort(key=lambda x: x[1], reverse=True)
        for name, count in issues_found:
            print(f"    - {name}: {count} occurrences")
    else:
        print("  No obvious error keywords found in scanned files.")
    print("=======================\n")

def grep_file(file_path, keywords, start_dt=None, end_dt=None, date_str=None):
    results = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for i, line in enumerate(f):
                # Time filter
                if (start_dt or end_dt or date_str):
                    if not is_in_time_range(line, start_dt, end_dt, date_str):
                        continue

                # Keyword filter
                for keyword in keywords:
                    if keyword.lower() in line.lower():
                        results.append(f"Line {i+1}: {line.strip()}")
                        break
    except Exception as e:
        results.append(f"Error reading {file_path}: {e}")
    return results

def check_smart(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking Disk SMART Health ---")
    files = find_files(root_dir, r"disk_smart\.txt")
    if not files:
        print("Warning: disk_smart.txt not found.")
        return

    # Critical attributes (keywords for grep)
    default_keywords = ["FAILED", "Pre-fail", "Old_age"]
    if extra_keywords:
        default_keywords.extend(extra_keywords)
    
    # Attributes to parse specifically
    critical_attrs = {
        "Reallocated_Sector_Ct": 0,
        "Current_Pending_Sector": 0,
        "Uncorrectable_Sector_Ct": 0,
        "Command_Timeout": 0,
    }
    
    for file in files:
        print(f"Scanning {file}...")
        try:
            with open(file, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    # SMART logs usually don't have timestamps per line, so we ignore time filtering here usually
                    # unless it's a historical smart log. Assuming static snapshot for now.
                    
                    # 1. Keyword check
                    for k in default_keywords:
                        if k.lower() in line.lower() and "Always" not in line: 
                             # Just a simple heuristic output
                             pass 

                    # 2. Attribute parsing
                    parts = line.split()
                    if len(parts) > 9:
                        name = parts[1]
                        if name in critical_attrs:
                            try:
                                raw_val = int(parts[-1])
                                if raw_val > critical_attrs[name]:
                                    print(f"  [WARNING] {name}: {raw_val} (Raw Value) in {line.strip()}")
                            except ValueError:
                                pass
                    
                    if "SMART overall-health self-assessment test result" in line:
                        if "PASSED" not in line:
                             print(f"  [CRITICAL] Health Test Failed: {line.strip()}")

        except Exception as e:
            print(f"Error: {e}")

def check_raid(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking RAID Status ---")
    files = find_files(root_dir, r"(sasraidlog|sashbalog)\.txt")
    if not files:
        print("Warning: RAID logs not found.")
        return

    keywords = ["Degraded", "Offline", "Failed", "Rebuild", "Media Error", "Predictive Failure"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        # RAID logs might not have standard timestamps on every line, depends on the tool output
        # passing kwargs just in case user wants to grep specific dates if they exist in the text
        raw_issues = grep_file(file, keywords, **kwargs)
        
        # Filter out legend/header lines which often contain the keywords but aren't actual errors
        # Legend lines often have | separators and definitions like =
        issues = []
        for issue in raw_issues:
            # Skip common legend patterns
            if "|" in issue and "=" in issue: continue
            if "Cac=CacheCade" in issue: continue
            if "UBUnsp=UBad" in issue: continue
            if "Pdgd=Partially" in issue: continue
            # Skip lines that are just configuration settings (unless they indicate a failure)
            if "Rate =" in issue or "Rate :" in issue: continue
            if "Auto Rebuild =" in issue or "AutoRebuild :" in issue: continue
            if "Force Offline =" in issue or "Force Rebuild =" in issue: continue
            
            issues.append(issue)
            
        # Re-filter specific noisy patterns in RAID logs
        final_issues = []
        for issue in issues:
            # Skip "Media Error Count = 0" and "Predictive Failure Count = 0"
            if "Count = 0" in issue: continue
            if "Media Error:       0" in issue: continue
            if "Other Error:         0" in issue: continue
            if "Snapdump not supported" in issue: continue
            if "Invalid command for requested device type" in issue: continue
            if "Cachevault is absent" in issue: continue
            if "Failed to get lock key on bootup" in issue: continue
            if "Deny Force Failed" in issue: continue
            if "Support Degraded Media" in issue: continue
            if "Disable AutoRebuild" in issue: continue
            if "Any Offline VD Cache Preserved" in issue: continue
            if "Last Predictive Failure Event Sequence Number" in issue: continue
            if "Rebuild Rate" in issue: continue
            
            final_issues.append(issue)
            
        if final_issues:
            for issue in final_issues:
                print(f"  {issue}")
        else:
            print("  No obvious RAID issues found.")

def check_io_performance(root_dir, **kwargs):
    print("\n--- Checking I/O Performance (iostat) ---")
    files = find_files(root_dir, r"iostat\.txt")
    if not files:
        print("Warning: iostat.txt not found.")
        return

    for file in files:
        print(f"Scanning {file}...")
        try:
            with open(file, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                
            util_idx = -1
            await_idx = -1
            header_found = False
            
            for line in lines:
                # iostat usually captures snapshots. Timestamps might be on separate lines.
                # Complex to filter line-by-line with timestamps. 
                # For now, we process all, as performance issues are usually systemic.
                
                parts = line.split()
                if not parts:
                    continue
                    
                if "Device" in line and ("%util" in line or "util" in line):
                    header_found = True
                    try:
                        if "%util" in parts: util_idx = parts.index("%util")
                        elif "util" in parts: util_idx = parts.index("util")
                        if "await" in parts: await_idx = parts.index("await")
                    except ValueError: pass
                    continue
                
                if header_found and util_idx != -1 and len(parts) > util_idx:
                    try:
                        if not parts[0][0].isalpha(): continue
                        util = float(parts[util_idx].replace(',', '.'))
                        if util > 95.0:
                            print(f"  [WARNING] High Utilization: {parts[0]} - {util}%")
                        if await_idx != -1 and len(parts) > await_idx:
                            await_val = float(parts[await_idx].replace(',', '.'))
                            if await_val > 20.0:
                                print(f"  [WARNING] High Latency: {parts[0]} - {await_val}ms")
                    except ValueError: pass
                        
        except Exception as e:
            print(f"  Error parsing {file}: {e}")

def check_system_events(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking System Events (dmesg/messages) ---")
    files = find_files(root_dir, r"(dmesg\.txt|message.*|syslog.*)")
    if not files:
        print("Warning: System logs not found.")
        return

    keywords = ["I/O error", "SCSI error", "buffer I/O error", "rejecting I/O", "xfs_force_shutdown", "EXT4-fs error"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
            print(f"  Found {len(issues)} potential issues. Showing first 10:")
            for issue in issues[:10]:
                print(f"  {issue}")
        else:
            print("  No critical storage errors found.")

def main():
    parser = argparse.ArgumentParser(
        description="Detailed Disk Diagnosis Tool (SMART/RAID/iostat Analysis)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./infocollect_logs/ -o
  python3 %(prog)s ./infocollect_logs/ -k "sda" "error"
  python3 %(prog)s ./infocollect_logs/ -d "2023-03-05" -k "FAILED"
        """
    )
    
    parser.add_argument("log_dir", help="Path to the directory containing InfoCollect logs")
    
    parser.add_argument("-k", "--keywords", nargs="+", metavar="WORD",
                        help="Additional keywords to search for (e.g., 'sda', 'Critical')")
    
    parser.add_argument("-d", "--date", metavar="DATE_STR",
                        help="Filter logs by specific date string (e.g., '2023-03-05'). Matches substring.")
    
    parser.add_argument("-s", "--start-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="Start time for filtering (e.g., '2023-03-05 10:00:00')")
    
    parser.add_argument("-e", "--end-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="End time for filtering (e.g., '2023-03-05 12:00:00')")
                        
    parser.add_argument("-o", "--overview", action="store_true",
                        help="Show global health summary (SMART healthy, RAID status, I/O bottlenecks) instead of detailed logs")

    args = parser.parse_args()
    
    if not os.path.isdir(args.log_dir):
        print(f"Error: Directory {args.log_dir} not found.")
        sys.exit(1)

    if args.overview:
        show_overview(args.log_dir)
        # If overview is requested, we might still want to run full diagnosis or not?
        # Usually overview is a quick check. Let's ask or assume.
        # The user said "Global overview", implying a summary mode. 
        # I will return after overview to keep it clean, unless user wants both.
        # But typically one might run -o to see what's up, then run without it for details.
        # Let's exit after overview.
        sys.exit(0)

    # Parse timestamps if provided
    start_dt = None
    end_dt = None
    if args.start_time:
        try:
            start_dt = datetime.strptime(args.start_time, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            print("Error: Invalid start time format. Use 'YYYY-MM-DD HH:MM:SS'")
            sys.exit(1)
    if args.end_time:
        try:
            end_dt = datetime.strptime(args.end_time, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            print("Error: Invalid end time format. Use 'YYYY-MM-DD HH:MM:SS'")
            sys.exit(1)

    print(f"Starting Disk Diagnosis on {args.log_dir}...")
    if args.keywords: print(f"Additional Keywords: {args.keywords}")
    if args.date: print(f"Filter Date: {args.date}")
    if start_dt: print(f"Start Time: {start_dt}")
    
    # Common args for grep functions
    grep_kwargs = {
        'start_dt': start_dt,
        'end_dt': end_dt,
        'date_str': args.date
    }

    check_smart(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    check_raid(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    check_io_performance(args.log_dir, **grep_kwargs)
    check_system_events(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    
    print("\nDiagnosis Complete.")

if __name__ == "__main__":
    main()

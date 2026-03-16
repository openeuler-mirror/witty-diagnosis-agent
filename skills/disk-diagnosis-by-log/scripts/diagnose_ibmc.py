
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

def show_overview(root_dir):
    print("\n=== iBMC Log Overview ===")

    # 1. Time Range
    print("\n[Log Time Range]")
    time_files = find_files(root_dir, r"(sel.*\.csv|.*sel.*\.txt)")
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
        print("  No iBMC SEL logs found to determine time range.")

    # 2. SEL Count
    print("\n[SEL Summary]")
    sel_files = find_files(root_dir, r".*sel.*")
    print(f"  SEL Files found: {len(sel_files)}")
    
    # 3. Error Overview
    print("\n[Error Summary]")
    error_keywords = ["error", "fail", "critical", "warning", "asserted", "deasserted"]
    
    all_files = []
    all_files.extend(find_files(root_dir, r".*\.txt"))
    all_files.extend(find_files(root_dir, r".*\.csv"))
    all_files.extend(find_files(root_dir, r".*\.log"))
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
        issues_found.sort(key=lambda x: x[1], reverse=True)
        for name, count in issues_found:
            print(f"    - {name}: {count} occurrences")
    else:
        print("  No obvious error keywords found in scanned files.")
    print("=======================\n")

def check_ibmc_sel(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking iBMC SEL (System Event Logs) ---")
    files = find_files(root_dir, r"(sel.*|.*sel.*\.txt|.*sel.*\.csv|.*sel.*\.log)")
    if not files:
        print("Warning: iBMC SEL logs not found.")
        return

    # Critical keywords for SEL
    keywords = ["Asserted", "Critical", "Non-recoverable", "Drive Fault", "Slot", "Predictive Failure", "Uncorrectable"]
    if extra_keywords:
        keywords.extend(extra_keywords)
    
    for file in files:
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
            print(f"  Found {len(issues)} potential issues. Showing first 20:")
            for issue in issues[:20]:
                print(f"  {issue}")
        else:
            print("  No critical SEL events found.")

def check_ibmc_faults(root_dir, extra_keywords=None, **kwargs):
    print("\n--- Checking General iBMC Faults ---")
    files = find_files(root_dir, r"(alarm.*|fault.*|error.*)")
    if not files:
        # Fallback to scanning all logs if no specific alarm files found
        files = find_files(root_dir, r".*\.log")
        
    keywords = ["Fault", "Error", "Failed", "Abnormal"]
    if extra_keywords:
        keywords.extend(extra_keywords)
        
    for file in files:
        # Skip huge binary files or irrelevant ones if possible
        if file.endswith('.tar.gz') or file.endswith('.zip'): continue
        
        # We only scan if filename suggests faults OR if it's a general log scan
        # To avoid noise, let's limit this check to files that likely contain faults
        if "sel" in os.path.basename(file).lower(): continue # Already checked in SEL
        
        print(f"Scanning {file}...")
        issues = grep_file(file, keywords, **kwargs)
        if issues:
             # Limit output
             if len(issues) > 5:
                 print(f"  Found {len(issues)} issues. Showing first 5:")
                 for issue in issues[:5]:
                     print(f"  {issue}")
             else:
                 for issue in issues:
                     print(f"  {issue}")

def main():
    parser = argparse.ArgumentParser(
        description="iBMC Log Diagnosis Tool (SEL/Fault Analysis)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./ibmc_logs/ -o
  python3 %(prog)s ./ibmc_logs/ -k "Drive Fault" -d "Mar 16"
  python3 %(prog)s ./ibmc_logs/ -s "2026-03-15 01:00:00" -e "2026-03-15 23:59:59"
        """
    )
    
    parser.add_argument("log_dir", help="Path to the directory containing iBMC logs (e.g., exported .tar.gz content)")
    
    parser.add_argument("-k", "--keywords", nargs="+", metavar="WORD",
                        help="Additional keywords to search for in SEL and alarm logs")
    
    parser.add_argument("-d", "--date", metavar="DATE_STR",
                        help="Filter logs by specific date string (e.g., 'Mar 5' or '2023-03-05')")
    
    parser.add_argument("-s", "--start-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="Start time for precise time filtering")
    
    parser.add_argument("-e", "--end-time", metavar="'YYYY-MM-DD HH:MM:SS'",
                        help="End time for precise time filtering")
                        
    parser.add_argument("-o", "--overview", action="store_true",
                        help="Show high-level overview (Time range, SEL count, Error summary) instead of detailed logs")

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

    print(f"Starting iBMC Diagnosis on {args.log_dir}...")
    
    grep_kwargs = {
        'start_dt': start_dt,
        'end_dt': end_dt,
        'date_str': args.date
    }

    check_ibmc_sel(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    check_ibmc_faults(args.log_dir, extra_keywords=args.keywords, **grep_kwargs)
    
    print("\nDiagnosis Complete.")

if __name__ == "__main__":
    main()

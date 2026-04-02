#!/usr/bin/env python3
import os
import sys
import re
import argparse
from datetime import datetime
import random
import string

def find_files(root_dir, pattern):
    """Recursively find files matching the pattern."""
    matched_files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if re.search(pattern, filename, re.IGNORECASE):
                matched_files.append(os.path.join(dirpath, filename))
    return matched_files

def determine_scenario(root_dir):
    """Determine the log scenario based on file presence."""
    if find_files(root_dir, r'disk_smart\.txt$'):
        return 'infocollect'
    elif find_files(root_dir, r'PD_SMART_INFO_C.*'):
        return 'ibmc'
    else:
        return 'unknown'

def parse_infocollect_env_link(root_dir):
    issues = []
    
    # 1. Check CRC Errors in SMART (ID 199)
    smart_files = find_files(root_dir, r'disk_smart\.txt$')
    for file_path in smart_files:
        current_disk = None
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    disk_match = re.match(r'^smartctl -a (/dev/\S+)', line)
                    if disk_match:
                        current_disk = disk_match.group(1)
                    elif current_disk:
                        # Extract attribute 199 (UDMA_CRC_Error_Count)
                        attr_match = re.match(r'^\s*199\s+([a-zA-Z0-9_-]+)\s+0[xX][0-9a-fA-F]+\s+\d+\s+\d+\s+\d+\s+[a-zA-Z_-]+\s+[a-zA-Z_-]+\s+[^\s]+\s+(\d+)', line)
                        if attr_match:
                            raw = int(attr_match.group(2))
                            if raw > 0:
                                issues.append({
                                    'layer': 'L4 链路层',
                                    'component': current_disk,
                                    'issue': f"UDMA_CRC_Error_Count (ID 199) RAW is {raw} (>0)",
                                    'impact': 'HIGH (可能是线缆老化、背板接触不良或接口故障，易被误判为坏盘)',
                                    'source': f"{file_path}:{line_num}"
                                })
                        # Check Temperature ID 194
                        temp_match = re.match(r'^\s*194\s+Temperature_Celsius\s+0[xX][0-9a-fA-F]+\s+\d+\s+\d+\s+\d+\s+[a-zA-Z_-]+\s+[a-zA-Z_-]+\s+[^\s]+\s+(\d+)', line)
                        if temp_match:
                            temp = int(temp_match.group(1))
                            if temp > 65:
                                issues.append({
                                    'layer': 'L3 环境层',
                                    'component': current_disk,
                                    'issue': f"Temperature is {temp}℃ (>65℃)",
                                    'impact': 'HIGH (硬盘过热，可能导致性能下降或寿命加速损耗，检查散热)',
                                    'source': f"{file_path}:{line_num}"
                                })
        except Exception as e:
            print(f"Error reading {file_path}: {e}")

    # 2. Check RAID Controller Status
    raid_files = find_files(root_dir, r'sasraidlog\.txt$') + find_files(root_dir, r'sashbalog\.txt$')
    for file_path in raid_files:
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    # Check for Degraded or Offline Virtual Drives
                    if re.search(r'State\s*:\s*(Degraded|Offline|Failed)', line, re.IGNORECASE):
                        issues.append({
                            'layer': 'L4 控制器层',
                            'component': 'RAID Controller / VD',
                            'issue': f"RAID array state is Degraded/Offline/Failed",
                            'impact': 'CRITICAL (阵列降级或离线，存在数据丢失风险)',
                            'source': f"{file_path}:{line_num}"
                        })
                    # Check for rebuilding
                    if re.search(r'State\s*:\s*Rebuild', line, re.IGNORECASE) or re.search(r'Rebuild Progress', line, re.IGNORECASE):
                         issues.append({
                            'layer': 'L4 控制器层',
                            'component': 'RAID Controller / VD',
                            'issue': f"RAID array is currently Rebuilding",
                            'impact': 'MEDIUM (阵列正在重建，此时系统性能下降，若再坏盘将导致数据丢失)',
                            'source': f"{file_path}:{line_num}"
                        })
        except Exception:
            pass

    # 3. Check OS Link Resets / SCSI Errors
    dmesg_files = find_files(root_dir, r'dmesg\.txt$') + find_files(root_dir, r'messages.*')
    for file_path in dmesg_files:
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    if 'reset link' in line.lower() or 'hard resetting link' in line.lower():
                        issues.append({
                            'layer': 'L4 链路层',
                            'component': 'OS Link / HBA',
                            'issue': f"OS detected link reset: {line.strip()[:100]}",
                            'impact': 'HIGH (底层链路不稳定，控制器不断尝试重置，导致IO卡顿)',
                            'source': f"{file_path}:{line_num}"
                        })
        except Exception:
            pass
            
    return issues

def parse_ibmc_env_link(root_dir):
    issues = []
    
    # 1. Check Global Sensors (Temperature/Power)
    sensor_files = find_files(root_dir, r'sensor_info\.txt$')
    for file_path in sensor_files:
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    # Just an example logic to find reading unavailable or crossing thresholds
                    if 'reading unavailable' in line.lower() or 'unc' in line.lower() or 'ucr' in line.lower():
                         issues.append({
                            'layer': 'L3 环境层',
                            'component': 'Sensors',
                            'issue': f"Sensor abnormal or crossed threshold: {line.strip()[:80]}",
                            'impact': 'MEDIUM/HIGH (传感器读数异常，可能反映环境温度过高或供电异常)',
                            'source': f"{file_path}:{line_num}"
                        })
        except Exception:
            pass

    # 2. Check Power Supply (psu_info.txt)
    psu_files = find_files(root_dir, r'psu_info\.txt$')
    for file_path in psu_files:
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    if 'power loss' in line.lower() or 'input lost' in line.lower():
                        issues.append({
                            'layer': 'L3 环境层',
                            'component': 'PSU (Power Supply)',
                            'issue': f"Power loss detected: {line.strip()[:80]}",
                            'impact': 'CRITICAL (电源丢失可能导致瞬时掉电或设备重启)',
                            'source': f"{file_path}:{line_num}"
                        })
        except Exception:
            pass

    # 3. Check RAID Controller Status
    raid_files = find_files(root_dir, r'RAID_Controller_Info\.txt$')
    for file_path in raid_files:
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    if re.search(r'Status\s*=\s*(Degraded|Offline|Failed)', line, re.IGNORECASE):
                        issues.append({
                            'layer': 'L4 控制器层',
                            'component': 'RAID Controller',
                            'issue': f"RAID Status is Degraded/Offline/Failed: {line.strip()[:80]}",
                            'impact': 'CRITICAL (阵列降级或离线)',
                            'source': f"{file_path}:{line_num}"
                        })
        except Exception:
            pass

    # 4. Check CRC Errors in SMART (ID 199) from iBMC logs
    smart_files = find_files(root_dir, r'PD_SMART_INFO_C.*') + find_files(root_dir, r'SMARTAttribute')
    for file_path in smart_files:
        current_disk = "Unknown"
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    if line.startswith('Device Name') or line.startswith('Device Id'):
                        current_disk = line.split(':', 1)[1].strip()
                    elif '199 ' in line and 'UDMA_CRC' in line:
                         attr_match = re.match(r'^\s*199\s+([a-zA-Z0-9_-]+)\s+0[xX][0-9a-fA-F]+\s+\d+\s+\d+\s+\d+\s+[a-zA-Z_-]+\s+[a-zA-Z_-]+\s+[^\s]+\s+(\d+)', line)
                         if attr_match:
                            raw = int(attr_match.group(2))
                            if raw > 0:
                                issues.append({
                                    'layer': 'L4 链路层',
                                    'component': current_disk,
                                    'issue': f"UDMA_CRC_Error_Count (ID 199) RAW is {raw} (>0)",
                                    'impact': 'HIGH (背板链路/接口可能存在物理接触不良，非硬盘本身介质故障)',
                                    'source': f"{file_path}:{line_num}"
                                })
        except Exception:
            pass
            
    return issues

def main():
    parser = argparse.ArgumentParser(
        description="Automated Disk Environment & Link (L3/L4) Diagnosis Tool",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Examples:
  # The script will automatically detect whether the directory contains OS Infocollect logs or iBMC hardware logs
  python3 env_link_diagnosis.py /opt/data/jinshan_cloud_log/disk_logs/10.107.18.37/infocollect_logs
        """
    )
    parser.add_argument("log_path", help="Root directory of the logs to analyze (auto-detects infocollect or ibmc)")
    args = parser.parse_args()

    root_dir = args.log_path
    if not os.path.exists(root_dir):
        print(f"Error: Directory {root_dir} does not exist.")
        sys.exit(1)

    scenario = determine_scenario(root_dir)
    print(f"Detected scenario: {scenario}")

    issues = []
    if scenario == 'infocollect':
        issues = parse_infocollect_env_link(root_dir)
    elif scenario == 'ibmc':
        issues = parse_ibmc_env_link(root_dir)
    else:
        print("Could not determine log scenario. Aborting.")
        sys.exit(1)

    timestamp_str = datetime.now().strftime('%Y%m%d_%H%M%S')
    random_str = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
    output_file = f"/tmp/env_link_diagnosis_report_{timestamp_str}_{random_str}.txt"
    
    with open(output_file, "w") as out:
        out.write("=============================================\n")
        out.write("  服务器环境与链路层 (L3 & L4) 诊断报告\n")
        out.write("=============================================\n")
        out.write(f"检测执行时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        out.write(f"日志路径：{root_dir}\n")
        out.write(f"检测场景：{scenario.upper()}\n\n")

        out.write("诊断原则说明：\n")
        out.write("- 若出现 L3 环境报警（高温/掉电），需优先排查机房环境与散热器。\n")
        out.write("- 若出现 L4 链路报警（CRC 错误高/链路 Reset），极易表现为系统卡顿或“假坏盘”，请优先排查线缆、背板或 RAID 卡，切勿盲目更换硬盘。\n\n")

        out.write("-" * 140 + "\n")
        out.write(f"{'层级':<15} | {'组件/对象':<25} | {'异常表现':<50} | {'风险影响与建议':<45}\n")
        out.write("-" * 140 + "\n")
        
        if not issues:
            out.write("未检测到环境与链路层异常。所有状态良好。\n")
        else:
            for issue in issues:
                out.write(f"{issue['layer']:<12} | {issue['component'][:25]:<25} | {issue['issue'][:48]:<50} | {issue['impact'][:45]:<45}\n")
                out.write(f"  [坐标]: {issue['source']}\n\n")

    print(f"诊断完成。结果已输出至 {output_file}")

if __name__ == "__main__":
    main()
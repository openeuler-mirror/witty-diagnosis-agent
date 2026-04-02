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

def parse_disk_operations(root_dir):
    """Extract disk-related operations like reboot or hot-plug from OS logs."""
    ops = []
    # Find dmesg and messages files for OS level events
    log_files = find_files(root_dir, r'(dmesg|messages)')
    
    op_patterns = {
        'Reboot / Boot': re.compile(r'(Linux version|Command line:.*BOOT_IMAGE|Command line:.*vmlinuz)'),
        'Disk Plugged In': re.compile(r'(Attached SCSI disk|sd [a-z]+: Attached SCSI disk|Direct-Access.*attached)'),
        'Disk Unplugged': re.compile(r'(Synchronizing SCSI cache.*|sd [a-z]+: Synchronizing SCSI cache|scsi.*:.*:.*:.*: device offline)'),
        'RAID Rebuild Started': re.compile(r'(State change on VD.*from.*to.*Rebuilding|Background Initialization started)'),
        'RAID Rebuild Completed': re.compile(r'(State change on VD.*from.*to.*Optimal|Background Initialization completed)')
    }
    
    timestamp_pattern = re.compile(r'^([A-Z][a-z]{2}\s+\d+\s+\d{2}:\d{2}:\d{2}|\[\s*\d+\.\d+\])')
    
    for file_path in log_files:
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    for op_type, pattern in op_patterns.items():
                        match = pattern.search(line)
                        if match:
                            ts_match = timestamp_pattern.search(line)
                            timestamp = ts_match.group(1) if ts_match else "Unknown Time"
                            ops.append({
                                'type': op_type,
                                'timestamp': timestamp,
                                'matched_text': match.group(0),
                                'full_line': line.strip(),
                                'file_path': file_path,
                                'line_num': line_num
                            })
        except Exception as e:
            pass # Silently ignore unreadable files

    return sorted(ops, key=lambda x: x['line_num'])

def determine_scenario(root_dir):
    """Determine the log scenario based on file presence."""
    if find_files(root_dir, r'disk_smart\.txt$'):
        return 'infocollect'
    elif find_files(root_dir, r'PD_SMART_INFO_C.*'):
        # Both Huawei and H3C use this pattern, we can treat them similarly for SMART
        return 'ibmc'
    else:
        return 'unknown'

def parse_infocollect_smart(file_path):
    disks = []
    current_disk = None
    
    try:
        with open(file_path, 'r', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                # Match OS device name, ignore duplicate sg devices if possible, but keep for completeness if sd* isn't there
                disk_match = re.match(r'^smartctl -a (/dev/\S+)', line)
                if disk_match:
                    if current_disk:
                        disks.append(current_disk)
                    current_disk = {
                        'device': disk_match.group(1), 
                        'health': 'UNKNOWN', 
                        'model': 'N/A', 
                        'serial': 'N/A', 
                        'timestamp': 'N/A',
                        'metrics': {},
                        'log_file': file_path,
                        'log_line': line_num
                    }
                elif current_disk:
                    if line.startswith('Device Model:'):
                        current_disk['model'] = line.split(':', 1)[1].strip()
                    elif line.startswith('Model Family:'):
                        if current_disk['model'] == 'N/A':
                            current_disk['model'] = line.split(':', 1)[1].strip()
                    elif line.startswith('Serial Number:'):
                        current_disk['serial'] = line.split(':', 1)[1].strip()
                    elif line.startswith('Local Time is:'):
                        current_disk['timestamp'] = line.split(':', 1)[1].strip()
                    elif line.startswith('SMART overall-health self-assessment test result:'):
                        current_disk['health'] = line.split(':', 1)[1].strip()
                    else:
                        # Extract attributes: ID, NAME, FLAG, VALUE, WORST, THRESH, TYPE, UPDATED, WHEN_FAILED, RAW_VALUE
                        attr_match = re.match(r'^\s*(\d+)\s+([a-zA-Z0-9_-]+)\s+0[xX][0-9a-fA-F]+\s+(\d+)\s+(\d+)\s+(\d+)\s+[a-zA-Z_-]+\s+[a-zA-Z_-]+\s+([^\s]+)\s+(\d+)', line)
                        if attr_match:
                            attr_id = attr_match.group(1)
                            name = attr_match.group(2)
                            value = int(attr_match.group(3))
                            thresh = int(attr_match.group(5))
                            when_failed = attr_match.group(6)
                            raw = int(attr_match.group(7))
                            current_disk['metrics'][attr_id] = {
                                'name': name,
                                'value': value,
                                'thresh': thresh,
                                'when_failed': when_failed,
                                'raw': raw,
                                'line_num': line_num
                            }
    except Exception as e:
        print(f"Error reading {file_path}: {e}")

    if current_disk:
        disks.append(current_disk)
        
    return disks

def parse_ibmc_smart(file_paths):
    disks = []
    
    for file_path in file_paths:
        current_disk = None
        try:
            with open(file_path, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    # Different iBMC formats might use Device Name, Slot Number, or Device Id
                    if line.startswith('Device Name') or line.startswith('Device Id') or line.startswith('Slot Number'):
                        # If we have a disk and hit a new device identifier, and we haven't seen this identifier type yet, 
                        # it might just be the same disk's attributes.
                        # Usually it's:
                        # Device Id: 0
                        # Slot Number: 38
                        # So we shouldn't create a new disk just for Slot Number if we just got Device Id
                        
                        is_new_disk = False
                        if line.startswith('Device Name') or line.startswith('Device Id'):
                            if current_disk and current_disk['device'] != 'N/A' and not current_disk['device'].isdigit() and not current_disk['device'].startswith("Slot"):
                                is_new_disk = True
                            elif current_disk and (current_disk['device'].isdigit() or current_disk['device'].startswith("Slot")):
                                # In this case we already got something, but if we get another Device Id it's probably a new disk
                                if line.startswith('Device Id'):
                                    is_new_disk = True
                        
                        if is_new_disk:
                            disks.append(current_disk)
                            current_disk = None

                        if not current_disk:
                            current_disk = {
                                'device': 'N/A', 
                                'health': 'UNKNOWN', 
                                'model': 'N/A', 
                                'serial': 'N/A', 
                                'timestamp': 'N/A',
                                'metrics': {},
                                'log_file': file_path,
                                'log_line': line_num
                            }
                            
                        if line.startswith('Device Name') or line.startswith('Device Id'):
                            dev_val = line.split(':', 1)[1].strip()
                            if current_disk['device'] == 'N/A' or current_disk['device'].startswith('Slot'):
                                current_disk['device'] = dev_val
                        elif line.startswith('Slot Number'):
                            if current_disk['device'] == 'N/A' or current_disk['device'].isdigit():
                                current_disk['device'] = "Slot " + line.split(':', 1)[1].strip()
                    elif current_disk:
                        if line.startswith('Model'):
                            current_disk['model'] = line.split(':', 1)[1].strip()
                        elif line.startswith('Serial Number'):
                            current_disk['serial'] = line.split(':', 1)[1].strip()
                        elif line.startswith('Timestamp'):
                            current_disk['timestamp'] = line.split(':', 1)[1].strip()
                        elif line.startswith('Health Status'):
                            current_disk['health'] = line.split(':', 1)[1].strip()
                        elif line.startswith('Manufacturer') or line.startswith('Enclosure Id') or line.startswith('Interface Type') or line.startswith('SMART Attributes Data Revision Number') or line.startswith('Vender Specific SMART Attributes with Thresholds') or line.startswith('Vendor Specific SMART Attributes with Thresholds') or line.startswith('ID#'):
                            pass # Ignored
                        else:
                            # Extract attributes
                            attr_match = re.match(r'^\s*(\d+)\s+([a-zA-Z0-9_-]+)\s+0[xX][0-9a-fA-F]+\s+(\d+)\s+(\d+)\s+(\d+)\s+[a-zA-Z_-]+\s+[a-zA-Z_-]+\s+([^\s]+)\s+(\d+)', line)
                            if attr_match:
                                attr_id = attr_match.group(1)
                                name = attr_match.group(2)
                                value = int(attr_match.group(3))
                                thresh = int(attr_match.group(5))
                                when_failed = attr_match.group(6)
                                raw = int(attr_match.group(7))
                                current_disk['metrics'][attr_id] = {
                                    'name': name,
                                    'value': value,
                                    'thresh': thresh,
                                    'when_failed': when_failed,
                                    'raw': raw,
                                    'line_num': line_num
                                }
        except Exception as e:
            print(f"Error reading {file_path}: {e}")

        if current_disk:
            disks.append(current_disk)
            
    return disks

def evaluate_disk(disk):
    diagnosis = []
    level = 'P3' # Default background risk if old, otherwise OK
    is_failed = False
    justifications = []
    
    # 1. Check ID 198 Offline_Uncorrectable (Fatal)
    metrics = disk['metrics']
    if '198' in metrics:
        raw = metrics['198']['raw']
        if raw > 0:
            msg = f"ID 198 Offline_Uncorrectable RAW is {raw} (>0)"
            diagnosis.append(msg)
            justifications.append(f"【依据】：参考指南决策树，ID 198 RAW > 0 表示存在彻底无法修复的坏道，大概率伴随数据丢失，属致命故障。")
            level = 'P0'
            is_failed = True

    # 2. Check ID 197 Current_Pending_Sector
    if '197' in metrics:
        raw = metrics['197']['raw']
        if raw > 0:
            msg = f"ID 197 Current_Pending_Sector RAW is {raw} (>0)"
            diagnosis.append(msg)
            if not is_failed:
                if raw >= 50:
                    level = 'P0' # 骤增至数十以上
                    justifications.append(f"【依据】：参考指南决策树，ID 197 RAW骤增至数十以上（当前 {raw}），判定为高危故障盘。")
                else:
                    level = 'P1' 
                    justifications.append(f"【依据】：参考指南决策树，ID 197 RAW > 0（当前 {raw}）代表存在读写困难的疑似坏道，判定为故障/亚健康盘。")
                is_failed = True

    # 3. Check ID 5 Reallocated_Sector_Ct
    if '5' in metrics:
        raw = metrics['5']['raw']
        if raw > 0:
            msg = f"ID 5 Reallocated_Sector_Ct RAW is {raw} (>0)"
            diagnosis.append(msg)
            if not is_failed:
                if raw > 50:
                    level = 'P0'
                    justifications.append(f"【依据】：参考指南决策树，ID 5 RAW > 50（当前 {raw}）说明已发生较多不可逆物理坏道并完成重映射，判定为高危故障盘。")
                else:
                    level = 'P1'
                    justifications.append(f"【依据】：参考指南决策树，ID 5 RAW > 0（当前 {raw}）代表已发生物理损伤，属于故障/亚健康盘。")
                is_failed = True
                
    # 4. Check WHEN_FAILED = FAILING_NOW
    for attr_id, m in metrics.items():
        if m['when_failed'] == 'FAILING_NOW':
            msg = f"Attribute {m['name']} is FAILING_NOW (Value {m['value']} <= Threshold {m['thresh']})"
            diagnosis.append(msg)
            if level != 'P0':
                justifications.append(f"【依据】：参考指南决策树，WHEN_FAILED = FAILING_NOW 代表硬盘 Pre-fail 属性跌破厂商阈值，即将物理失效，判定为故障盘。")
            level = 'P0'
            is_failed = True

    # 5. Check Health Status
    if disk['health'] not in ['UNKNOWN', 'PASSED', 'OK'] and not is_failed:
        msg = f"SMART Health is {disk['health']}"
        diagnosis.append(msg)
        justifications.append(f"【依据】：参考指南，综合健康自检结果非 PASSED（当前 {disk['health']}），固件判定即将失效。")
        level = 'P0'
        is_failed = True
            
    # 6. Check Additional L1 & L2 Health/Load Indicators
    # ID 187 Reported_Uncorrectable_Errors
    if '187' in metrics:
        raw = metrics['187']['raw']
        if raw > 5:
            diagnosis.append(f"ID 187 Reported_Uncorrectable_Errors RAW is {raw} (>5)")
            if not is_failed:
                level = 'P1'
                justifications.append(f"【依据】：ID 187 > 5 说明报告给主机的无法纠正错误较多，属亚健康/高危盘。")
                is_failed = True

    # ID 188 Command_Timeout
    if '188' in metrics:
        raw = metrics['188']['raw']
        if raw > 100:
            diagnosis.append(f"ID 188 Command_Timeout RAW is {raw} (>100)")
            if not is_failed:
                level = 'P2'
                justifications.append(f"【依据】：ID 188 > 100 说明指令超时较多，可能存在接口或介质响应异常。")

    # ID 177 Wear_Leveling_Count (SSD)
    if '177' in metrics:
        val = metrics['177']['value']
        thresh = metrics['177']['thresh']
        if val <= thresh and thresh > 0:
            diagnosis.append(f"ID 177 Wear_Leveling_Count VALUE {val} <= THRESH {thresh}")
            if not is_failed:
                level = 'P0'
                justifications.append(f"【依据】：ID 177 跌破阈值，说明 SSD 擦写寿命已耗尽，属高危故障盘。")
                is_failed = True
        elif val - thresh < 20:
            diagnosis.append(f"ID 177 Wear_Leveling_Count VALUE {val} is close to THRESH {thresh}")
            if not is_failed:
                level = 'P1'
                justifications.append(f"【依据】：ID 177 逼近阈值，说明 SSD 寿命剩余不足 20%，建议计划换盘。")

    # Mechanical HDD Indicators (ID 3, 10)
    if '10' in metrics:
        raw = metrics['10']['raw']
        if raw > 0:
            diagnosis.append(f"ID 10 Spin_Retry_Count RAW is {raw} (>0)")
            if not is_failed:
                level = 'P2'
                justifications.append(f"【依据】：ID 10 > 0 说明电机启动重试异常，存在机械老化风险。")

    # L2 Load/Life Indicators (ID 9, 4, 193)
    if '9' in metrics:
        poh = metrics['9']['raw']
        if poh > 50000:
            msg = f"Power_On_Hours is {poh} (>50,000h)"
            if not is_failed and level not in ['P0', 'P1', 'P2']:
                diagnosis.append(msg)
                justifications.append(f"【依据】：参考指南决策树，累计通电时间 > 50,000 小时（当前 {poh}h，约 5.7 年），进入高故障期，属亚健康高龄盘。")
                level = 'P3'
                
    if '4' in metrics:
        start_stop = metrics['4']['raw']
        if start_stop > 10000:
            msg = f"Start_Stop_Count is {start_stop} (>10,000)"
            if not is_failed and level not in ['P0', 'P1', 'P2']:
                diagnosis.append(msg)
                justifications.append(f"【依据】：累计启停次数过多（当前 {start_stop}），机械磨损加剧，增加背景风险评分。")
                level = 'P3'

    if '193' in metrics:
        load_unload = metrics['193']['raw']
        if load_unload > 300000:
            msg = f"Load_Cycle_Count is {load_unload} (>300,000)"
            if not is_failed and level not in ['P0', 'P1', 'P2']:
                diagnosis.append(msg)
                justifications.append(f"【依据】：累计磁头加载/卸载次数过高（当前 {load_unload}），机械疲劳严重。")
                level = 'P3'

    if not diagnosis:
        diagnosis.append("Healthy (All critical indicators normal)")
        justifications.append("【依据】：所有关键指标 RAW = 0 且 VALUE > THRESHOLD，符合健康标准。")
        level = 'OK'
        
    return level, is_failed, diagnosis, justifications

def main():
    parser = argparse.ArgumentParser(
        description="Automated SMART Disk Health Diagnosis Tool",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Examples:
  # The script will automatically detect whether the directory contains OS Infocollect logs or iBMC hardware logs
  python3 smart_diagnosis.py /opt/data/jinshan_cloud_log/disk_logs/10.107.18.37/infocollect_logs
  python3 smart_diagnosis.py /opt/data/jinshan_cloud_log/disk_logs/10.107.18.37/ibmc_logs/2102312CLGN0KC000952
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

    disks = []
    if scenario == 'infocollect':
        smart_files = find_files(root_dir, r'disk_smart\.txt$')
        for f in smart_files:
            disks.extend(parse_infocollect_smart(f))
    elif scenario == 'ibmc':
        smart_files = find_files(root_dir, r'PD_SMART_INFO_C.*')
        disks.extend(parse_ibmc_smart(smart_files))
    else:
        print("Could not determine log scenario or find SMART logs. Aborting.")
        sys.exit(1)
        
    # Parse external disk operations (reboots, hotplugs, rebuilds)
    disk_operations = parse_disk_operations(root_dir)

    # Remove duplicate devices (like /dev/sg* pointing to same physical disk as /dev/sd*)
    # For simplicity, if we have /dev/sda and /dev/sg0 with same serial, keep /dev/sda
    unique_disks = {}
    for d in disks:
        # If infocollect, prefer sdX over sgX
        sn = d['serial']
        dev = d['device']
        if sn not in unique_disks:
            unique_disks[sn] = d
        else:
            existing_dev = unique_disks[sn]['device']
            if dev.startswith('/dev/sd') and existing_dev.startswith('/dev/sg'):
                unique_disks[sn] = d

    disks = list(unique_disks.values())

    timestamp_str = datetime.now().strftime('%Y%m%d_%H%M%S')
    import random
    import string
    random_str = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
    output_file = f"/tmp/smart_diagnosis_report_{timestamp_str}_{random_str}.txt"
    
    with open(output_file, "w") as out:
        out.write("=============================================\n")
        out.write("  服务器磁盘健康预测与诊断报告\n")
        out.write("=============================================\n")
        out.write(f"检测执行时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        out.write(f"日志路径：{root_dir}\n")
        out.write(f"检测场景：{scenario.upper()}\n\n")

        out.write("（1）磁盘信息汇总\n")
        out.write("-" * 120 + "\n")
        out.write(f"{'Device':<15} | {'Model':<30} | {'Serial':<20} | {'Timestamp':<25} | {'Health':<10}\n")
        out.write("-" * 120 + "\n")
        for d in disks:
            out.write(f"{d['device']:<15} | {d['model'][:30]:<30} | {d['serial'][:20]:<20} | {d['timestamp'][:25]:<25} | {d['health']:<10}\n")
        out.write("\n")

        out.write("（2）磁盘故障或亚健康信息汇总\n")
        out.write("-" * 120 + "\n")
        has_issues = False
        for d in disks:
            level, is_failed, diag_msgs, justifications = evaluate_disk(d)
            if is_failed or level in ['P0', 'P1', 'P2']:
                has_issues = True
                out.write(f"【设备】 {d['device']} (SN: {d['serial']})\n")
                out.write(f"  - 风险等级: {level}\n")
                
                # Combine messages and justifications
                for i in range(len(diag_msgs)):
                    msg = diag_msgs[i]
                    justification = justifications[i] if i < len(justifications) else ""
                    
                    # Find which metric caused this to give precise coordinates
                    line_num = d['log_line']
                    # Try to find specific line for metrics
                    if "ID 198" in msg and '198' in d['metrics']:
                        line_num = d['metrics']['198']['line_num']
                    elif "ID 197" in msg and '197' in d['metrics']:
                        line_num = d['metrics']['197']['line_num']
                    elif "ID 5" in msg and '5' in d['metrics']:
                        line_num = d['metrics']['5']['line_num']
                    elif "Power_On_Hours" in msg and '9' in d['metrics']:
                        line_num = d['metrics']['9']['line_num']
                    
                    out.write(f"  - 异常表现: {msg}\n")
                    out.write(f"    坐标: 文件 {d['log_file']} , 第 {line_num} 行, 时间 {d['timestamp']}\n")
                    if justification:
                        out.write(f"    {justification}\n")
                out.write("\n")
        if not has_issues:
            out.write("未发现故障或亚健康磁盘。\n\n")

        out.write("（3）所有磁盘的诊断说明\n")
        out.write("-" * 120 + "\n")
        for d in disks:
            level, is_failed, diag_msgs, justifications = evaluate_disk(d)
            out.write(f"- {d['device']} ({d['serial']}): [{level}] {'; '.join(diag_msgs)}\n")
            if level == 'P0':
                out.write("  建议：🔴 致命故障或极高风险，立即换盘（数据可能已丢失或处于危险边缘）。\n")
            elif level == 'P1':
                out.write("  建议：🟡 亚健康或高危，建议准备备件并在近期（7天内）计划换盘。\n")
            elif level == 'P2':
                out.write("  建议：🟡 关注，增加巡检频率，密切观察指标变化。\n")
            elif level == 'P3':
                out.write("  建议：🟢 背景风险（如高龄盘），纳入下一批次换盘计划。\n")
            else:
                out.write("  建议：🟢 健康，继续保持日常监控。\n")
            out.write("\n")

        # Add section for System level disk operations (Reboot, Hot-plug, Rebuild)
        out.write("（4）系统级磁盘操作历史 (Reboots / Hot-plugs / Rebuilds)\n")
        out.write("-" * 120 + "\n")
        if not disk_operations:
            out.write("未在内核日志中检测到近期的系统重启、磁盘插拔或 RAID 重建动作。\n")
        else:
            # Show a summary timeline, cap at 30 events to avoid flooding
            if len(disk_operations) > 30:
                out.write(f"检测到大量磁盘相关操作，仅展示部分关键事件（已折叠 {len(disk_operations)-30} 条）：\n")
                # Show first 10 and last 20
                display_ops = disk_operations[:10] + disk_operations[-20:]
                
                for op in disk_operations[:10]:
                    out.write(f"[{op['timestamp']}] [{op['type']}] {op['full_line']} (来源: {os.path.basename(op['file_path'])})\n")
                out.write("......\n")
                for op in disk_operations[-20:]:
                    out.write(f"[{op['timestamp']}] [{op['type']}] {op['full_line']} (来源: {os.path.basename(op['file_path'])})\n")
            else:
                for op in disk_operations:
                    out.write(f"[{op['timestamp']}] [{op['type']}] {op['full_line']} (来源: {os.path.basename(op['file_path'])})\n")
            
        out.write("\n")

    print(f"诊断完成。结果已输出至 {output_file}")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
analyze_heap_trend.py — 堆增长趋势分析
多时间点堆快照对比，识别泄漏增长模式
使用: python3 analyze_heap_trend.py --pid PID [--interval SEC] [--count N] [--threshold KB]
"""
import subprocess, sys, time, argparse, json
from collections import defaultdict

def get_smaps_anon(pid):
    """获取进程匿名页统计"""
    try:
        out = subprocess.check_output(['grep', '-E', 'anonymous|heap|stack', f'/proc/{pid}/smaps'],
                                        stderr=subprocess.DEVNULL, timeout=5).decode()
        total_anon = 0
        for line in out.split('\n'):
            if 'Rss:' in line:
                kb = int(line.split()[1])
                total_anon += kb
        return total_anon
    except: return None

def get_proc_status(pid):
    """获取进程内存状态"""
    try:
        out = subprocess.check_output(['cat', f'/proc/{pid}/status'],
                                        timeout=3).decode()
        data = {}
        for line in out.split('\n'):
            for key in ['VmRSS', 'VmSize', 'VmPeak', 'VmData', 'VmStk', 'VmExe']:
                if line.startswith(key + ':'):
                    data[key] = line.split()[1]
        return data
    except: return {}

def get_smaps_detailed(pid):
    """获取详细匿名映射"""
    try:
        out = subprocess.check_output(
            ['grep', '-A1', r'^[0-9a-f]', f'/proc/{pid}/smaps'],
            stderr=subprocess.DEVNULL, timeout=5).decode()
        regions = defaultdict(lambda: {'rss': 0, 'pss': 0, 'anon': 0})
        current = None
        for line in out.split('\n'):
            if re.match(r'^[0-9a-f]', line):
                current = line.split()[-1] if len(line.split()) > 1 else 'anonymous'
            elif current and 'Rss:' in line:
                regions[current]['rss'] += int(line.split()[1])
            elif current and 'Pss:' in line:
                regions[current]['pss'] += int(line.split()[1])
            elif current and 'Anonymous:' in line:
                regions[current]['anon'] += int(line.split()[1])
        return dict(regions)
    except: return {}

def main():
    parser = argparse.ArgumentParser(description='堆增长趋势分析')
    parser.add_argument('--pid', '-p', required=True, type=int, help='目标进程 PID')
    parser.add_argument('--interval', '-i', type=int, default=10, help='采样间隔(秒)')
    parser.add_argument('--count', '-c', type=int, default=6, help='采样次数')
    parser.add_argument('--threshold', '-t', type=int, default=1024,
                        help='增长阈值(KB/次)，超过此值视为异常增长')
    args = parser.parse_args()

    pid = args.pid
    print(f'堆增长趋势分析 - PID {pid}')
    print(f'采样间隔: {args.interval}s, 采样次数: {args.count}')
    print(f'异常阈值: {args.threshold}KB/次')
    print()
    print(f'{"时间":>12s} {"VmRSS":>8s} {"VmSize":>8s} {"VmPeak":>8s} {"Anon":>8s} {"增量KB":>8s}')
    print('-' * 60)

    prev_rss = 0
    import re

    for i in range(args.count):
        status = get_proc_status(pid)
        anon = get_smaps_anon(pid)
        if not status:
            print(f'{"N/A":>12s} PID {pid} 不可访问')
            break

        rss = int(status.get('VmRSS', '0').rstrip('kB'))
        vsize = int(status.get('VmSize', '0').rstrip('kB'))
        peak = int(status.get('VmPeak', '0').rstrip('kB'))

        delta = rss - prev_rss if i > 0 else 0
        ts = time.strftime('%H:%M:%S')

        flag = ' <<<' if delta > args.threshold else ''
        print(f'{ts:>12s} {rss:>8d} {vsize:>8d} {peak:>8d} {anon or 0:>8d} {delta:>+8d}{flag}')

        prev_rss = rss

        if i < args.count - 1:
            time.sleep(args.interval)

    # 趋势判定
    print()
    print('--- 趋势分析 ---')
    if prev_rss > args.threshold * args.count:
        print(f'⚠ 检测到持续增长趋势 (总增长: {prev_rss}KB)')
        print(f'  建议: 检查可能存在内存泄漏')
        print(f'  下一步: valgrind --tool=massif 或 AddressSanitizer')
    else:
        print(f'✓ RSS 增长在正常范围内')

if __name__ == '__main__':
    main()

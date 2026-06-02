#!/usr/bin/env python3
# =============================================================================
# 脚本：pprof_to_folded.py
# 用途：将 Go pprof 原始格式转换为 folded 格式（与 stackcollapse-go.pl 保持一致）
# 使用：python3 pprof_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE     : 指定输入文件（go tool pprof -raw 输出）
#   --output FILE    : 指定输出文件（folded 格式）
#   --help / -h      : 显示帮助信息
# 说明：与 stackcollapse-go.pl 行为保持一致，支持 go tool pprof -raw 格式
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def pprof_raw_to_folded(content: str) -> str:
    """
    解析 go tool pprof -raw 输出格式，转换为 folded 格式
    
    输入格式示例：
        Samples:
        samples/count cpu/nanoseconds
             1   10000000: 1 2 
             2   10000000: 3 2 
             1   10000000: 4 2 
        Locations
             1: 0x58b265 scanblock :0 s=0
             2: 0x599530 GC :0 s=0
             3: 0x58a999 flushptrbuf :0 s=0
             4: 0x58d6a8 runtime.MSpan_Sweep :0 s=0
        Mappings
            ...
    
    输出格式示例：
        GC;flushptrbuf 2
        GC;runtime.MSpan_Sweep 1
        GC;scanblock 1
    """
    state = "ignore"
    stacks = defaultdict(int)
    frames = {}
    collapsed = defaultdict(int)

    for line in content.split('\n'):
        line = line.rstrip()
        
        # 跳过注释和空行
        if not line or line.startswith('#'):
            continue

        if state == "ignore":
            if line.startswith('Samples:'):
                state = "sample"
                continue

        elif state == "sample":
            # 匹配样本行："     1   10000000: 1 2 "
            sample_match = re.match(r'^\s*([0-9]+)\s*[0-9]+: ([0-9 ]+)$', line)
            if sample_match:
                count = int(sample_match.group(1))
                stack = sample_match.group(2).strip()
                stacks[stack] += count
            elif line.startswith('Locations'):
                state = "location"
                continue

        elif state == "location":
            # 匹配位置行："     1: 0x58b265 scanblock :0 s=0"
            # 或："     1: 0x58b265 M=1 scanblock :0 s=0"
            loc_match = re.match(r'^\s*([0-9]+): 0x[0-9a-fA-F]+(?: M=[0-9]+ )?([^ ]+)', line)
            if loc_match:
                loc_id = loc_match.group(1)
                loc_name = loc_match.group(2)
                frames[loc_id] = loc_name
            elif line.startswith('Mappings'):
                state = "mapping"
                break

    # 转换堆栈格式
    for stack_str, count in stacks.items():
        loc_list = stack_str.split()
        frame_names = []
        for loc_id in loc_list:
            if loc_id in frames:
                frame_names.append(frames[loc_id])
        
        # 反转顺序（内核到用户，与 stackcollapse-go.pl 一致）
        if frame_names:
            collapsed[';'.join(reversed(frame_names))] += count

    # 按字典序排序输出
    return '\n'.join(f"{stack} {count}" for stack, count in sorted(collapsed.items()))


def main():
    parser = argparse.ArgumentParser(
        description='将 Go pprof 原始格式转换为 folded 格式（与 stackcollapse-go.pl 保持一致）',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 pprof_to_folded.py --input profile.pprof --output out.folded
  cat profile.pprof | python3 pprof_to_folded.py > out.folded

生成输入文件的方法:
  go tool pprof -seconds=60 -raw -output=a.pprof http://$ADDR/debug/pprof/profile

与 stackcollapse-go.pl 行为保持一致：
- 支持 go tool pprof -raw 输出格式
- 栈帧顺序：从底向上（与 stackcollapse-go.pl 一致）
- 自动合并相同调用栈
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（go tool pprof -raw 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    # 读取内容
    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = pprof_raw_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()

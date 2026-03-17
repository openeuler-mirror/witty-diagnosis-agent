#!/usr/bin/env python3
"""
analyze_struct.py - Parse and analyze kernel data structures from crash output
"""

import sys
import re
import argparse
from typing import Dict, List, Tuple

def parse_struct_output(crash_output: str) -> Dict[str, str]:
    """Parse crash 'struct' command output into a dictionary."""
    struct_data = {}
    current_field = None
    
    for line in crash_output.split('\n'):
        # Match field lines like "  field_name = value"
        field_match = re.match(r'\s+(\w+)\s*=\s*(.+)', line)
        if field_match:
            field_name, value = field_match.groups()
            struct_data[field_name] = value.strip()
            current_field = field_name
        # Handle multi-line values
        elif current_field and line.strip() and not line.startswith('struct'):
            struct_data[current_field] += ' ' + line.strip()
    
    return struct_data

def format_task_struct(data: Dict[str, str]) -> str:
    """Format task_struct data into readable output."""
    output = []
    output.append("=" * 80)
    output.append("TASK STRUCTURE ANALYSIS")
    output.append("=" * 80)
    
    # Key fields for task analysis
    important_fields = [
        ('pid', 'Process ID'),
        ('comm', 'Command Name'),
        ('state', 'Task State'),
        ('flags', 'Task Flags'),
        ('mm', 'Memory Descriptor'),
        ('stack', 'Kernel Stack'),
        ('cpu', 'CPU Number'),
        ('prio', 'Priority'),
        ('static_prio', 'Static Priority'),
        ('normal_prio', 'Normal Priority'),
        ('rt_priority', 'RT Priority'),
    ]
    
    output.append("\nKey Information:")
    output.append("-" * 80)
    for field, description in important_fields:
        if field in data:
            output.append(f"  {description:.<25} {data[field]}")
    
    # State interpretation
    if 'state' in data:
        state_val = data['state']
        output.append("\nState Interpretation:")
        output.append("-" * 80)
        states = {
            '0': 'TASK_RUNNING',
            '1': 'TASK_INTERRUPTIBLE',
            '2': 'TASK_UNINTERRUPTIBLE',
            '4': 'TASK_STOPPED',
            '8': 'TASK_TRACED',
            '16': 'EXIT_ZOMBIE',
            '32': 'EXIT_DEAD',
        }
        for val, name in states.items():
            if val in state_val:
                output.append(f"  → {name}")
    
    output.append("\n" + "=" * 80)
    return '\n'.join(output)

def analyze_backtrace(bt_output: str) -> List[Tuple[int, str, str]]:
    """Parse backtrace output and extract frame information."""
    frames = []
    frame_pattern = re.compile(r'#(\d+)\s+\[([0-9a-fx]+)\]\s+(.+)')
    
    for line in bt_output.split('\n'):
        match = frame_pattern.match(line.strip())
        if match:
            frame_num = int(match.group(1))
            address = match.group(2)
            function = match.group(3)
            frames.append((frame_num, address, function))
    
    return frames

def format_backtrace(frames: List[Tuple[int, str, str]]) -> str:
    """Format backtrace in a readable manner."""
    output = []
    output.append("=" * 80)
    output.append("BACKTRACE ANALYSIS")
    output.append("=" * 80)
    
    for frame_num, address, function in frames:
        output.append(f"\nFrame #{frame_num}")
        output.append(f"  Address:  {address}")
        output.append(f"  Function: {function}")
        
        # Highlight potentially problematic functions
        if any(keyword in function.lower() for keyword in 
               ['panic', 'oops', 'bug', 'warn', 'error', 'fault']):
            output.append("  ⚠️  ATTENTION: Potential error condition")
    
    output.append("\n" + "=" * 80)
    return '\n'.join(output)

def main():
    parser = argparse.ArgumentParser(
        description='Analyze kernel data structures from crash output'
    )
    parser.add_argument(
        'input_file',
        help='File containing crash command output'
    )
    parser.add_argument(
        '--type',
        choices=['task', 'backtrace', 'auto'],
        default='auto',
        help='Type of structure to analyze'
    )
    
    args = parser.parse_args()
    
    try:
        with open(args.input_file, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File '{args.input_file}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Auto-detect content type if needed
    if args.type == 'auto':
        if 'struct task_struct' in content or 'comm =' in content:
            args.type = 'task'
        elif re.search(r'#\d+\s+\[0x', content):
            args.type = 'backtrace'
        else:
            print("Warning: Could not auto-detect type, defaulting to task")
            args.type = 'task'
    
    # Process based on type
    if args.type == 'task':
        struct_data = parse_struct_output(content)
        print(format_task_struct(struct_data))
    elif args.type == 'backtrace':
        frames = analyze_backtrace(content)
        print(format_backtrace(frames))

if __name__ == '__main__':
    main()
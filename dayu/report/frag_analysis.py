#!/usr/bin/env python3
import re

with open('/proc/1/maps') as f:
    regions = []
    for line in f:
        m = re.match(r'([0-9a-f]+)-([0-9a-f]+)', line)
        if m:
            start, end = int(m.group(1), 16), int(m.group(2), 16)
            regions.append((start, end, line.strip()))

regions.sort()

total_mapped = sum(e-s for s,e,_ in regions)
print(f"Total mapped memory: {total_mapped / 1024 / 1024:.1f} MB")
print(f"Total VMA count: {len(regions)}")

# Find gaps
max_gap = 0
max_gap_start = 0
max_gap_end = 0
small_gaps = 0  # gaps < 4KB
total_gap_space = 0

for i in range(len(regions)-1):
    gap = regions[i+1][0] - regions[i][1]
    if gap > 0:
        total_gap_space += gap
        if gap < 4096:
            small_gaps += 1
        if gap > max_gap:
            max_gap = gap
            max_gap_start = regions[i][1]
            max_gap_end = regions[i+1][0]

print(f"Max contiguous free region: {max_gap / 1024 / 1024:.1f} MB")
print(f"  (from 0x{max_gap_start:x} to 0x{max_gap_end:x})")
print(f"Total free gap space: {total_gap_space / 1024 / 1024:.1f} MB")
print(f"Total address space range: {max(regions[-1][1] for regions in [regions]) / 1024 / 1024 / 1024:.1f} GB")

# Analyze fragmentation severity
free_percent = (total_gap_space / max(regions[-1][1], 1)) * 100
print(f"Free space ratio: {free_percent:.1f}%")
print(f"Number of small gaps (<4KB): {small_gaps}")

# Assessment
print()
print("=== Fragmentation Assessment ===")
if max_gap < 128 * 1024 * 1024:
    print("CRITICAL: Max contiguous free region < 128 MB - high risk for large mmap allocations")
elif max_gap < 512 * 1024 * 1024:
    print("WARNING: Max contiguous free region < 512 MB - moderate risk for large mmap allocations")
else:
    print("OK: Sufficient contiguous free space available")

if total_gap_space < 256 * 1024 * 1024:
    print(f"WARNING: Very tight address space (total free only {total_gap_space/1024/1024:.0f} MB)")

# Count /dev/zero mappings
zero_count = sum(1 for _,_,l in regions if '/dev/zero' in l)
print(f"\n/dev/zero (deleted) mappings: {zero_count}")
if zero_count > 1000:
    print("HIGH: Large number of /dev/zero mappings detected - this is the likely root cause of fragmentation")

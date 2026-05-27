#!/bin/sh
echo "=== VMA type distribution ==="
cat /proc/1/maps | awk '{print $5}' | sort | uniq -c | sort -rn | head -n 20
echo ""
echo "=== Number of anonymous vs file-backed ==="
cat /proc/1/maps | awk '{print $5}' | awk '{if ($1 == "00:00" || $1 == "0") print "anon"; else print "file"}' | sort | uniq -c | sort -rn
echo ""
echo "=== First 30 lines of maps ==="
head -n 30 /proc/1/maps
echo ""
echo "=== Last 10 lines of maps ==="
tail -n 10 /proc/1/maps
echo ""
echo "=== Unique inode counts (top 30) ==="
cat /proc/1/maps | awk '{print $1, $5, $6}' | sort -k3 -rn | uniq -f2 -c | sort -rn | head -n 30

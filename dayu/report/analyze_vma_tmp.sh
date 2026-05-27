#!/bin/sh
cat /proc/1/maps | awk '{print $5}' | sort | uniq -c | sort -rn | head -n 20

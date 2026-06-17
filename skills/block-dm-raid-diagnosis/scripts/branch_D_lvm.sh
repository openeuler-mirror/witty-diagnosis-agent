#!/bin/bash
# Branch D: LVM Diagnosis
# Use when: PV missing, VG incomplete, LV inactive, thin pool full, snapshot overflow
# Usage: bash branch_D_lvm.sh [vg_name]
set -e
VG="${1:-}"
TIMEOUT="timeout 5"

echo "=========================================="
echo " Branch D: LVM Diagnosis"
[ -n "$VG" ] && echo " VG: $VG"
echo "=========================================="

# 1. Physical Volume check
echo ""
echo "--- 1. PV status ---"
$TIMEOUT pvs 2>/dev/null || echo "N/A"
echo "--- PV with all columns ---"
$TIMEOUT pvs -a -o +pv_used,pv_mda_count,pv_mda_size,pv_mda_free 2>/dev/null || echo "N/A"
echo "--- PV missing check ---"
$TIMEOUT pvs -o pv_name,pv_attr,pv_size,pe_count,pe_alloc_count 2>/dev/null || echo "N/A"

# 2. Volume Group check
echo ""
echo "--- 2. VG status ---"
if [ -n "$VG" ]; then
    $TIMEOUT vgs "$VG" -o +vg_missing_pv_count 2>/dev/null || echo "VG $VG not found"
    $TIMEOUT vgdisplay "$VG" 2>/dev/null || echo "vgdisplay failed"
    echo "--- VG attributes ---"
    $TIMEOUT vgs "$VG" -o vg_attr 2>/dev/null || echo "N/A"
else
    $TIMEOUT vgs -o +vg_missing_pv_count 2>/dev/null || echo "N/A"
    for vg in $($TIMEOUT vgs --noheadings -o vg_name 2>/dev/null); do
        echo "=== $vg ==="
        $TIMEOUT vgdisplay "$vg" 2>/dev/null | head -20 || echo "N/A"
    done
fi

# 3. Logical Volume check
echo ""
echo "--- 3. LV status ---"
if [ -n "$VG" ]; then
    $TIMEOUT lvs "$VG" -a -o +lv_attr,lv_size,data_percent,metadata_percent,snap_percent,lv_health_status,lv_role,devices 2>/dev/null || echo "N/A"
else
    $TIMEOUT lvs -a -o +lv_attr,lv_size,data_percent,metadata_percent,snap_percent,lv_health_status,lv_role,devices 2>/dev/null || echo "N/A"
fi

# 4. Thin pool deep check
echo ""
echo "--- 4. Thin pool analysis ---"
$TIMEOUT lvs -a -o lv_name,lv_attr,data_percent,metadata_percent,lv_size,data_lv,metadata_lv,pool_lv 2>/dev/null | grep -i thin || echo "(no thin pools)"
echo "--- Thin pool dmsetup status ---"
$TIMEOUT dmsetup status 2>/dev/null | grep -i thin | head -10 || echo "(none)"
echo "--- Thin pool kernel messages ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "dm-thin" | tail -10 || echo "(none)"

# 5. Snapshot check
echo ""
echo "--- 5. Snapshot analysis ---"
$TIMEOUT lvs -a -o lv_name,lv_attr,snap_percent,origin,cow_dtable_size,cow_size 2>/dev/null | grep -v "^$" || echo "(no snapshots)"

# 6. Activation check
echo ""
echo "--- 6. LV activation state ---"
$TIMEOUT lvs -o lv_name,lv_attr,lv_active 2>/dev/null | head -30 || echo "N/A"

# 7. Metadata check
echo ""
echo "--- 7. Metadata & archive ---"
echo "Backup: $(ls -la /etc/lvm/backup/ 2>/dev/null | head -5 || echo 'no backup dir')"
echo "Archive count: $(ls /etc/lvm/archive/ 2>/dev/null | wc -l || echo 'N/A')"
echo "--- LVM metadata seqno ---"
for vg in $($TIMEOUT vgs --noheadings -o vg_name 2>/dev/null); do
    seqno=$($TIMEOUT vgdisplay "$vg" 2>/dev/null | grep "Seq No" | awk '{print $NF}')
    echo "$vg seqno: $seqno"
done

# 8. LVM kernel messages
echo ""
echo "--- 8. LVM kernel messages ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "lvm\|device-mapper" | tail -10 || echo "N/A"

echo ""
echo "=========================================="
echo " Branch D analysis complete."
echo "=========================================="

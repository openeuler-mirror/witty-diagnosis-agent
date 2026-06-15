# Block Device / DM / RAID / LVM Fault Pattern Reference

## Pattern 1: High IO Wait / D-state Processes
**Symptoms**: System load high, `iostat %util` near 100%, multiple D-state processes, application hangs
**Possible Causes**:
- Device saturation (queue depth exhausted)
- Hardware errors causing IO retries
- DM thin pool out of space (metadata full)
- md RAID resync consuming all IO
- SCSI command timeouts
- Filesystem journal commit blocked

**Diagnostic Flow**:
1. `iostat -x 1 5` → identify victim device (%util, await, svctm)
2. `/sys/block/*/inflight` → check in-flight IO count
3. `/sys/block/*/stat` → check IO ticks vs wall time
4. `ps aux | grep ' D'` → check D-state process stacks
5. `dmesg | grep -E "I/O error|blk_update_request|hung_task"` → kernel-level errors
6. Check DM thin pool status if applicable
7. Check md RAID sync status if applicable

---

## Pattern 2: Device Timeout / IO Error
**Symptoms**: `dmesg` shows `blk_update_request: I/O error`, `Buffer I/O error`, applications get EIO
**Possible Causes**:
- Disk hardware failure (bad sector, failing HDD/SSD)
- Cable/backplane connection issue
- Controller / HBA failure
- SCSI command timeout
- NVMe PCIe error
- Multipath failover timing issue

**Diagnostic Flow**:
1. `dmesg | grep -E "I/O error|Buffer I/O|blk_update_request"` → locate device
2. `smartctl -a /dev/sdX` → SMART data (pending sectors, reallocated count, raw read errors)
3. `iostat -x -d 1 5` → check I/O errors per device
4. Check syslog/journal for SCSI/ATA transport errors
5. Check multipath status (if applicable)
6. For NVMe: check `nvme list`, `nvme error-log /dev/nvmeX`

---

## Pattern 3: Device Read-Only (RO)
**Symptoms**: Filesystem remounted read-only, `touch test` fails, `dmesg` shows `remounting filesystem read-only`
**Possible Causes**:
- Underlying device IO errors (hardware failure)
- Filesystem journal failure / corruption
- LVM snapshot overflow
- Device mapper failure
- Kernel forced RO due to unrecoverable IO error

**Diagnostic Flow**:
1. `mount | grep "ro,"` → identify RO mounts
2. `dmesg | grep "remount"` → find reason for RO remount
3. `dmsg | grep "I/O error"` → check underlying IO errors
4. `blockdev --getro /dev/sdX` → check ro flag
5. Check `/sys/block/*/ro` → not just filesystem RO, block device RO
6. Check if filesystem needs `fsck`
7. Trace DM dependency chain for RO propagation

---

## Pattern 4: md RAID Degraded
**Symptoms**: `/proc/mdstat` shows `[U_]` or indicates degraded state, system performance impacted
**Possible Causes**:
- Physical disk failure
- Cable/SAS expander issue
- Intermittent connection causing drive timeout
- Multiple drives failing simultaneously (correlated failure)
- md superblock mismatch / event count conflict

**Diagnostic Flow**:
1. `cat /proc/mdstat` → check `[UU]` vs `[_U]` vs `[U_]`
2. `mdadm --detail /dev/mdX` → identify failed device
3. `mdadm --examine /dev/sdX` → check event count per component
4. `/sys/block/mdX/md/rdN/state` → per-disk state
5. `dmesg | grep "md:"` → find fail events
6. Check smartctl for failing/disconnected drives
7. Compare event counts across components (should be equal)

---

## Pattern 5: LVM PV Missing / VG Incomplete
**Symptoms**: `pvs` shows unknown device, `lvs` shows LV not active, VG has missing PV count > 0
**Possible Causes**:
- Disk disconnected or failed
- Multipath mapping changed
- Disk path renamed (e.g., sdX -> sdY after reboot)
- LVM metadata corrupted on one PV
- Disk removed without proper vgreduce

**Diagnostic Flow**:
1. `pvs -a -o +pv_missing` → identify missing PVs
2. `vgs -o +vg_missing_pv_count` → check VG health
3. `dmsetup table` → verify underlying mapping exists
4. Check `/dev/disk/by-id/` for persistent names
5. Check if device reappeared under different name (`lsblk`)
6. `vgextend --restoremissing VG /dev/sdX` → if device is available but missing in metadata
7. If drive truly dead: `vgreduce --removemissing VG` to force remove

---

## Pattern 6: LVM Thin Pool Full
**Symptoms**: Writes fail on thin-provisioned volumes, `dmesg` shows `dm-thin: no free space`, applications report disk full
**Possible Causes**:
- Thin pool data volume exhausted
- Thin pool metadata volume exhausted
- Snapshots consuming excessive space
- No auto-extend configured or auto-extend threshold too low
- Too many snapshots filling metadata

**Diagnostic Flow**:
1. `lvs -a -o+data_percent,metadata_percent` → check utilization
2. `dmsetup status | grep thin` → check `<data_blocks>/<total_data_blocks> <metadata_blocks>/<total_metadata_blocks>`
3. `dmesg | grep "dm-thin"` → look for "no free space" messages
4. Check `/etc/lvm/lvm.conf` → `thin_pool_autoextend_threshold`
5. `lvextend -L+10G VG/thin_pool_tdata` → extend data volume
6. `lvextend -L+1G VG/thin_pool_tmeta` → extend metadata volume
7. Check for dangling snapshots that can be removed

---

## Pattern 7: DM Cache Performance Degradation
**Symptoms**: Cache device not improving performance, cache hit ratio very low
**Possible Causes**:
- Cache device too small for working set
- Cache policy mismatch
- Dirty cache blocking writes
- Migrate threshold too high
- Sequential IO bypassing cache
- Cache device wearing out (SSD endurance)

**Diagnostic Flow**:
1. `dmsetup status | grep cache` → check hit ratio, promotion/demotion counts
2. `dmsetup table | grep cache` → check cache params (migration threshold, sequential threshold)
3. Check cache device IO stats (`iostat -x`)
4. Check `smartctl` on SSD cache device
5. Consider changing cache policy (mapping mode)

---

## Pattern 8: Multipath Failover Issues
**Symptoms**: Multipath status shows failed/ghost paths, IO stalls during failover
**Possible Causes**:
- SAN/FC link failure
- Target port unavailable
- Path checker wrong type
- Internal array port failure
- Failover timeout too long (system hangs before switching paths)
- ALUA misconfiguration

**Diagnostic Flow**:
1. `multipath -ll` → check path states (active/enabled/failed/ghost)
2. `multipathd show paths` → detailed per-path status
3. `multipathd show status` → daemon health
4. `dmesg | grep -i "multipath"` → check for failover messages
5. `journalctl -u multipathd -n 50` → multipathd logs
6. Check SAN switches / FC connectivity
7. Verify `path_checker` matches array type
8. Check `prio` settings for ALUA arrays

---

## Pattern 9: IO Scheduler Misconfiguration
**Symptoms**: Unexpectedly low throughput, high latency despite low utilization
**Possible Causes**:
- Wrong IO scheduler for hardware type (CFQ on NVMe)
- `nr_requests` too small limiting depth
- `max_sectors_kb` too small reducing throughput
- Read-ahead too low for sequential workloads
- WBT thrashing on fast SSDs
- IO merging disabled (`nomerges=2`)

**Diagnostic Flow**:
1. Check `scheduler` — `none` for NVMe, `mq-deadline`/`kyber` for SSD, `bfq` for HDD
2. Check `nr_requests` — increase for deep queue devices
3. Check `max_sectors_kb` — increase for NVMe (up to 1280+)
4. Check `rotational` — 0 for SSD, 1 for HDD
5. For latency issues: check `wbt_lat_usec` (disable with 0 for NVMe)
6. Benchmark with `fio` to validate after changes

---

## Pattern 10: Filesystem-level Latency
**Symptoms**: High `iowait`, `await` moderate but application-level IO slow, `sync` takes long
**Possible Causes**:
- Journal commit frequency too slow
- Barrier/fua overhead on storage
- Dirty page ratio too high
- FS fragmentation
- XFS log busy / AG lock contention
- EXT4 journal checksum errors

**Diagnostic Flow**:
1. `iostat -x 1` → check `await`, `svctm`, `%util`
2. `vmstat 1` → check `bo` (blocks out), `bi` (blocks in), `wa`
3. `sysctl vm.dirty_ratio` → check dirty page limits
4. Check mount options (`barrier`, `noatime`, `data=ordered` vs `writeback`)
5. `dmesg | grep -E "EXT.*error|XFS.*error|journal"` → FS-level errors
6. For XFS: `xfs_info` → check allocation group settings

---

## Pattern 11: Component Event Count Mismatch (md RAID)
**Symptoms**: md RAID fails to assemble, superblock event count differs across drives
**Possible Causes**:
- Disk was offline while array continued operating
- Drive replacement without proper mdadm management
- Split-brain (dual writes with missing drives)
- Newer replacement drive with firmware zeroed superblock

**Diagnostic Flow**:
1. `mdadm --examine /dev/sdX1` for each component → compare `Events` field
2. The component with the lowest event count has stale data
3. `mdadm --assemble --force /dev/mdX /dev/sdX1 /dev/sdY1` → force assembly with majority
4. `mdadm --manage /dev/mdX --re-add /dev/sdZ1` → if drive was removed and reattached

---

## Pattern 12: DM Target Loop / Stack Overflow
**Symptoms**: Unable to remove DM device, infinite dependency chain, `dmsetup` hangs
**Possible Causes**:
- Circular DM dependency (accidental stacking)
- DM table points to self
- Reference count leak (open device)
- User error in `dmsetup create` parameters

**Diagnostic Flow**:
1. `dmsetup deps` → check each device for circular deps
2. `dmsetup table` → check target params point back to themselves
3. `ls -la /sys/block/*/holders` → check hold chains
4. `dmsetup remove -f device` → force removal if stuck
5. Reboot as last resort

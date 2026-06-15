# Block Device / DM / RAID / LVM Command Reference

## 1. Block Device Commands

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `lsblk` | List block devices (tree view) | `-o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,ROTA`, `-s` (reverse dependencies), `-t` (topology) |
| `blkid` | Show block device attributes/FS type | `-o export`, `-p` (probe) |
| `iostat -x` | Extended I/O statistics per device | `-x` (extended), `-d` (device only), interval count |
| `iostat -x -m 1 5` | 5 samples of per-device stats in MB | |
| `blockdev` | Query/set block device parameters | `--getra` (read-ahead), `--getbsz` (block size), `--getsize64` (size) |
| `fdisk -l` | List partition tables | `-l` list, `-x` detail |
| `parted -l` | Detailed partition info | |
| `/sys/block/*/stat` | Raw I/O counters (read-only) | Fields: read IOs, read merges, read sectors, read ticks, write IOs, write merges, write sectors, write ticks, in-flight, I/O ticks, time-in-queue |
| `/sys/block/*/inflight` | Current in-flight I/O count | |
| `/proc/diskstats` | All disk I/O statistics | |
| `smartctl -a /dev/sdX` | SMART data (health, errors, temperature) | `-a` (all), `-H` (health summary), `-l error` (error log) |

## 2. I/O Scheduling

| Command | Purpose | Notes |
|---------|---------|-------|
| `/sys/block/*/queue/scheduler` | Get/set I/O scheduler | `[mq-deadline] none` (bracket=active) |
| `/sys/block/*/queue/nr_requests` | Queue depth | Default 128-512 |
| `/sys/block/*/queue/read_ahead_kb` | Read-ahead in KB | |
| `/sys/block/*/queue/max_sectors_kb` | Max IO size per request | |
| `/sys/block/*/queue/nomerges` | Disable IO merging | 0=all, 1=simple, 2=none |
| `/sys/block/*/queue/rq_affinity` | Request CPU affinity | 1=best CPU, 2=strictly |
| `/sys/block/*/queue/rotational` | 0=SSD, 1=HDD | |
| `/sys/block/*/queue/wbt_lat_usec` | Write-back throttle latency target | 0=disabled |
| `/sys/block/*/queue/write_cache` | Write cache setting | write back / write through |

## 3. Device-Mapper (dmsetup)

| Command | Purpose | Key Output |
|---------|---------|------------|
| `dmsetup ls` | List DM devices | Name, major:minor |
| `dmsetup ls --tree` | Tree view of DM stack | Shows parent-child relationships |
| `dmsetup deps` | Show device dependencies | e.g., `1 dependencies : (8:16)` |
| `dmsetup table` | Show mapping table (target type, params) | Target types: `linear`, `striped`, `mirror`, `snapshot`, `thin`, `cache`, `crypt`, `multipath`, `era`, `flakey` (testing) |
| `dmsetup status` | Show runtime status (thin/cache metadata) | Thin: `1048576/8388608` = metadata used/total |
| `dmsetup info` | Show device info | `State: ACTIVE/SUSPENDED`, `Open count`, `Target count` |
| `dmsetup message` | Send control message | Used for thin pool trim (e.g., `release_metadata_snap`) |
| `dmsetup suspend` | Suspend a DM device | |
| `dmsetup resume` | Resume a DM device | |

### DM Target Types Quick Reference

| Target | Table Column 3 | Status Key Fields |
|--------|---------------|-------------------|
| linear | `linear` | - |
| striped | `striped` | Stripe size |
| mirror | `mirror` | `100%` or `A` (alive) / `D` (dead) |
| snapshot | `snapshot` | Metadata usage |
| snapshot-origin | `snapshot-origin` | - |
| thin-pool | `thin-pool` | Data%, Metadata%, Holders |
| thin | `thin` | External origin, Transaction ID |
| cache | `cache` | Metadata, Cache hit ratio, Promotions |
| crypt | `crypt` | cipher, key size |
| multipath | `multipath` | Path selector, path count, fail count |
| flakey | `flakey` | Up/down interval (fault injection) |

## 4. md RAID (mdadm)

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `cat /proc/mdstat` | RAID status summary | `[UU]` = both up, `[_U]` = one degraded |
| `mdadm --detail /dev/mdX` | Detailed array info | Level, RaidDisks, TotalDevices, State |
| `mdadm --examine /dev/sdX` | Examine component device superblock | Events, Role, State, Array UUID |
| `mdadm --detail --scan` | Scan all arrays | Useful for config |
| `mdadm --examine --scan` | Scan all components | Useful for assembly |
| `mdadm --manage /dev/mdX --re-add /dev/sdX` | Re-add a failed disk | |
| `/sys/block/mdX/md/` | sysfs md attributes | See below |

### md sysfs Attributes

| File | Purpose |
|------|---------|
| `mismatch_cnt` | Data inconsistency count (scrub-detected) |
| `sync_action` | Current sync action: `idle`, `check`, `repair`, `resync`, `recover` |
| `sync_completed` | Resync/resilver progress (sectors completed / total) |
| `sync_speed_min` | Min sync speed (KB/s) |
| `sync_speed_max` | Max sync speed (KB/s) |
| `degraded` | Number of degraded/missing drives |
| `raid_disks` | Total disks in the array |
| `chunk_size` | RAID chunk size |
| `layout` | RAID layout (for RAID5/6) |
| `level` | RAID level |
| `rdN/block` | Block device for disk N |
| `rdN/state` | State of disk N: `in_sync`, `Faulty`, `spare`, `remove` |

### md RAID States in /proc/mdstat

| Pattern | Meaning |
|---------|---------|
| `[UU]` | All disks healthy |
| `[_U]` | One disk missing/failed (degraded) |
| `[U_]` | Active disk failed, spare rebuilding |
| `(F)` | Failed disk flagged |
| `(S)` | Spare disk |
| `removal` | Disk being removed |
| `sync = X%` | Resync/rebuild in progress |

## 5. LVM Commands

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `pvs` | List Physical Volumes | `-o +pv_used,pv_mda_count` |
| `pvs -a` | Include missing PVs | For fault diagnosis |
| `pvdisplay /dev/sdX` | PV details | |
| `pvck /dev/sdX` | Check PV metadata integrity | |
| `vgs` | List Volume Groups | `-o +vg_missing_pv_count` |
| `vgdisplay VG` | VG details | Shows PE size, extent counts, missing PVs |
| `vgck VG` | Check VG metadata | |
| `vgreduce --removemissing VG` | Remove missing PVs from VG | |
| `lvs` | List Logical Volumes | `-a` include internal, `-o +devices` |
| `lvs -a -o +data_percent,metadata_percent` | Thin pool utilization | |
| `lvdisplay /dev/VG/LV` | LV details | |
| `lvchange -ay VG/LV` | Activate an LV | `-ay` activate all |
| `lvchange -an VG/LV` | Deactivate an LV | |
| `dmsetup info -c` | All DM devices info | `-o suspended` to filter |

### LVM Health Status Values

| `lv_attr` field | Position 5 (Health) | Meaning |
|-----------------|---------------------|---------|
| `-` | Normal | No health issue |
| `p` | Partial | Some PVs missing, data at risk |
| `r` | Refresh needed | Metadata refresh required |
| `m` | Mismatch | Data mismatch detected |
| `s` | Snapshot | Snapshot metadata issue |

## 6. Multipath Commands

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `multipath -ll` | List multipath topology (detailed) | `-l` (short), `-ll` (long with status) |
| `multipath -t` | Show configuration | |
| `multipath -f /dev/mapper/mpathX` | Flush/remove a multipath device | |
| `multipathd show maps` | Show multipath maps | |
| `multipathd show paths` | Show all paths with status | |
| `multipathd show status` | Daemon status info | |
| `multipathd -k"reconfigure"` | Reload configuration | |
| `multipathd -k"del map mpathX"` | Remove a map | |
| `systemctl status multipathd` | Daemon unit status | |
| `journalctl -u multipathd -n 50` | Daemon recent logs | |
| `/etc/multipath.conf` | Main config file | |
| `/etc/multipath/bindings` | WWID-to-device bindings | |

### Multipath Path States

| State | Meaning |
|-------|---------|
| `active` | Path ready for I/O |
| `enabled` | Path enabled but not currently used (active/passive) |
| `failed` | Path permanently failed |
| `ghost` | Path in "ghost" state (TPGS ALUA, not yet active) |
| `undef` | Unknown state |

### Path Checker Types (`path_checker`)

| Checker | Mechanism | When to Use |
|---------|-----------|-------------|
| `tur` | Test Unit Ready (SCSI) | Default, most compatible |
| `readsector0` | Read first sector | Legacy |
| `emc_clariion` | EMC-specific inquiry | EMC arrays |
| `hp_sw` | HP-specific | HP arrays |
| `rdac` | RDAC mode | LSI/NetApp RDAC |

## 7. Kernel Parameters

| Parameter | Path | Purpose |
|-----------|------|---------|
| IO scheduler | `/sys/block/*/queue/scheduler` | Set active IO scheduler |
| nr_requests | `/sys/block/*/queue/nr_requests` | I/O queue depth |
| read_ahead_kb | `/sys/block/*/queue/read_ahead_kb` | Read-ahead cache |
| max_sectors_kb | `/sys/block/*/queue/max_sectors_kb` | Max I/O request size |
| wbt_lat_usec | `/sys/block/*/queue/wbt_lat_usec` | WBT latency target |
| raid_speed_limit_min | `/proc/sys/dev/raid/speed_limit_min` | Min rebuild speed (KB/s) |
| raid_speed_limit_max | `/proc/sys/dev/raid/speed_limit_max` | Max rebuild speed (KB/s) |
| vm.dirty_ratio | `sysctl -w vm.dirty_ratio` | Max dirty page % |
| vm.dirty_background_ratio | `sysctl -w vm.dirty_background_ratio` | Dirty page bg flush % |
| vm.dirty_expire_centisecs | `sysctl -w vm.dirty_expire_centisecs` | Dirty page expiry |

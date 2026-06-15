# Block / DM / RAID Key Tuning Parameters

## IO Scheduler Selection Guide

| Hardware | Recommended Scheduler | Rationale |
|----------|----------------------|-----------|
| NVMe SSD | `none` (noop) | Device manages its own queue; any scheduler adds overhead |
| SATA/SAS SSD | `mq-deadline` or `kyber` | Latency-oriented; kyber good for consistent QoS |
| HDD (spinning) | `bfq` or `mq-deadline` | BFQ provides fairness; deadline good for latency bounds |
| Virtual/Cloud disk | `none` | Hypervisor handles scheduling |
| RAID (hardware) | `none` or `mq-deadline` | HW RAID controller does scheduling |

## Queue Depth Tuning

| Device Type | `nr_requests` | `max_sectors_kb` | Effect |
|-------------|---------------|------------------|--------|
| NVMe | 1024-4096 | 1280-4096 | High throughput, deep queue |
| SATA SSD | 512-1024 | 1280 | Good sequential perf |
| HDD | 128-512 | 512 | Avoid queue saturation |
| Virtual disk | 256-512 | 1024 | Moderate |

## Write-Back Throttling (WBT)

| Device Type | `wbt_lat_usec` | Effect |
|-------------|----------------|--------|
| NVMe (low latency) | 0 (disable) | Full write speed |
| SATA SSD | 10-50 | Balance latency/throughput |
| HDD | 200-2000 | Control write bursts |
| Default | 75 | General purpose |

## Dirty Page Ratios

| Setting | Default | Tuning Direction |
|---------|---------|------------------|
| `vm.dirty_ratio` | 20% | Increase for write-heavy sequential IO |
| `vm.dirty_background_ratio` | 10% | Increase if `dirty_ratio` increased |
| `vm.dirty_expire_centisecs` | 3000 (30s) | Decrease for data safety, increase for throughput |
| `vm.dirty_writeback_centisecs` | 500 (5s) | Wakeup interval for flusher threads |

## md RAID Speed Tuning

| Parameter | Default | Tuning |
|-----------|---------|--------|
| `/proc/sys/dev/raid/speed_limit_min` | 1000 KB/s | Increase to speed up rebuilds |
| `/proc/sys/dev/raid/speed_limit_max` | 200000 KB/s | Increase if drives can handle more |
| `bitmap` on md | Disabled | Enables local-write reduction, speeds up recovery |

## LVM Auto-Extend

| lvm.conf Parameter | Default | Recommendation |
|-------------------|---------|----------------|
| `thin_pool_autoextend_threshold` | 100 (off) | Set to 75-80 to auto-extend at 80% |
| `thin_pool_autoextend_percent` | 20 | Extend by 20% each time above threshold |

## Multipath Tuning

| multipath.conf Param | Default | Recommendation |
|---------------------|---------|----------------|
| `polling_interval` | 5s | Decrease to 1-3s for faster failover |
| `path_grouping_policy` | failover | `multibus` for ALUA, `failover` for simple |
| `path_selector` | `service-time 0` | `round-robin 0` for simple load balancing |
| `no_path_retry` | 0 (fail immediate) | Set to `3-5` for retries before IO error |
| `prio` | const | Use `alua` for ALUA arrays |
| `rr_min_io` | 1000 | Lower for balanced load across paths |

## Comparison: Block Device Relevant `/sys` Files

| Path | Read/Write | Purpose |
|------|-----------|---------|
| `/sys/block/*/stat` | R | IO counters |
| `/sys/block/*/device/serial` | R | Drive serial number |
| `/sys/block/*/device/vendor` | R | Drive vendor |
| `/sys/block/*/device/model` | R | Drive model |
| `/sys/block/*/device/timeout` | RW | SCSI command timeout (s) |
| `/sys/block/*/queue/scheduler` | RW | IO scheduler |
| `/sys/block/*/queue/nr_requests` | RW | Queue depth |
| `/sys/block/*/queue/read_ahead_kb` | RW | Read-ahead size |
| `/sys/block/*/queue/max_sectors_kb` | RW | Max IO size |
| `/sys/block/*/queue/rotational` | RW | Rotational flag |
| `/sys/block/*/queue/rq_affinity` | RW | Request CPU placement |
| `/sys/block/*/queue/wbt_lat_usec` | RW | Write-back throttle latency |
| `/sys/block/*/queue/nomerges` | RW | Disable merges |
| `/sys/block/*/inflight` | R | Current in-flight IOs |
| `/sys/block/*/ro` | R | Read-only flag |
| `/sys/block/*/size` | R | Size in sectors |
| `/sys/block/md*/md/mismatch_cnt` | R | RAID data inconsistency count |
| `/sys/block/md*/md/sync_action` | RW | Trigger check/repair |
| `/sys/block/md*/md/degraded` | R | Number of degraded drives |
| `/sys/block/md*/md/rd*/state` | R | Per-disk state |

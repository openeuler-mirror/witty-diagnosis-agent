# Sample io_uring Diagnosis Report

## Summary

- Case ID: sample-memlock-fixed-buffer
- Host: openEuler test VM
- Kernel: collected by `uname -a`
- Process/PID: io_uring fault probe
- Failure window: test execution window
- Classification: resource-limit
- Confidence: medium in sample, high when runtime log and limits are both present

## User-visible Symptom

The test program creates an io_uring instance and attempts to register a 4 MiB
fixed buffer while the child shell has a low locked-memory limit.

## Evidence

| Evidence | Source | Interpretation |
| --- | --- | --- |
| `ulimit -l=64` | `run.sh run memlock` output | locked memory limit is intentionally constrained |
| `io_uring_register_buffers` returns errno | probe output | fixed buffer registration reached kernel resource validation |
| `registered_buffer_bytes=4194304` | probe output | requested buffer size is larger than the low memlock limit |

## Root Cause Analysis

The expected root cause is `RLIMIT_MEMLOCK` limiting fixed-buffer registration.
The failure occurs during `io_uring_register` rather than ring setup or CQ
consumption.

## Excluded Causes

- Ring setup failure is excluded when `io_uring_setup` succeeds.
- CQ overflow is excluded because no SQE workload is submitted in this scenario.
- O_DIRECT alignment is excluded because no O_DIRECT file operation is used.

## Recommendations

Read-only:

- Confirm `/proc/<pid>/limits` or shell `ulimit -l` during the failing run.
- Compare requested registered buffer bytes with the locked-memory limit.
- Check cgroup memory pressure if memlock is not the limiting factor.

Requires approval in a test environment:

- Re-run the same probe with a higher locked-memory limit.
- Reduce registered buffer size and confirm registration succeeds.

## Commands Run

```bash
./run.sh build
./run.sh run memlock
../../skills/kernel-io-uring-diagnosis/scripts/diagnose_io_uring_limits.sh -l ./out/memlock.log
```

## Cleanup

```bash
./run.sh clean
```
